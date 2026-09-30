# Modern CMake Best Practices Guide

A practical guide to writing CMake projects (3.21+) that work when built standalone, consumed via `add_subdirectory`, integrated with `FetchContent`, or installed and found with `find_package`. Everything here is cross-platform: no generator-specific or OS-specific hacks unless noted.

---

## 1. Core principles

1. **Targets, not flags.** Never scatter `include_directories`, `add_definitions`, or `link_libraries` at directory scope. Everything — include paths, compile options, definitions, dependencies — is attached to a *target* via `target_*` commands. Then consumers of the target inherit usage requirements automatically.
2. **A library is its INTERFACE.** What matters is `target_link_libraries(my_lib PUBLIC ...)`, not global state. If a target correctly expresses its usage requirements, it works identically whether built in-tree, fetched, or installed.
3. **Consumer/developer split.** A person *using* your library should only see the public target and its dependencies. A person *developing* it additionally sees tests, examples, warnings, dev tools. Control this with options and `PROJECT_IS_TOP_LEVEL`.
4. **Idempotent, relocatable installs.** The install rules must produce a package that works from any prefix (`CMAKE_INSTALL_PREFIX`), with no absolute source/build paths baked in.

---

## 2. Project layout

The structure below separates components by kind, which maps naturally onto the target kinds:

```text
myproj/
├── CMakeLists.txt              # project root, options, dependency resolution
├── cmake/
│   ├── deps.cmake              # dependency resolution (see §4)
│   └── myproj-config.cmake.in  # package config template
├── src/
│   ├── lib1/
│   │   ├── CMakeLists.txt
│   │   ├── include/myproj/lib1/ # PUBLIC headers (installed)
│   │   │   └── lib1.hpp
│   │   └── src/                 # PRIVATE sources
│   │       └── lib1.cpp
│   └── app1/
│       ├── CMakeLists.txt
│       └── main.cpp
└── tests/
    ├── CMakeLists.txt
    └── lib1/
        ├── CMakeLists.txt
        └── test_lib1.cpp
```

Rules:

- One `CMakeLists.txt` per component. The root file declares the project, options, and dependencies only — it never declares targets directly.
- `include/myproj/lib1/` mirrors the install path, so the same relative include works for both in-tree and installed use.
- Headers consumers must not see live outside `include/`. Everything in `src/` is private.
- Tests live in `tests/` and are guarded behind `MYPROJ_BUILD_TESTS`.

---

## 3. Root CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.21)

# project() defines MYPROJ_VERSION, MYPROJ_SOURCE_DIR etc. and sets
# PROJECT_IS_TOP_LEVEL, the modern way to detect being consumed.
project(myproj VERSION 1.2.3 LANGUAGES CXX)

# ---- Options: define BEFORE dependency resolution, with initial values
# ---- that flip OFF when the project is consumed as a subproject.
option(MYPROJ_BUILD_TESTS "Build tests" ${PROJECT_IS_TOP_LEVEL})
option(MYPROJ_BUILD_EXAMPLES "Build examples" ${PROJECT_IS_TOP_LEVEL})
option(MYPROJ_INSTALL "Install targets" ${PROJECT_IS_TOP_LEVEL})

# ---- Default to a release-like build only when top level.
if(PROJECT_IS_TOP_LEVEL)
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
                 Debug Release RelWithDebInfo MinSizeRel)
  endif()
endif()

# ---- Dependencies ----
include(cmake/deps.cmake)

# ---- Components ----
add_subdirectory(src/lib1)
add_subdirectory(src/app1)

if(MYPROJ_BUILD_TESTS)
  enable_testing()
  add_subdirectory(tests)
endif()

