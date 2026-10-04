 if(NOT COMMAND weld_component)
    macro(weld_component name target)

        set(options AUTO_SOURCES)
        set(oneValueArgs STD)
        set(multiValueArgs SOURCES PUBLIC PRIVATE INTERFACE)
        cmake_parse_arguments(PARSE_ARGV 1 comp
            "${options}" "${oneValueArgs}" "${multiValueArgs}"
        )

        if(comp_AUTO_SOURCES AND DEFINED comp_SOURCES)
            message(FATAL_ERROR "[weld] AUTO_SOURCES enabled and SOURCES specified at the same time for ${name}. Chose one approach or the other.")
        endif()

        if(NOT DEFINED comp_STD AND NOT DEFINED ${PROJECT_NAME}_DEFAULT_STD)
            message(FATAL_ERROR "[weld] No C++ standard defined for ${name}, neither directly (STD argument) or at the package level (DEFAULT_STD argument to weld_project()")
        endif()

        if(${PROJECT_NAME}_WELD_DEV_LOGS AND NOT comp_AUTO_SOURCES AND NOT DEFINED comp_SOURCES)
            message(WARNING "[weld] component ${name} declared without sources. Make sure it's on purpose.")
        endif()

        set(${PROJECT_NAME}_${target}_NAME ${name} CACHE INTERNAL "" FORCE)

        if(comp_AUTO_SOURCES)
            file(GLOB comp_SOURCES CONFIGURE_DEPENDS *.cpp)
        endif()

        target_sources(
            ${target}
            PRIVATE ${comp_SOURCES}
        )

        if(NOT DEFINED comp_STD)
            set(comp_STD ${${PROJECT_NAME}_DEFAULT_STD})
        endif()
        target_compile_features(${target} PUBLIC cxx_std_${comp_STD})

        set(visibilities PUBLIC PRIVATE INTERFACE)
        set(target_deps)
        foreach(visibility IN LISTS visibilities)
            foreach(dep IN LISTS comp_${visibility})
                target_link_libraries(${target} ${visibility} ${dep})
                list(APPEND target_deps ${dep})
            endforeach()
        endforeach()
        set(${PROJECT_NAME}_${target}_DEPS ${target_deps} CACHE INTERNAL "" FORCE)

        set_target_properties(
            ${target}
            PROPERTIES
                EXPORT_NAME ${name}                 # installed target is ${PROJECT_NAME}::${name}, not ${PROJECT_NAME}::${target}
                POSITION_INDEPENDENT_CODE ON
                VERSION   ${PROJECT_VERSION}        # affects shared libraries on versioned platforms
                SOVERSION ${PROJECT_VERSION_MAJOR}
                EXPORT_COMPILE_COMMANDS ${${PROJECT_NAME}_COMPILE_COMMANDS}
        )

    endmacro()
endif()