#include <test_package/my_lib.hpp>

#include <iostream>

int main(int argc, const char *argv[]) {
  std::cout << mylib::generate_greetings("handsome") << '\n';
}