include(cmake/install.cmake)   # export + package config, guarded (see §8)
```

Notes:

- `cmake_minimum_required` is the very first line, before `project()`.
- `include(GNUInstallDirs)` (in `deps.cmake` or the root) provides `CMAKE_INSTALL_BINDIR`, `CMAKE_INSTALL_LIBDIR`, `CMAKE_INSTALL_INCLUDEDIR` — the portable way to honor platform conventions without hardcoding.
- Never use `CMAKE_SOURCE_DIR`/`CMAKE_BINARY_DIR` in components; always `CMAKE_CURRENT_SOURCE_DIR` or the project variables. This is what makes `add_subdirectory` consumption safe.

---

## 4. Dependencies: the compatibility pattern

The goal: a component says `find_package(fmt CONFIG REQUIRED)` and it works whether fmt came from the system, Conan/vcpkg, `FetchContent`, or the parent project. The canonical pattern:

**`cmake/deps.cmake`**

```cmake
include(FetchContent)

# ---- fmt ----
find_package(fmt CONFIG QUIET)
if(NOT fmt_FOUND)
  FetchContent_Declare(
    fmt
    GIT_REPOSITORY https://github.com/fmtlib/fmt.git
    GIT_TAG        11.1.4   # always pin an exact tag, never a branch
    GIT_SHALLOW    TRUE
  )
  FetchContent_MakeAvailable(fmt)
endif()
```

Key points:

- **`FetchContent_MakeAvailable`** downloads, configures as a subproject, and defines the `fmt` target — with the same usage semantics as an installed `fmt::fmt`, provided the dependency follows best practices itself.
- **`find_package` first.** A dependency already available (Conan generators, a superproject, a sysroot) must win over downloading. This is what makes the project `FetchContent`-friendly *and* package-manager friendly.
- **`GIT_SHALLOW TRUE` + exact tags**: reproducible and fast. Never depend on mutable branches.
- With **Conan**, `conan install` generates a toolchain and config files that make `find_package(fmt CONFIG REQUIRED)` resolve from the Conan cache; with **vcpck/vcpkg**, the toolchain does the same. Because your project only ever uses `find_package`, you support both without any package-manager-specific CMake code. `deps.cmake` is then only the *fallback* for a standalone build.
- If a superproject already provides the target, you can also guard on the target name: `if(NOT TARGET fmt::fmt)` before declaring it.
- For *optional* dependencies, propagate the result to code: `target_compile_definitions(mylib PUBLIC MYPROJ_HAVE_FMT=$<BOOL:${fmt_FOUND}>)`.

---

## 5. Declaring libraries

**`src/lib1/CMakeLists.txt`**

```cmake
add_library(myproj_lib1)
add_library(myproj::lib1 ALIAS myproj_lib1)  # namespaced alias, set up immediately

target_sources(myproj_lib1 PRIVATE
  src/lib1.cpp
)

target_include_directories(myproj_lib1
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>   # relative, never absolute
)

target_compile_features(myproj_lib1 PUBLIC cxx_std_17)

target_link_libraries(myproj_lib1
  PUBLIC  fmt::fmt        # appears in the public API
  PRIVATE myproj::other   # implementation detail; consumers never see it
)

set_target_properties(myproj_lib1 PROPERTIES
  EXPORT_NAME lib1          # installed target is myproj::lib1, not myproj::myproj_lib1
  POSITION_INDEPENDENT_CODE ON
  VERSION   ${PROJECT_VERSION}     # affects shared libraries on versioned platforms
  SOVERSION ${PROJECT_VERSION_MAJOR}
)

# ---- install (guarded) ----
if(MYPROJ_INSTALL)
  install(
    TARGETS myproj_lib1
    EXPORT myproj-targets
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}    # Windows DLLs
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}    # Unix shared objects
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}    # static libs / import libs
  )
  install(
    DIRECTORY include/myproj
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
  )
