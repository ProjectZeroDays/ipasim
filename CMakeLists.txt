cmake_minimum_required (VERSION 3.12.2)

# TODO: When calling ninja, hide message "no work to do".

option (SUPERBUILD "Configure Clang and then the project itself." ON)

set (CL_COMPILER OFF)

if (SUPERBUILD)

    project (ipaSim-superbuild LANGUAGES NONE)

    set (SOURCE_DIR "${CMAKE_SOURCE_DIR}")
    set (BINARY_DIR "${CMAKE_BINARY_DIR}")

    list (APPEND CMAKE_MODULE_PATH "${SOURCE_DIR}/scripts")
    include (CommonVariables)

    function (add_superbuild_target name cmakeDir)
        add_custom_command (
            OUTPUT "${cmakeDir}/build.ninja"
            COMMAND "${CMAKE_COMMAND}"
                "-DSOURCE_DIR=${SOURCE_DIR}"
                "-DBINARY_DIR=${BINARY_DIR}"
                -P "${SOURCE_DIR}/scripts/${name}.cmake"
            USES_TERMINAL
            DEPENDS "${SOURCE_DIR}/scripts/${name}.cmake"
                "${SOURCE_DIR}/scripts/CommonVariables.cmake")
        add_custom_target ("config-${name}"
            DEPENDS "${cmakeDir}/build.ninja")
    endfunction (add_superbuild_target)

    add_superbuild_target (clang-x86-Debug "${DEBUG_CLANG_CMAKE_DIR}")
    add_superbuild_target (clang-x86-Release "${RELEASE_CLANG_CMAKE_DIR}")
    add_superbuild_target (ipaSim-x86-Debug "${DEBUG_IPASIM_CMAKE_DIR}")
    add_superbuild_target (ipaSim-x86-Release "${RELEASE_IPASIM_CMAKE_DIR}")
    add_superbuild_target (winobjc-x86-Debug "${DEBUG_WINOBJC_CMAKE_DIR}")
    add_superbuild_target (winobjc-x86-Release "${RELEASE_WINOBJC_CMAKE_DIR}")
    add_superbuild_target (lief-x86-Debug "${DEBUG_LIEF_CMAKE_DIR}")
    add_superbuild_target (lief-x86-Release "${RELEASE_LIEF_CMAKE_DIR}")
    add_superbuild_target (Libffi-x86-Debug "${DEBUG_LIBFFI_CMAKE_DIR}")
    add_superbuild_target (Libffi-x86-Release "${RELEASE_LIBFFI_CMAKE_DIR}")

    add_custom_target (tblgens-x86-Release
        COMMENT "Tablegens"
        COMMAND ninja llvm-tblgen clang-tblgen
        WORKING_DIRECTORY "${RELEASE_CLANG_CMAKE_DIR}"
        USES_TERMINAL
        DEPENDS config-clang-x86-Release)

    add_dependencies (config-clang-x86-Debug tblgens-x86-Release)

    add_custom_target (clang-x86-Release
        COMMENT "Clang"
        COMMAND ninja clang lld
        WORKING_DIRECTORY "${RELEASE_CLANG_CMAKE_DIR}"
        USES_TERMINAL
        DEPENDS config-clang-x86-Release)

    add_custom_target (clang-x86-Debug
        COMMENT "Clang"
        COMMAND ninja clang lld
        WORKING_DIRECTORY "${DEBUG_CLANG_CMAKE_DIR}"
        USES_TERMINAL
        DEPENDS config-clang-x86-Debug)

    add_custom_target (prep-ipaSim-x86-Debug
        COMMENT "Prepare ipaSim"
        DEPENDS config-ipaSim-x86-Debug config-winobjc-x86-Debug
            clang-x86-Release)

    add_custom_target (prep-ipaSim-x86-Release
        COMMENT "Pepare ipaSim"
        DEPENDS config-ipaSim-x86-Release config-winobjc-x86-Release
            clang-x86-Release)

    add_custom_target (ipaSim-x86-Debug
        COMMENT "ipaSim"
        COMMAND ninja IpaSimApp
        WORKING_DIRECTORY "${DEBUG_IPASIM_CMAKE_DIR}"
        USES_TERMINAL
        DEPENDS config-ipaSim-x86-Debug)

    add_custom_target (ipaSim-x86-Release
        COMMENT "ipaSim"
        COMMAND ninja IpaSimApp
        WORKING_DIRECTORY "${RELEASE_IPASIM_CMAKE_DIR}"
        USES_TERMINAL
        DEPENDS config-ipaSim-x86-Release)

    add_custom_target (lief-x86-Debug
        COMMENT "LIEF"
        COMMAND ninja LIB_LIEF_STATIC
        WORKING_DIRECTORY "${DEBUG_LIEF_CMAKE_DIR}"
        USES_TERMINAL
        DEPENDS config-lief-x86-Debug)

    add_custom_target (lief-x86-Release
        COMMENT "LIEF"
        COMMAND ninja LIB_LIEF_STATIC
        WORKING_DIRECTORY "${RELEASE_LIEF_CMAKE_DIR}"
        USES_TERMINAL
        DEPENDS config-lief-x86-Release)

    add_custom_target (Libffi-x86-Debug
        COMMENT "Libffi"
        COMMAND ninja ffi
        WORKING_DIRECTORY "${DEBUG_LIBFFI_CMAKE_DIR}"
        USES_TERMINAL
        DEPENDS config-Libffi-x86-Debug)

    add_custom_target (Libffi-x86-Release
        COMMENT "Libffi"
        COMMAND ninja ffi
        WORKING_DIRECTORY "${RELEASE_LIBFFI_CMAKE_DIR}"
        USES_TERMINAL
        DEPENDS config-Libffi-x86-Release)

