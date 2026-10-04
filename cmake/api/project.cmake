include(${WELD_API_DIR}/internal/dep_file.cmake)
include(${WELD_API_DIR}/internal/find_package.cmake)
include(${WELD_API_DIR}/internal/conan.cmake)

if(NOT COMMAND weld_project)
    function(weld_project)
        set(options USE_DEP_FILE)
        set(oneValueArgs DEFAULT_STD)
        set(multiValueArgs)
        cmake_parse_arguments(PARSE_ARGV 0 pack
            "${options}" "${oneValueArgs}" "${multiValueArgs}"
        )

        if(DEFINED pack_DEFAULT_STD)
            set(${PROJECT_NAME}_DEFAULT_STD "${pack_DEFAULT_STD}" CACHE INTERNAL "" FORCE)
        else()
            unset(${PROJECT_NAME}_DEFAULT_STD CACHE)
        endif()

        set(${PROJECT_NAME}_USE_DEP_FILE ${pack_USE_DEP_FILE} CACHE INTERNAL "" FORCE)

        unset(${PROJECT_NAME}_LIBRARIES CACHE)
        unset(${PROJECT_NAME}_EXECUTABLES CACHE)
        unset(${PROJECT_NAME}_EXAMPLES CACHE)
        unset(${PROJECT_NAME}_TESTS CACHE)

        option(${PROJECT_NAME}_BUILD_TESTS "Build tests" ${PROJECT_IS_TOP_LEVEL})
        option(${PROJECT_NAME}_BUILD_EXAMPLES "Build examples" ${PROJECT_IS_TOP_LEVEL})
        option(${PROJECT_NAME}_INSTALL "Install targets" ${PROJECT_IS_TOP_LEVEL})
        option(${PROJECT_NAME}_WELD_DEV_LOGS "Generate log messages aimed at the package developpers" ${PROJECT_IS_TOP_LEVEL})
        option(${PROJECT_NAME}_COMPILE_COMMANDS "Generate a compile_commands.json for the targets" ${PROJECT_IS_TOP_LEVEL})

        # ---- Default to a release-like build only when top level.
        if(PROJECT_IS_TOP_LEVEL)
            if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
                set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
                set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
                            Debug Release RelWithDebInfo MinSizeRel)
            endif()
        endif()

        if(${PROJECT_NAME}_INSTALL)
            include(CMakePackageConfigHelpers)
            include(GNUInstallDirs)
        endif()

        if(${PROJECT_NAME}_USE_DEP_FILE)
            weld_parse_dep_file()

            foreach(dep IN LISTS ${PROJECT_NAME}_CORE_DEPS)
                weld_find_package(${dep} REQUIRED)
            endforeach()

            foreach(dep IN LISTS ${PROJECT_NAME}_OPTIONAL_DEPS)
                weld_find_package(${dep})
            endforeach()

            if(${PROJECT_NAME}_BUILD_TESTS)
                foreach(dep IN LISTS ${PROJECT_NAME}_TESTS_DEPS)
                    weld_find_package(${dep} REQUIRED)
                endforeach()
            endif()

            if(${PROJECT_NAME}_BUILD_EXAMPLES)
                foreach(dep IN LISTS ${PROJECT_NAME}_EXAMPLES_DEPS)
                    weld_find_package(${dep} REQUIRED)
                endforeach()
            endif()
        endif()
    endfunction()
endif()