endif()
```

The rules that make this "modern":

1. **Always create an `ALIAS` target with a double-colon namespace.** `myproj::lib1` inside the build tree means every downstream `target_link_libraries(mytarget PRIVATE myproj::lib1)` is written exactly the same as after installation — identical spelling before and after install is the whole trick to subproject/install dual usability. The `::` also makes CMake error out at configure time if the target doesn't exist (typos become hard errors).
2. **`$<BUILD_INTERFACE>` / `$<INSTALL_INTERFACE>` generator expressions** on include paths. `BUILD_INTERFACE` applies only in-tree; `INSTALL_INTERFACE` only in the installed package file. The install path must be relative or the installed package breaks the moment the prefix moves.
3. **No sources in `add_library()`** — add them with `target_sources`. This keeps the target declaration stable and lets you append platform-specific sources without editing the constructor.
4. **Link with target names only, never raw paths** (`fmt::fmt`, not `-lformat` or `/usr/lib/libfmt.so`).
5. **`PUBLIC` vs `PRIVATE` is API design.** If your public headers include fmt, the dependency must be `PUBLIC`. If you only use it in `.cpp` files, `PRIVATE`. Getting this wrong either breaks consumers (missing transitive dependency) or leaks dependencies into them (slower builds, coupling).
6. **Compile features, not standards flags.** `target_compile_features(t PUBLIC cxx_std_17)` propagates the requirement to consumers automatically. Don't set `CMAKE_CXX_STANDARD` globally except as a convenience default.
7. **Warnings are developer-only.** Never let warnings propagate to consumers:

```cmake
if(PROJECT_IS_TOP_LEVEL)
  target_compile_options(myproj_lib1 PRIVATE
    $<$<CXX_COMPILER_ID:MSVC>:/W4 /permissive->
    $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wall -Wextra -Wpedantic>
  )
endif()
```

The `if(PROJECT_IS_TOP_LEVEL)` guard is essential: a consumer who pulls your project in with `add_subdirectory` must not have your warning policy imposed on their build. (The MSVC branch here is not a platform hack — it is required for cross-platform warning portability.)

### Header-only and interface libraries

```cmake
add_library(myproj_header_lib INTERFACE)
add_library(myproj::header_lib ALIAS myproj_header_lib)

target_include_directories(myproj_header_lib INTERFACE
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)
target_compile_features(myproj_header_lib INTERFACE cxx_std_17)
```

`INTERFACE` libraries carry only usage requirements; they install via `install(TARGETS ... EXPORT myproj-targets)` exactly like real libraries.

### Static/shared flexibility

Don't hardcode `STATIC`/`SHARED`. Declare `add_library(myproj_lib1)` with no type and let `BUILD_SHARED_LIBS` (settable by the superproject, Conan, vcpkg, or the user) decide. Add `POSITION_INDEPENDENT_CODE ON` so the static variant can still be linked into shared libraries.

---

## 6. Declaring executables

**`src/app1/CMakeLists.txt`**

```cmake
add_executable(myproj_app1)
add_executable(myproj::app1 ALIAS myproj_app1)  # only needed if tests/other targets reference it

target_sources(myproj_app1 PRIVATE main.cpp)
target_compile_features(myproj_app1 PRIVATE cxx_std_17)
target_link_libraries(myproj_app1 PRIVATE myproj::lib1 fmt::fmt)

if(MYPROJ_INSTALL)
  install(TARGETS myproj_app1 RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()
```

- Executables almost never have `PUBLIC` requirements — `PRIVATE` only.
- Avoid `file(GLOB ...)` for sources; list files explicitly (or use `CONFIGURE_DEPENDS` only if you accept the tradeoff). Explicit lists make the build graph deterministic and diffs reviewable.
- If the app is only a dev tool, wrap its `add_subdirectory` in `if(PROJECT_IS_TOP_LEVEL OR MYPROJ_BUILD_TOOLS)` so superprojects don't build it.

---

## 7. Declaring tests

**`tests/CMakeLists.txt`**

```cmake
# Bring in a test framework the same FetchContent-compatible way as any dep.
find_package(GTest CONFIG QUIET)
if(NOT GTest_FOUND)
  FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.15.2
    GIT_SHALLOW    TRUE
  )
  # Silence the framework's own tests and installs while vendoring it:
  set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(googletest)
endif()

