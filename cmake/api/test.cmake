 include(${CMAKE_CURRENT_LIST_DIR}/internal/component.cmake)

 if(NOT COMMAND weld_test)
    function(weld_test name)
        set(target ${PROJECT_NAME}_${name})

        add_executable(${target})
        add_executable(${PROJECT_NAME}::${name} ALIAS ${target})  # namespaced alias, set up immediately

        weld_component(${name} ${target})

        add_test(
            NAME ${name}
            COMMAND ${target}
        )

        list(APPEND ${PROJECT_NAME}_TESTS ${target})
        set(${PROJECT_NAME}_TESTS ${${PROJECT_NAME}_TESTS} CACHE INTERNAL "" FORCE)
    endfunction()
 endif()