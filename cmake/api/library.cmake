 include(${WELD_API_DIR}/internal/component.cmake)

 if(NOT COMMAND weld_library)
    function(weld_library name)
        set(target ${PROJECT_NAME}_${name})

        add_library(${target})
        add_library(${PROJECT_NAME}::${name} ALIAS ${target})  # namespaced alias, set up immediately

        weld_component(${name} ${target})

        list(APPEND ${PROJECT_NAME}_LIBRARIES ${target})
        set(${PROJECT_NAME}_LIBRARIES ${${PROJECT_NAME}_LIBRARIES} CACHE INTERNAL "" FORCE)

        target_include_directories(
            ${target}
            PUBLIC
                $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include/>
                $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>   # relative, never absolute
        )

        # ---- install (guarded) ----
        if(${PROJECT_NAME}_INSTALL)
            install(
                TARGETS ${target}
                EXPORT ${PROJECT_NAME}-targets
                RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}    # Windows DLLs
                LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}    # Unix shared objects
                ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}    # static libs / import libs
            )
            install(
                DIRECTORY include/${PROJECT_NAME}
                DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
            )
        endif()
    endfunction()
 endif()