add_subdirectory(lib1)
```

**`tests/lib1/CMakeLists.txt`**

```cmake
add_executable(test_lib1)
target_sources(test_lib1 PRIVATE test_lib1.cpp)
target_compile_features(test_lib1 PRIVATE cxx_std_17)
target_link_libraries(test_lib1 PRIVATE
  myproj::lib1
  GTest::gtest_main
)

# CTest registration: use the target, never a path.
include(GoogleTest OPTIONAL RESULT_VARIABLE have_gtest_module)
if(have_gtest_module)
  gtest_discover_tests(test_lib1)
else()
  add_test(NAME lib1.all COMMAND test_lib1)
endif()
```

Guidance:

- **Tests link only namespaced aliases** (`myproj::lib1`), so the test code can't accidentally depend on the internal build layout.
- `gtest_discover_tests` (or Catch2's `catch_discover_tests`) registers each test case individually — better IDE integration and per-test `ctest -R` filtering. Plain `add_test` is the portable fallback and is always correct.
- Never install tests. Everything under `tests/` is guarded by the build option, so a consumed package carries zero test weight.
- For install-verification tests (like Conan's `test_package`), write a *separate* tiny project outside the main build that does `find_package(myproj CONFIG REQUIRED)` and links `myproj::lib1`. That validates the installed package the way a real consumer sees it — the strongest guarantee of dual usability.

---

## 8. Installing the package: the consumer side

Install rules above only make the targets *installable*; making them *findable* requires an export set and a package config.

**`cmake/install.cmake`**

```cmake
if(MYPROJ_INSTALL)
  include(CMakePackageConfigHelpers)

  install(
    EXPORT myproj-targets
    FILE myproj-targets.cmake
    NAMESPACE myproj::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/myproj
  )

  write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/myproj-config-version.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY SameMajorVersion
  )

  # Export the dependencies too, so find_package(myproj) finds fmt as well.
  file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/myproj-config-dependencies.cmake "
include(CMakeFindDependencyMacro)
find_dependency(fmt)
")

  configure_package_config_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/cmake/myproj-config.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/myproj-config.cmake
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/myproj
  )

  install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/myproj-config.cmake
    ${CMAKE_CURRENT_BINARY_DIR}/myproj-config-version.cmake
    ${CMAKE_CURRENT_BINARY_DIR}/myproj-config-dependencies.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/myproj
  )
endif()
```

**`cmake/myproj-config.cmake.in`**

```cmake
@PACKAGE_INIT@

include("${CMAKE_CURRENT_LIST_DIR}/myproj-targets.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/myproj-config-dependencies.cmake" OPTIONAL)

