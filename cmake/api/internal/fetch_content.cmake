if(NOT COMMAND weld_fetch_content)
   include(FetchContent)

   function(weld_fetch_content dep fallback)

      # repo@tag
      if(${fallback} MATCHES "^([^@]+)@(.+)$")
         set(repo_url "${CMAKE_MATCH_1}")
         set(tag     "${CMAKE_MATCH_2}")

         # host:repo@tag format
         if(${repo_url} MATCHES "^([A-Za-z0-9_-]+):([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$")
            set(host "${CMAKE_MATCH_1}")
            set(repo "${CMAKE_MATCH_2}")

            if(host STREQUAL "gh")
               set(git_url "https://github.com/${repo}.git")
            elseif(host STREQUAL "gl")
               set(git_url "https://gitlab.com/${repo}.git")
            elseif(host STREQUAL "bb")
               set(git_url "https://bitbucket.org/${repo}.git")
            else()
               message(FATAL_ERROR "[weld] Unsupported host '${host}' given for ${dep} fallback. Use 'gh' for GitHub, 'gl' for 'GitLab' or 'bb' for BitBucket or a full git url if the repo is hosted on an unsupported platform.")
            endif()
         else()
            # full url given, use as is
            set(git_url ${repo_url})
         endif()

         FetchContent_Declare(
            ${dep}
            GIT_REPOSITORY ${git_url}
            GIT_TAG        ${tag}
            GIT_SHALLOW    TRUE
         )
      else()
         # not a git repo, fetch the URL directly
         FetchContent_Declare(
            ${dep}
            URL ${fallback}
         )
      endif()

      FetchContent_MakeAvailable(${dep})
   endfunction()
endif()