cmake_minimum_required(VERSION 3.21)

project(
    test_package
    VERSION 1.0
    LANGUAGES CXX
)

find_package(
    weld 1.0 CONFIG REQUIRED
    NO_DEFAULT_PATH # make sure to use the current dev version and not an already installed one
)

weld_project(
    DEFAULT_STD 17
)

weld_dependency(fmt)
weld_dependency(spdlog FOR_TESTS)
weld_dependency(tinyxml2 FOR_EXAMPLES)
weld_dependency(yaml-cpp OPTIONAL)

weld_build()