check_required_components(myproj)
```

Result: a consumer writes, identically for all consumption modes,

```cmake
find_package(myproj 1.2 CONFIG REQUIRED)
target_link_libraries(consumer PRIVATE myproj::lib1)
```

and it works whether `myproj` was installed, fetched via `FetchContent`, or added with `add_subdirectory`. That invariant is the design goal of this entire guide.

Details that matter:

- **`NAMESPACE myproj::`** on the export is what makes the installed target name match your in-tree alias.
- **`find_dependency`** (not `find_package`) inside the config file preserves component semantics; this is required whenever you export targets whose `PUBLIC`/`INTERFACE` link libraries reference external packages like `fmt::fmt`.
- **`COMPATIBILITY SameMajorVersion`** matches semver-style versioning for a library.
- **`check_required_components`** enables component support (`find_package(myproj COMPONENTS lib1)`) at near-zero cost.

---

## 9. FetchContent-compatible consumption checklist

Use this as a review checklist:

- [ ] `cmake_minimum_required` is the first line; `project()` immediately after.
- [ ] No `CMAKE_SOURCE_DIR`/`CMAKE_BINARY_DIR` references — only current/project-scoped variables.
- [ ] Side-effectful global commands (`enable_testing`, global compiler flags, `set(CMAKE_CXX_STANDARD ...)`, dev warnings) are guarded by `PROJECT_IS_TOP_LEVEL`.
- [ ] All dependency resolution goes through the `find_package`-first, `FetchContent`-fallback pattern (§4).
- [ ] Every target has a `myproj::` alias created right after `add_library`/`add_executable`.
- [ ] Include directories use `$<BUILD_INTERFACE:...>`/`$<INSTALL_INTERFACE:...>` pairs.
- [ ] No absolute paths anywhere in usage requirements.
- [ ] Tests, examples, docs, and dev warnings are behind options defaulting to `OFF` when not top level.
- [ ] Install rules are guarded by an install option and use `GNUInstallDirs` variables only.
- [ ] Export set + package config are generated (§8), so `find_package(myproj CONFIG)` works after install.

---

## 10. Quick reference: smell test


| Anti-pattern                                          | Modern replacement                                   |
| ----------------------------------------------------- | ---------------------------------------------------- |
| `include_directories(...)`                            | `target_include_directories(t ...)`                  |
| `add_definitions(...)`                                | `target_compile_definitions(t ...)`                  |
| `set(CMAKE_CXX_FLAGS ...)`                            | `target_compile_options` / `target_compile_features` |
| `link_libraries(...)` (directory scope)               | `target_link_libraries(t ...)`                       |
| `add_library(foo STATIC a.cpp)`                       | `add_library(foo)` + `target_sources`                |
| `file(GLOB SRC *.cpp)`                                | Explicit source list                                 |
| Un-namespaced target names in `target_link_libraries` | Always `pkg::target` aliases/exports                 |
| `set_target_properties(... CXX_STANDARD 17)`          | `target_compile_features(t cxx_std_17)`              |
| Hardcoded `lib/`, `include/` install paths            | `${CMAKE_INSTALL_LIBDIR}` etc. via `GNUInstallDirs`  |
| Absolute paths in `INSTALL_INTERFACE`                 | Relative paths only                                  |
| Unguarded `enable_testing()` / dev flags              | `if(PROJECT_IS_TOP_LEVEL)`                           |
| Branch-typed `GIT_TAG`                                | Pinned release tag                                   |
| Hardcoded `STATIC`/`SHARED`                           | Type-less `add_library` + `BUILD_SHARED_LIBS`        |


---

## 11. A minimal end-to-end example

Putting it all together, a complete dual-usable component:

```cmake
# src/lib1/CMakeLists.txt
add_library(myproj_lib1)
add_library(myproj::lib1 ALIAS myproj_lib1)

target_sources(myproj_lib1 PRIVATE src/lib1.cpp)

target_include_directories(myproj_lib1
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)

target_compile_features(myproj_lib1 PUBLIC cxx_std_17)
target_link_libraries(myproj_lib1 PUBLIC fmt::fmt)

set_target_properties(myproj_lib1 PROPERTIES EXPORT_NAME lib1)

if(PROJECT_IS_TOP_LEVEL)
  target_compile_options(myproj_lib1 PRIVATE
    $<$<CXX_COMPILER_ID:MSVC>:/W4>
    $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wall -Wextra>
  )
endif()