else (SUPERBUILD)

    option (USE_ORIG_CLANG "Use the original instead of our patched Clang. For \
testing purposes only." OFF)
    option (USE_DEBUG_CLANG "Use Debug version of our patched Clang." OFF)

    project (ipaSim LANGUAGES C CXX ASM)

    list (APPEND CMAKE_MODULE_PATH "${SOURCE_DIR}/scripts")
    include (CommonVariables)

    # Now, the compiler was tested, so we can change it to our
    # possibly-not-yet-existing patched Clang. See #2.
    if (NOT USE_ORIG_CLANG)
        if (USE_DEBUG_CLANG)
            set (CLANG_EXE "${BUILT_DEBUG_CLANG_EXE}")
            set (LLD_LINK_EXE "${BUILT_DEBUG_LLD_LINK_EXE}")
        else (USE_DEBUG_CLANG)
            set (CLANG_EXE "${BUILT_CLANG_EXE}")
            set (LLD_LINK_EXE "${BUILT_LLD_LINK_EXE}")
        endif (USE_DEBUG_CLANG)
    endif (NOT USE_ORIG_CLANG)
    set (CMAKE_C_COMPILER "${CLANG_EXE}")
    set (CMAKE_CXX_COMPILER "${CLANG_EXE}")
    # Note that this is probably not actually used, but we keep it here for
    # consistency. Why is this not used? See below where we manually set
    # `-fuse-ld=lld-link`.
    set (CMAKE_LINKER "${LLD_LINK_EXE}")

    # Simplify `CMAKE_CXX_LINK_EXECUTABLE` so that it actually works. (The
    # original also set some `-Wl` options which weren't compatible with MSVC
    # nor LLVM's MSVC-like linker.) The values were copied from
    # `C:\Program Files\CMake\share\cmake-3.11\Modules\CMakeCXXInformation.cmake`.
    # The original values were probably from
    # `Modules\Platform\Windows-GNU.cmake`. Also, we want to use `lld-link.exe`
    # instead of `CMAKE_CXX_COMPILER` for linking.
    macro (update_commands lang)
        set ("CMAKE_${lang}_LINK_EXECUTABLE"
            "<CMAKE_CXX_COMPILER> -fuse-ld=lld-link -g <FLAGS> \
<CMAKE_CXX_LINK_FLAGS> <LINK_FLAGS> <OBJECTS> -o <TARGET> \
-Wl,/implib:<TARGET_IMPLIB> <LINK_LIBRARIES>")
        set ("CMAKE_${lang}_CREATE_SHARED_LIBRARY"
            "<CMAKE_CXX_COMPILER> -fuse-ld=lld-link -g \
<CMAKE_SHARED_LIBRARY_CXX_FLAGS> <LANGUAGE_COMPILE_FLAGS> <LINK_FLAGS> \
<CMAKE_SHARED_LIBRARY_CREATE_CXX_FLAGS> <SONAME_FLAG><TARGET_SONAME> \
-o <TARGET> -Wl,/implib:<TARGET_IMPLIB> <OBJECTS> <LINK_LIBRARIES>")
    endmacro ()
    update_commands (C)
    update_commands (CXX)

    # TODO: Don't hardcode the architecture.
    add_prep_target ("prep-ipaSim-x86-${CMAKE_BUILD_TYPE}")

    add_custom_target (config-winobjc
        COMMENT "Configure WinObjC"
        COMMAND ninja "config-winobjc-x86-${CMAKE_BUILD_TYPE}"
        WORKING_DIRECTORY "${BINARY_DIR}"
        USES_TERMINAL)
    function (add_woc_lib name)
        add_custom_target ("woc-${name}-build"
            BYPRODUCTS "${CURRENT_WINOBJC_CMAKE_DIR}/bin/${name}.dll"
                "${CURRENT_WINOBJC_CMAKE_DIR}/bin/${name}.lib"
            COMMENT "WinObjC: ${name}"
            COMMAND ninja "${name}"
            WORKING_DIRECTORY "${CURRENT_WINOBJC_CMAKE_DIR}"
            USES_TERMINAL
            DEPENDS config-winobjc)
        add_library ("woc-${name}" SHARED IMPORTED)
        set_target_properties ("woc-${name}" PROPERTIES
            IMPORTED_LOCATION "${CURRENT_WINOBJC_CMAKE_DIR}/bin/${name}.dll"
            IMPORTED_IMPLIB "${CURRENT_WINOBJC_CMAKE_DIR}/bin/${name}.lib")
    endfunction (add_woc_lib)
    # TODO: Create these somehow automatically. See
    # https://cmake.org/pipermail/cmake/2010-September/039388.html
    add_woc_lib (WOCStdLib)
    add_woc_lib (Logging)
    add_woc_lib (Starboard)
    add_woc_lib (WinObjCRT)
    add_woc_lib (Foundation)
    add_woc_lib (Accelerate)
    add_woc_lib (UIKit)
    # See `tools/Logging/CMakeLists.txt`.
    target_include_directories (woc-Logging INTERFACE
        "${SOURCE_DIR}/deps/WinObjC/tools/Logging/include")

    function (add_prebuilt_lib_core name dllname)
        add_library ("${name}" SHARED IMPORTED)
        set_target_properties ("${name}" PROPERTIES
            IMPORTED_LOCATION "${SOURCE_DIR}/deps/WinObjC/deps/prebuilt/\
Universal Windows/x86/${dllname}.dll"
            IMPORTED_IMPLIB "${SOURCE_DIR}/deps/WinObjC/deps/prebuilt/\
Universal Windows/x86/${name}.lib")
    endfunction (add_prebuilt_lib_core)
    function (add_prebuilt_lib name)
        add_prebuilt_lib_core ("${name}" "${name}")
    endfunction (add_prebuilt_lib)

    # Library ICU. See <http://site.icu-project.org/>.
    # TODO: Use CMake function `FindICU` or something like that instead.
    function (add_icu_lib name)
        add_prebuilt_lib_core ("icu${name}" "icu${name}57")
    endfunction (add_icu_lib)
    add_icu_lib (dt)
    add_icu_lib (in)
    add_icu_lib (uc)

    add_prebuilt_lib (libxml2)

    # NuGet package ANGLE.WindowsStore.
    add_library (EGL SHARED IMPORTED)
    set_target_properties (EGL PROPERTIES
        IMPORTED_LOCATION "${ANGLE_DIR}/bin/UAP/Win32/libEGL.dll"
        IMPORTED_IMPLIB "${ANGLE_DIR}/bin/UAP/Win32/libEGL.lib")
    target_include_directories (EGL INTERFACE "${ANGLE_DIR}/Include")
    add_library (GLESv2 SHARED IMPORTED)
    set_target_properties (GLESv2 PROPERTIES
        IMPORTED_LOCATION "${ANGLE_DIR}/bin/UAP/Win32/libGLESv2.dll"
        IMPORTED_IMPLIB "${ANGLE_DIR}/bin/UAP/Win32/libGLESv2.lib")
    target_include_directories (GLESv2 INTERFACE "${ANGLE_DIR}/Include")

    # See
    # https://medium.com/@alasher/colored-c-compiler-output-with-ninja-clang-gcc-10bfe7f2b949.
    # TODO: Do this for CL.exe, too.
    option (FORCE_COLORED_OUTPUT "Always produce ANSI-colored output." OFF)
    if (FORCE_COLORED_OUTPUT)
        add_compile_options (-fcolor-diagnostics -fansi-escape-codes)
    endif (FORCE_COLORED_OUTPUT)

    # Target grouping all WinObjC Frameworks. See function `woc_framework`.
    add_custom_target (Frameworks)

    add_subdirectory (src)
    add_subdirectory (deps/unicorn)
    add_subdirectory (deps/WinObjC/deps/3rdparty/cassowary-0.60)
    add_subdirectory (deps/WinObjC/deps/3rdparty/libdispatch)
    add_subdirectory (deps/WinObjC/Frameworks)

endif (SUPERBUILD)
