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
    # USE_DEP_FILE
)

weld_dependency(fmt VERSION 10.0 FALLBACK gh:fmtlib/fmt@10.0)
weld_dependency(Catch2 VERSION 3.16 FOR_TESTS FALLBACK gh:catchorg/catch2@v3.16.0)
weld_dependency(tinyxml2 FOR_EXAMPLES)
weld_dependency(yaml-cpp VERSION 0.8.0 OPTIONAL)

weld_build()