if(MYPROJ_INSTALL)
  install(TARGETS myproj_lib1 EXPORT myproj-targets
          RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
          LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
          ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})
  install(DIRECTORY include/myproj DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
endif()
```

A downstream project — whether it installed you, fetched you, or embedded you — consumes it with exactly:

```cmake
find_package(myproj CONFIG REQUIRED)   # omitted when added via add_subdirectory
target_link_libraries(downstream PRIVATE myproj::lib1)
```

If those two lines work in all three consumption modes, your CMake is doing its job.

---

## 12. The `weld_*` wrapper API

All of the above is correct but repetitive — every component repeats the same boilerplate (alias, include dirs, install rules, export name). The `weld` API hides that boilerplate behind a small set of functions so a component's `CMakeLists.txt` states *what* it is, not *how* to wire it. Because every rule from §1–§11 lives inside the functions, fixing a best-practice issue or adopting a new CMake idiom is a one-line version bump of `weld`, not an edit of every project.

**Setup** — the wrapper is itself a normal CMake package, consumed exactly like any other dependency (§4 pattern):

```cmake
# cmake/deps.cmake
find_package(weld CONFIG QUIET)
if(NOT weld_FOUND)
  FetchContent_Declare(
    weld
    GIT_REPOSITORY https://github.com/<you>/weld.git
    GIT_TAG        v1.0.0
    GIT_SHALLOW    TRUE
  )
  FetchContent_MakeAvailable(weld)
endif()

weld_project(myproj         # sets up options, export set, package config, testing
  VERSION 1.2.3
  DEFAULT_STD 17
)
```

### `weld_library`

Replaces the full §5 boilerplate:

```cmake
# src/lib1/CMakeLists.txt
weld_library(lib1
  SOURCES src/lib1.cpp
  PUBLIC_LINK  fmt::fmt        # PUBLIC deps (exposed in the API)
  PRIVATE_LINK myproj::other   # implementation deps
  PUBLIC_HEADERS include/myproj/lib1   # installed + BUILD/INSTALL_INTERFACE handled
)

# weld_library provides, at once:
#   - target myproj_lib1 + alias myproj::lib1
#   - EXPORT_NAME, PIC, VERSION/SOVERSION from project version
#   - guarded install rules (RUNTIME/LIBRARY/ARCHIVE + headers)
#   - top-level-only dev warnings
# Interface libs: weld_library(header_only INTERFACE PUBLIC_HEADERS include/...)
```

### `weld_executable`

```cmake
# src/app1/CMakeLists.txt
weld_executable(app1
  SOURCES main.cpp
  LINK myproj::lib1 fmt::fmt   # always PRIVATE
)
# Provides myproj_app1, guarded RUNTIME install, options-gated build.
```

### `weld_test`

```cmake
# tests/lib1/CMakeLists.txt
weld_test(lib1
  SOURCES test_lib1.cpp
  LINK myproj::lib1
  FRAMEWORK gtest             # fetches/registers per §7; discovers test cases
)
# Provides test_lib1 + ctest registration; never installed.
```

### Semantics the wrapper must preserve

These are the contract between `weld` and the guide — the functions are only sugar if these invariants hold:

1. **Spelling stability.** `weld_library(lib1 ...)` creates `myproj::lib1` in-tree *and* in the installed export set, so consumers write identical `target_link_libraries` lines in all three consumption modes.
2. **Zero global side effects.** `weld_*` functions never touch directory-scope state; everything is target-scoped. Project-level setup happens only in `weld_project`, guarded by `PROJECT_IS_TOP_LEVEL`.
3. **Escape hatch.** Every wrapper argument maps 1:1 to the raw commands shown in §5–§7, and the underlying target is accessible for anything the wrapper doesn't cover (`target_compile_definitions(myproj_lib1 PRIVATE ...)` still works, because it *is* the same target).
4. **Versioned fixes.** Best-practice changes land in `weld` releases; projects pin a tag and bump it deliberately. Keep old signatures working; deprecate with warnings rather than breaking.

### A note on defaults

The wrapper should default to the guide's recommendations (type-less libraries + `BUILD_SHARED_LIBS`, `GNUInstallDirs` destinations, `SameMajorVersion` compatibility, `find_package`-first deps) and only expose knobs where projects legitimately differ. Every option a wrapper removes is a mistake nobody can make again.

---

## 13. Packaging `weld` itself: exporting a CMake API

`weld` is a CMake project with **no binary targets** — its build/install produces only `.cmake` files. The pattern is the same as §8, minus the export set: the config file is the entry point, and the API modules are data files installed alongside it.

### Repository layout

```text
weld/
├── CMakeLists.txt              # trivial project + install rules only
├── weld-config.cmake.in
├── cmake/
│   ├── project.cmake           # weld_project()
│   ├── library.cmake            # weld_library()
│   ├── executable.cmake         # weld_executable()
│   ├── test.cmake               # weld_test()
│   └── internal/utils.cmake     # shared helpers (not exported API)
└── tests/
    └── test_project/            # a consumer project that exercises the API
```

### The config file is an *includer*, not the API

**`weld-config.cmake.in`**

```cmake
@PACKAGE_INIT@

# Define the API by including the modules installed next to this file.
# Each module defines its functions guarded so repeated includes are safe.
include("${CMAKE_CURRENT_LIST_DIR}/weld-project.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/weld-targets-api.cmake")

check_required_components(weld)
```

That's all. `find_package(weld CONFIG REQUIRED)` then makes `weld_library()` etc. available — functions are defined at configure time by the include, there is no build-time component at all.

### The CMakeLists.txt of weld

```cmake
cmake_minimum_required(VERSION 3.21)
project(weld VERSION 1.0.0 LANGUAGES NONE)   # NONE: no compiler needed

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

# Bundle the API modules into one file so the config only needs one include.
file(READ ${CMAKE_CURRENT_SOURCE_DIR}/cmake/project.cmake    _weld_project)
file(READ ${CMAKE_CURRENT_SOURCE_DIR}/cmake/library.cmake    _weld_lib)
file(READ ${CMAKE_CURRENT_SOURCE_DIR}/cmake/executable.cmake _weld_exe)
file(READ ${CMAKE_CURRENT_SOURCE_DIR}/cmake/test.cmake       _weld_test)
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/weld-targets-api.cmake
  "${_weld_project}\n${_weld_lib}\n${_weld_exe}\n${_weld_test}\n")

