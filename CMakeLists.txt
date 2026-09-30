cmake_minimum_required(VERSION 3.21)

# A language is required for GNUInstallDirs to work even though weld doesn't have C++ targets
project(weld VERSION 1.0.0 LANGUAGES CXX)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

configure_package_config_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/cmake/weld-config.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/weld-config.cmake
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/weld
)

write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/weld-config-version.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY SameMajorVersion
)

if (PROJECT_IS_TOP_LEVEL)
    install(
        FILES
            ${CMAKE_CURRENT_BINARY_DIR}/weld-config.cmake
            ${CMAKE_CURRENT_BINARY_DIR}/weld-config-version.cmake
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/weld
    )
    install(
        DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/cmake/api
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/weld
    )
    file(COPY ${CMAKE_CURRENT_SOURCE_DIR}/cmake/api DESTINATION ${CMAKE_CURRENT_BINARY_DIR})
else()
    # Being consumed via add_subdirectory/FetchContent: define the API directly.
    include(cmake/api/weld.cmake)
endif()

