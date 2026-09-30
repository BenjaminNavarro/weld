#include <test_package/my_lib.hpp>

#include <iostream>

int main(int argc, const char *argv[]) {
  if (argc > 1) {
    std::cout << mylib::generate_greetings(argv[1]) << '\n';
  } else {
    std::cout << mylib::generate_greetings("random user") << '\n';
  }
}