configure_package_config_file(
  ${CMAKE_CURRENT_SOURCE_DIR}/weld-config.cmake.in
  ${CMAKE_CURRENT_BINARY_DIR}/weld-config.cmake
  INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/weld
)

write_basic_package_version_file(
  ${CMAKE_CURRENT_BINARY_DIR}/weld-config-version.cmake
  VERSION ${PROJECT_VERSION}
  COMPATIBILITY SameMajorVersion
)

install(FILES
  ${CMAKE_CURRENT_BINARY_DIR}/weld-config.cmake
  ${CMAKE_CURRENT_BINARY_DIR}/weld-config-version.cmake
  ${CMAKE_CURRENT_BINARY_DIR}/weld-targets-api.cmake
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/weld
)
```

### FetchContent compatibility of weld itself

Consumers may fetch `weld` instead of installing it (§4 pattern). When fetched, `find_package` never runs, so the API must also be defined from the plain project. In `weld`'s root:

```cmake
if(NOT PROJECT_IS_TOP_LEVEL)
  # Being consumed via add_subdirectory/FetchContent: define the API directly.
  include(cmake/project.cmake)
  include(cmake/library.cmake)
  include(cmake/executable.cmake)
  include(cmake/test.cmake)
endif()
```

This gives the same dual-mode usability the whole guide demands of any other target — `weld` is its own first consumer.

### Implementation rules for the API modules

1. **Guard every definition** so multiple inclusion is harmless:
  ```cmake
   if(NOT COMMAND weld_library)
     function(weld_library name)
       # ... raw CMake from §5 ...
     endfunction()
   endif()
  ```
2. **One function per concept, thin over raw CMake.** The body of `weld_library` is exactly the boilerplate of §5; the escape-hatch rule (§12) holds because it operates on a plain target.
3. **No side effects at include time.** The modules define functions only. Nothing executes until a `weld_*` function is called, so including the API can never break the consuming project.
4. **Derive names, don't hardcode.** `weld_project(myproj ...)` stores the project name in a normal variable (`WELD_PROJECT_NAME`) read by the other functions to build `myproj_lib1` / `myproj::lib1` / `myproj-targets`. But also accept an override for unusual cases.
5. **Version the API in the version file.** Bump major when a function signature breaks; the `SameMajorVersion` check then protects downstreams automatically.

### Why not the alternatives?

- **Only `weld-config.cmake.in` with everything inline**: unmanageable past a few hundred lines; per-module files are the same reason you split C++ into headers.
- **`export(EXPORT ...)`**: requires at least one real target; weld has none, so there is nothing to export.
- **An `INTERFACE` library carrying the API via `file(GENERATE)`**: works, but forces every consumer to link a dummy target for no benefit.
- **Not a CMake project at all** (just a repo of `.cmake` files, consumed via `include(weld.cmake)`): loses `find_package` version checking, `CMakePackageConfigHelpers` relocation, Conan/vcpkg packaging, and the §4 dependency pattern. Being a proper project costs \~30 lines and buys all of that.

---

## 14. `test_package` without installing weld

The point of a test package (§7) is to exercise weld *exactly as a real consumer would* — through `find_package(weld CONFIG REQUIRED)`. Skipping installation would defeat that, so don't change the mechanism; make the build-tree package discoverable instead.

### The key fact: the package config already exists in the build tree

`configure_package_config_file` (§13) writes `weld-config.cmake` and the version file into `${CMAKE_CURRENT_BINARY_DIR}` during configure — no install step needed for the files to exist. A consumer just has to point `find_package` at that directory.

### `tests/test_package/CMakeLists.txt`

Standalone project, run by the weld CI *after configuring (and optionally building) the main project, but before installing*:

```cmake
cmake_minimum_required(VERSION 3.21)
project(weld_test_package LANGUAGES CXX)

