from conan import ConanFile
from conan.tools.cmake import CMake, cmake_layout


class WeldConan(ConanFile):
    name = "weld"
    version = "1.0.0"
    description = ""
    license = "MIT"
    url = "https://github.com/BenjaminNavarro/weld.git"
    homepage = "https://github.com/BenjaminNavarro/weld"
    topics = ("cmake", "c++")
    package_type = "build-scripts"
    generators = "CMakeDeps", "CMakeToolchain"
    settings = "build_type"

    exports = "LICENSE"
    exports_sources = (
        "CMakeLists.txt", "cmake/*", "share/*"
    )

    def layout(self):
        cmake_layout(self)

    def build(self):
        cmake = CMake(self)
        cmake.configure()
        cmake.build()

    def package(self):
        cmake = CMake(self)
        cmake.install()            # relies on the project's install rules

    def package_info(self):
        self.cpp_info.set_property("cmake_build_modules", ["lib/cmake/weld/api/weld.cmake"])