if(NOT COMMAND weld_dependency)
    function(weld_dependency dep)
        if(${PROJECT_NAME}_USE_DEP_FILE)
            message(FATAL_ERROR "[weld] ${PROJECT_NAME} has been configured to use a dep file so calls to weld_dependency() are forbiden. Choose one approach or the other.")
        endif()

        set(options FOR_EXAMPLES FOR_TESTS OPTIONAL)
        set(oneValueArgs VERSION FALLBACK)
        set(multiValueArgs)
        cmake_parse_arguments(PARSE_ARGV 1 dep
            "${options}" "${oneValueArgs}" "${multiValueArgs}"
        )

        if(dep_FOR_TESTS AND NOT ${PROJECT_NAME}_BUILD_TESTS)
            return()
        endif()

        if(dep_FOR_EXAMPLES AND NOT ${PROJECT_NAME}_BUILD_EXAMPLES)
            return()
        endif()

        if(DEFINED dep_VERSION)
            list(APPEND find_args "${dep_VERSION}")
            set(${PROJECT_NAME}_${dep}_VERSION ${dep_VERSION} PARENT_SCOPE)
        else()
            set(${PROJECT_NAME}_${dep}_VERSION "" PARENT_SCOPE)
        endif()

        if(DEFINED dep_FALLBACK)
            set(${PROJECT_NAME}_${dep}_FALLBACK ${dep_FALLBACK})
        endif()

        if(NOT dep_OPTIONAL)
            list(APPEND find_args "REQUIRED")
        endif()

        set(${PROJECT_NAME}_${dep}_FIND_NAME ${dep})

        weld_find_package(${dep} ${find_args} ${dep_UNPARSED_ARGUMENTS})

        list(APPEND ${PROJECT_NAME}_ALL_DEPS ${dep})
        set(${PROJECT_NAME}_ALL_DEPS ${${PROJECT_NAME}_ALL_DEPS} PARENT_SCOPE)

        if(dep_FOR_TESTS)
            list(APPEND ${PROJECT_NAME}_TESTS_DEPS ${dep})
            set(${PROJECT_NAME}_TESTS_DEPS ${${PROJECT_NAME}_TESTS_DEPS} PARENT_SCOPE)
        elseif(dep_FOR_EXAMPLES)
            list(APPEND ${PROJECT_NAME}_EXAMPLES_DEPS ${dep})
            set(${PROJECT_NAME}_EXAMPLES_DEPS ${${PROJECT_NAME}_EXAMPLES_DEPS} PARENT_SCOPE)
        else()
            list(APPEND ${PROJECT_NAME}_CORE_DEPS ${dep})
            set(${PROJECT_NAME}_CORE_DEPS ${${PROJECT_NAME}_CORE_DEPS} PARENT_SCOPE)
        endif()

        if(dep_OPTIONAL)
            list(APPEND ${PROJECT_NAME}_OPTIONAL_DEPS ${dep})
            set(${PROJECT_NAME}_OPTIONAL_DEPS ${${PROJECT_NAME}_OPTIONAL_DEPS} PARENT_SCOPE)
        endif()
    endfunction()
endif()

if(NOT COMMAND weld_build)
    function(weld_build)
        set(comp_types src apps tests)
        foreach(comp_type IN LISTS comp_types)
            if(comp_type STREQUAL "tests")
                if(${PROJECT_NAME}_BUILD_TESTS)
                    enable_testing()
                else()
                    continue()
                endif()
            endif()
            set(dir ${CMAKE_CURRENT_LIST_DIR}/${comp_type})
            if(EXISTS ${dir})
                if(EXISTS ${dir}/CMakeLists.txt)
                    add_subdirectory(${dir})
                else()
                    message(WARNING "[weld] ${dir} folder detected without a CMakeLists.txt file inside. Consider removing the folder if unused or add a CMakeLists.txt if missing.")
                endif()
            endif()
        endforeach()

        if(${PROJECT_NAME}_BUILD_TESTS)
            add_custom_target(
                run-tests
                ${CMAKE_CTEST_COMMAND}
                DEPENDS ${${PROJECT_NAME}_TESTS}
                WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/tests
            )
        endif()

        if(${PROJECT_NAME}_INSTALL)
            if(${PROJECT_NAME}-targets)
                install(
                    EXPORT ${PROJECT_NAME}-targets
                    FILE ${PROJECT_NAME}-targets.cmake
                    NAMESPACE ${PROJECT_NAME}::
                    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/${PROJECT_NAME}
                )
            endif()

            write_basic_package_version_file(
                ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}-config-version.cmake
                VERSION ${PROJECT_VERSION}
                COMPATIBILITY SameMajorVersion
            )

            # Export the dependencies too, so find_package(${PROJECT_NAME}) finds them as well.
            set(config_deps_file ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}-config-dependencies.cmake)
            file(WRITE ${config_deps_file} "include(CMakeFindDependencyMacro)\n")
            foreach(dep IN LISTS ${PROJECT_NAME}_CORE_DEPS)
                file(APPEND ${config_deps_file} "find_dependency(${dep})\n")
            endforeach()

            set(config_input ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}-config.cmake.in)
            file(WRITE ${config_input} "@PACKAGE_INIT@\n")
            file(APPEND ${config_input} "include(\"\${CMAKE_CURRENT_LIST_DIR}/@PROJECT_NAME@-targets.cmake\")\n")
            file(APPEND ${config_input} "include(\"\${CMAKE_CURRENT_LIST_DIR}/@PROJECT_NAME@-config-dependencies.cmake\" OPTIONAL)\n")
            file(APPEND ${config_input} "check_required_components(@PROJECT_NAME@)\n")

            configure_package_config_file(
                ${config_input}
                ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}-config.cmake
                INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/${PROJECT_NAME}
            )

            install(
                FILES
                    ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}-config.cmake
                    ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}-config-version.cmake
                    ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}-config-dependencies.cmake
                DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/${PROJECT_NAME}
            )
        endif()
    endfunction()
endif()