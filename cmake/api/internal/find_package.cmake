include(${CMAKE_CURRENT_LIST_DIR}/fetch_content.cmake)

 if(NOT COMMAND weld_find_package)
    function(weld_find_package dep)
        set(options REQUIRED)
        set(oneValueArgs)
        set(multiValueArgs)
        cmake_parse_arguments(PARSE_ARGV 1 find
            "${options}" "${oneValueArgs}" "${multiValueArgs}"
        )

        if(${PROJECT_NAME}_${dep}_FALLBACK)
            find_package(${${PROJECT_NAME}_${dep}_FIND_NAME} ${${PROJECT_NAME}_${dep}_VERSION} ${find_UNPARSED_ARGUMENTS})
            if(NOT ${dep}_FOUND)
                weld_fetch_content(${${PROJECT_NAME}_${dep}_FIND_NAME} ${PROJECT_NAME}_${dep}_FALLBACK)
            endif()
        elseif(find_REQUIRED)
            find_package(${${PROJECT_NAME}_${dep}_FIND_NAME} ${${PROJECT_NAME}_${dep}_VERSION} REQUIRED ${find_UNPARSED_ARGUMENTS})
        else()
            find_package(${${PROJECT_NAME}_${dep}_FIND_NAME} ${${PROJECT_NAME}_${dep}_VERSION} ${find_UNPARSED_ARGUMENTS})
        endif()
   endfunction()
endif()