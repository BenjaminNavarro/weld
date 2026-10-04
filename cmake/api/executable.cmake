 include(${WELD_API_DIR}/internal/component.cmake)

 if(NOT COMMAND weld_executable)
    function(weld_executable name)
        set(target ${PROJECT_NAME}_${name})

        if(name MATCHES "-example$")
            set(${target}_IS_EXAMPLE TRUE)
        else()
            set(${target}_IS_EXAMPLE FALSE)
        endif()

        if(NOT ${PROJECT_NAME}_BUILD_EXAMPLES AND ${target}_IS_EXAMPLE)
            return()
        endif()

        add_executable(${target})
        add_executable(${PROJECT_NAME}::${name} ALIAS ${target})  # namespaced alias, set up immediately

        weld_component(${name} ${target})

        # ---- install (guarded) ----
        if(${PROJECT_NAME}_INSTALL AND NOT ${target}_IS_EXAMPLE)
            install(
                TARGETS ${target}
                RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}    # EXEs
            )
        endif()
    endfunction()
 endif()