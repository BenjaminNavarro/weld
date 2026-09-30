weld_executable(
    greeter-example
    SOURCES
        main.cpp
    PRIVATE
        test_package::my-lib
)