# WELD_BUILD_DIR is passed in by the CI script (or CMake preset):
#   cmake -S tests/test_package -B build/test_package \
#         -DWELD_BUILD_DIR=$PWD/build -Dweld_DIR=$PWD/build
#
# Setting the package root directly is the cleanest form:
find_package(weld 1.0 CONFIG REQUIRED
  PATHS ${WELD_BUILD_DIR}
  NO_DEFAULT_PATH        # don't pick up some other installed weld
)

weld_project(consumer VERSION 0.1.0)
weld_library(demo SOURCES demo.cpp)
```

Alternatively, skip the variable and set the standard `<Pkg>_DIR` cache variable, which `find_package` honors automatically:

```bash
cmake -S tests/test_package -B build/test_package \
      -Dweld_DIR=/path/to/weld/build
```

`-Dweld_DIR=<build-dir>` is the idiomatic answer: `find_package` treats it as the package configuration directory and finds `weld-config.cmake` there directly.

### Recommended CI order

```bash
# 1. Configure + build weld (generates the config in the build tree)
cmake -S . -B build -DWELD_BUILD_TESTS=ON
cmake --build build

# 2. Consumer test against the build tree (no install)
cmake -S tests/test_package -B build/test-package -Dweld_DIR=$PWD/build
cmake --build build/test-package

# 3. Install + consumer test against the installed tree (validates relocation)
cmake --install build --prefix build/install
cmake -S tests/test_package -B build/test-package-installed \
      -DCMAKE_PREFIX_PATH=$PWD/build/install
```

Step 2 catches API breakage immediately; step 3 additionally validates that the installed config is relocatable and self-contained (the `@PACKAGE_INIT@`-relative includes resolve correctly from the install prefix).

### Why not the shortcuts

- **`add_subdirectory(weld)` from the test project**: bypasses `find_package` entirely, so it would not test the config file — the exact artifact a test package exists to verify.
- **`FetchContent` of the local source** (`SOURCE_DIR`): works (`FetchContent_Declare(weld SOURCE_DIR ${WELD_SOURCE_DIR})` triggers the `NOT PROJECT_IS_TOP_LEVEL` include path of §13), but again tests the subdirectory mode rather than the `find_package` mode.
- **Copying the config into the test project**: brittle; the build tree already contains a valid, relocatable config, so just point `weld_DIR` at it.

### One prerequisite in weld itself

For this to work, §13's bundled API file (`weld-targets-api.cmake`) must be written to the **build** directory — it already is, since the `file(WRITE ...)` runs at configure time. If you ever move file generation behind `install()`, the build-tree test package breaks; keep all four generated files produced at configure time.