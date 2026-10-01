weld_test(
    greeter-test
    SOURCES
        main.cpp
    PRIVATE
        test_package::my-lib
        Catch2::Catch2WithMain
)