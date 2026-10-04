from conan import ConanFile
from conan.tools.cmake import CMakeToolchain, CMake, cmake_layout, CMakeDeps


class @PROJECT_NAME_SANITIZED@Conan(ConanFile):
    name = "@PROJECT_NAME@"
    version = "@PROJECT_VERSION@"
    description = "@PROJECT_DESCRIPTION@"
    # license = ""
    # url = ""
    # homepage = ""
    # topics = ("", "")
    settings = "os", "arch", "compiler", "build_type"
    options = {
        "shared": [True, False],
        "fPIC": [True, False],
        "examples": [True, False]
    }
    default_options = {
        "shared": False,
        "fPIC": True,
        "examples": False
    }
    # TODO try to define it based on the package content. If both libraries and apps are present, set it to unknown as there is no mechanism to handle this case in Conan yet (https://github.com/conan-io/conan/issues/12969)
    package_type = "@CONAN_PACKAGE_TYPE@"

    # ---- Exports: recipe lives with the sources, sdist stays self-contained
    exports = "LICENSE"
    exports_sources = (
        "CMakeLists.txt", "cmake/*", "src/*", "apps/*", "tests/*"
    )

    def requirements(self):
        @CONAN_REQUIREMENTS@
        if self.options.examples:
            @CONAN_EXAMPLES_REQUIREMENTS@

    # Build-time only (never propagate to consumers)
    def build_requirements(self):
        self.tool_requires("weld/@weld_VERSION@")
        @CONAN_TEST_REQUIREMENTS@

    # ---- Options hygiene
    def config_options(self):
        if self.settings.os == "Windows":
            del self.options.fPIC   # meaningless on MSVC/Windows

    def configure(self):
        if self.options.shared:
            self.options.rm_safe("fPIC")
        # Let BUILD_SHARED_LIBS drive the CMake side
        self.options["*"].shared = self.options.shared

    def layout(self):
        cmake_layout(self)   # standard build folders + generators dir layout

    def generate(self):
        # CMakeDeps makes find_package(<dep> CONFIG) resolve from the Conan cache
        deps = CMakeDeps(self)
        # Force a weld-config.cmake to be generated since it is not done automatically
        # for tool requirements
        deps.build_context_activated = ["weld"]
        deps.build_context_build_modules = ["weld"]
        deps.generate()
        # CMakeToolchain = full toolchain (compiler, flags, presets)
        tc = CMakeToolchain(self)
        tc.variables["@PROJECT_NAME@_BUILD_TESTS"] = not self.conf.get("tools.build:skip_test", default=True)
        tc.variables["@PROJECT_NAME@_BUILD_EXAMPLES"] = self.options.examples
        tc.variables["@PROJECT_NAME@_INSTALL"] = True
        # BUILD_SHARED_LIBS is set automatically from self.options.shared
        tc.generate()

    def build(self):
        cmake = CMake(self)
        cmake.configure()          # uses the generated presets, no -D soup
        cmake.build()

    def package(self):
        cmake = CMake(self)
        cmake.install()            # relies on the project's install rules

    def package_info(self):
        # Inform Conan consumers; keep names in sync with the CMake export
        self.cpp_info.set_property("cmake_find_mode", "none")  # when consumers use the config file directly
        self.cpp_info.set_property("cmake_file_name", "@PROJECT_NAME@")
        @CONAN_COMPONENTS@