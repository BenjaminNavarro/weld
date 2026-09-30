weld_executable(
    greeter
    SOURCES
        main.cpp
    PRIVATE
        test_package::my-lib
)