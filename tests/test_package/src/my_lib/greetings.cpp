#include <test_package/my_lib/greetings.hpp>

#include <fmt/format.h>

namespace mylib {

std::string generate_greetings(const std::string &name) {
  return fmt::format("Hello {}!", name);
}

} // namespace mylib