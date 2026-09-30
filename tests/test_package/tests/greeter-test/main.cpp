#include <test_package/my_lib.hpp>

#include <iostream>

int main(int argc, const char *argv[]) {
  if (mylib::generate_greetings("test") == "Hello test!") {
    return 0;
  } else {
    return 1;
  }
}