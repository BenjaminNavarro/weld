#include <catch2/catch_test_macros.hpp>

#include <test_package/my_lib.hpp>

TEST_CASE("greetings") {
  REQUIRE(mylib::generate_greetings("test") == "Hello test!");
}