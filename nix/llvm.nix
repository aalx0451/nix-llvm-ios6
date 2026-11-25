{
  pkgs,
  lib,
  spec,
  llvm-project-src,
  ios6-sdk,
  cctools-ios,
  ios-bintools,
}:

let
  patches = import ./patches.nix;

  # host clang/llvm patched to emit EmuTLS for iOS < 9 targets
  llvmPkgs = pkgs.llvmPackages_22.overrideScope (
    _: prev: {
      libllvm = prev.libllvm.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ patches.emutls.llvm ];
        doCheck = false;
      });
      clang-unwrapped = prev.clang-unwrapped.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ patches.emutls.clang ];
        doCheck = false;
      });
    }
  );

  llvmBinDir = "${lib.getBin llvmPkgs.llvm}/bin";
  clangUnwrappedBinDir = "${lib.getBin llvmPkgs.clang-unwrapped}/bin";

  llvm-project-ios6 = pkgs.applyPatches {
    name = "llvm-project-${spec.llvmVersion}-ios6";
    src = llvm-project-src;
    prePatch = ''
      patch -p1 -d llvm < ${patches.emutls.llvm}
      patch -p1 -d clang < ${patches.emutls.clang}
    '';
    patches = patches.monorepo;
  };

  baseDarwinCompileFlags = [
    "-target ${spec.iosHostTriple}"
    "-arch ${spec.iosArch}"
    "-miphoneos-version-min=${spec.iosMinVersion}"
    "-isysroot ${ios6-sdk.sdkRoot}"
    "-B${ios-bintools}/bin"
  ];

  baseLd64Flags = [
    "--ld-path=${ios-bintools.ld}"
    "-Wl,-syslibroot,${ios6-sdk.sdkRoot}"
  ];

  mkToolchainFile =
    {
      name,
      extraCxxFlags ? [ ],
      exeLinkerFlags ? baseLd64Flags,
      sharedLinkerFlags ? baseLd64Flags,
      moduleLinkerFlags ? sharedLinkerFlags,
    }:
    let
      commonFlags = lib.concatStringsSep " " baseDarwinCompileFlags;
      cxxFlags = lib.concatStringsSep " " (baseDarwinCompileFlags ++ extraCxxFlags);
      exeFlags = lib.concatStringsSep " " exeLinkerFlags;
      sharedFlags = lib.concatStringsSep " " sharedLinkerFlags;
      moduleFlags = lib.concatStringsSep " " moduleLinkerFlags;
    in
    pkgs.writeText "toolchain-${name}.cmake" ''
      set(CMAKE_SYSTEM_NAME Darwin)
      set(CMAKE_SYSTEM_PROCESSOR arm)

      set(CMAKE_SYSROOT "${ios6-sdk.sdkRoot}")
      set(CMAKE_OSX_SYSROOT "${ios6-sdk.sdkRoot}")

      set(CMAKE_C_COMPILER "${clangUnwrappedBinDir}/clang")
      set(CMAKE_CXX_COMPILER "${clangUnwrappedBinDir}/clang++")

      set(CMAKE_AR "${llvmBinDir}/llvm-ar" CACHE FILEPATH "Archiver")
      set(CMAKE_RANLIB "${llvmBinDir}/llvm-ranlib" CACHE FILEPATH "Ranlib")
      set(CMAKE_NM "${llvmBinDir}/llvm-nm" CACHE FILEPATH "NM")
      set(CMAKE_STRIP "${llvmBinDir}/llvm-strip" CACHE FILEPATH "Strip")
      set(CMAKE_LIPO "${llvmBinDir}/llvm-lipo" CACHE FILEPATH "Lipo")
      set(CMAKE_INSTALL_NAME_TOOL "${llvmBinDir}/llvm-install-name-tool" CACHE FILEPATH "Install name tool")

      set(CMAKE_LINKER "${ios-bintools.ld}" CACHE FILEPATH "Linker")

      set(CMAKE_C_FLAGS_INIT "${commonFlags}")
      set(CMAKE_CXX_FLAGS_INIT "${cxxFlags}")

      set(CMAKE_EXE_LINKER_FLAGS_INIT "${exeFlags}")
      set(CMAKE_SHARED_LINKER_FLAGS_INIT "${sharedFlags}")
      set(CMAKE_MODULE_LINKER_FLAGS_INIT "${moduleFlags}")

      set(CMAKE_FIND_ROOT_PATH "${ios6-sdk.sdkRoot}")
      set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
      set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
      set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

      set(CMAKE_C_COMPILER_TARGET "${spec.iosHostTriple}")
      set(CMAKE_CXX_COMPILER_TARGET "${spec.iosHostTriple}")
      set(CMAKE_ASM_COMPILER_TARGET "${spec.iosHostTriple}")
    '';

  crossTools =
    (with pkgs; [
      cmake
      ninja
      python3
    ])
    ++ [
      llvmPkgs.clang
      llvmPkgs.llvm
      cctools-ios
    ];

  mkCrossCmake =
    {
      pname,
      srcSubdir,
      toolchainFile,
      cmakeFlags ? [ ],
      ninjaBuildTargets ? [ ],
      ninjaInstallTarget ? "install",
      postInstall ? "",
      passthru ? { },
      meta ? { },
    }:
    llvmPkgs.stdenv.mkDerivation {
      inherit
        pname
        postInstall
        passthru
        meta
        ;
      version = spec.llvmVersion;

      dontUnpack = true;
      dontUseCmakeConfigure = true;
      dontUseNinjaBuild = true;
      dontUseNinjaInstall = true;
      dontFixup = true;

      nativeBuildInputs = crossTools;
      env.TERM = "dumb";

      configurePhase = ''
        runHook preConfigure

        export TERM=dumb
        cmake -G Ninja \
          -S "${llvm-project-ios6}/${srcSubdir}" \
          -B build \
          ${lib.escapeShellArgs (
            [
              "-DCMAKE_TOOLCHAIN_FILE=${toolchainFile}"
              "-DCMAKE_BUILD_TYPE=Release"
            ]
            ++ cmakeFlags
          )}

        runHook postConfigure
      '';

      buildPhase = ''
        runHook preBuild

        export TERM=dumb
        ninja -C build -j"$NIX_BUILD_CORES" ${
          lib.optionalString (ninjaBuildTargets != [ ]) (lib.escapeShellArgs ninjaBuildTargets)
        }

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        export TERM=dumb
        DESTDIR="$out" ninja -C build -j"$NIX_BUILD_CORES" ${lib.escapeShellArg ninjaInstallTarget}

        runHook postInstall
      '';
    };

  stage1Toolchain = mkToolchainFile {
    name = "ios6-stage1-builtins";
  };

  ios6-compiler-rt = mkCrossCmake {
    pname = "ios6-compiler-rt";
    srcSubdir = "compiler-rt";
    toolchainFile = stage1Toolchain;
    ninjaBuildTargets = [ "builtins" ];
    ninjaInstallTarget = "install-builtins";
    cmakeFlags = [
      "-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG -Wno-atomic-alignment"
      "-DCMAKE_INSTALL_PREFIX=${spec.clangResourceDir}"
      "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY"
      "-DDARWIN_iphoneos_CACHED_SYSROOT=${ios6-sdk.sdkRoot}"
      "-DDARWIN_iphonesimulator_CACHED_SYSROOT=${ios6-sdk.sdkRoot}"
      "-DDARWIN_iphonesimulator_OVERRIDE_SDK_VERSION=6.0"
      "-DDARWIN_macosx_CACHED_SYSROOT=${ios6-sdk.sdkRoot}"
      "-DDARWIN_macosx_OVERRIDE_SDK_VERSION=10.8"
      "-DDARWIN_ios_BUILTIN_ARCHS=${spec.iosArch}"
      "-DCOMPILER_RT_BUILD_BUILTINS=ON"
      "-DCOMPILER_RT_BUILD_SANITIZERS=OFF"
      "-DCOMPILER_RT_BUILD_XRAY=OFF"
      "-DCOMPILER_RT_BUILD_LIBFUZZER=OFF"
      "-DCOMPILER_RT_BUILD_PROFILE=OFF"
      "-DCOMPILER_RT_BUILD_MEMPROF=OFF"
      "-DCOMPILER_RT_BUILD_ORC=OFF"
      "-DCOMPILER_RT_ENABLE_IOS=ON"
    ];
    passthru.libDir = "${ios6-compiler-rt}${spec.clangResourceDir}/lib/darwin";
    meta = {
      description = "compiler-rt builtins for iOS 6 (armv7)";
      platforms = lib.platforms.linux;
    };
  };

  stage1LinkerFlags = baseLd64Flags ++ [
    "-L${ios6-compiler-rt.libDir}"
    "-lclang_rt.ios"
  ];

  stage2Toolchain = mkToolchainFile {
    name = "ios6-stage2-runtimes";
    exeLinkerFlags = stage1LinkerFlags;
    sharedLinkerFlags = stage1LinkerFlags;
  };

  ios6-runtimes = mkCrossCmake {
    pname = "ios6-runtimes";
    srcSubdir = "runtimes";
    toolchainFile = stage2Toolchain;
    cmakeFlags = [
      "-DCMAKE_INSTALL_PREFIX=${spec.installPrefix}"
      "-DCMAKE_INSTALL_NAME_DIR=${spec.installPrefix}/lib"
      "-DCMAKE_OSX_ARCHITECTURES=${spec.iosArch}"
      "-DLLVM_ENABLE_RUNTIMES=libcxx;libcxxabi"
      "-DLIBCXX_ENABLE_SHARED=ON"
      "-DLIBCXX_ENABLE_STATIC=ON"
      "-DLIBCXXABI_ENABLE_SHARED=ON"
      "-DLIBCXXABI_ENABLE_STATIC=ON"
      "-DLIBCXXABI_USE_LLVM_UNWINDER=OFF"
    ];
    postInstall = ''
      libDir="$out${spec.installPrefix}/lib"
      installLibDir="${spec.installPrefix}/lib"
      llvm-install-name-tool -id "$installLibDir/libc++abi.1.dylib" "$libDir/libc++abi.1.0.dylib"
      llvm-install-name-tool -id "$installLibDir/libc++.1.dylib" "$libDir/libc++.1.0.dylib"
      llvm-install-name-tool -change @rpath/libc++abi.1.dylib "$installLibDir/libc++abi.1.dylib" "$libDir/libc++.1.0.dylib"
    '';
    passthru = {
      includeDir = "${ios6-runtimes}${spec.installPrefix}/include/c++/v1";
      libDir = "${ios6-runtimes}${spec.installPrefix}/lib";
      staticLibs = [
        "${ios6-runtimes}${spec.installPrefix}/lib/libc++.a"
        "${ios6-runtimes}${spec.installPrefix}/lib/libc++abi.a"
      ];
    };
    meta = {
      description = "libc++ and libc++abi for iOS 6 (armv7)";
      platforms = lib.platforms.linux;
    };
  };

  mkStage2LinkerFlags =
    rpath:
    [ "-nostdlib++" ]
    ++ baseLd64Flags
    ++ [
      "-Wl,-rpath,${rpath}"
      "-Wl,-rpath,${spec.installPrefix}/lib"
    ]
    ++ ios6-runtimes.staticLibs
    ++ [
      "-L${ios6-compiler-rt.libDir}"
      "-lclang_rt.ios"
    ];

  stage3Toolchain = mkToolchainFile {
    name = "ios6-stage3-llvm";
    extraCxxFlags = [
      "-D_LIBCPP_DISABLE_AVAILABILITY"
      "-nostdinc++"
      "-isystem ${ios6-runtimes.includeDir}"
    ];
    exeLinkerFlags = mkStage2LinkerFlags "@executable_path/../lib";
    sharedLinkerFlags = mkStage2LinkerFlags "@loader_path";
  };

  ios6-llvm = mkCrossCmake {
    pname = "ios6-llvm";
    srcSubdir = "llvm";
    toolchainFile = stage3Toolchain;
    cmakeFlags = [
      "-DCMAKE_INSTALL_PREFIX=${spec.installPrefix}"
      "-DCMAKE_INSTALL_NAME_DIR=${spec.installPrefix}/lib"
      "-DCMAKE_OSX_ARCHITECTURES=${spec.iosArch}"
      "-DLLVM_HOST_TRIPLE=${spec.iosHostTriple}"
      "-DLLVM_DEFAULT_TARGET_TRIPLE=${spec.iosDefaultTargetTriple}"
      "-DLLVM_TARGETS_TO_BUILD=ARM;X86;AArch64"
      "-DLLVM_ENABLE_THREADS=ON"
      "-DLLVM_ENABLE_PROJECTS=clang;clang-tools-extra"
      "-DLLVM_ENABLE_LIBXML2=OFF"
      "-DLLVM_ENABLE_ZSTD=OFF"
      "-DLLVM_ENABLE_ZLIB=ON"
      "-DLLVM_ENABLE_TERMINFO=OFF"
      "-DLLVM_INCLUDE_TESTS=OFF"
      "-DLLVM_INCLUDE_BENCHMARKS=OFF"
      "-DLLVM_INCLUDE_EXAMPLES=OFF"
      "-DCLANG_INCLUDE_TESTS=OFF"
    ];
    meta = {
      description = "LLVM and Clang ${spec.llvmVersion} for iOS 6 (armv7)";
      platforms = lib.platforms.linux;
    };
  };

  # Materialize a real directory tree (not symlinks) so it can be archived onto the device.
  ios6-llvm-bundle =
    pkgs.runCommand "ios6-llvm-${spec.llvmMajor}-bundle"
      {
        meta = {
          description = "Relocatable LLVM ${spec.llvmVersion} toolchain bundle for iOS 6.1 (armv7)";
          platforms = lib.platforms.linux;
        };
      }
      ''
        mkdir -p "$out"
        for pkg in ${
          lib.escapeShellArgs [
            ios6-llvm
            ios6-runtimes
            ios6-compiler-rt
          ]
        }; do
          cp -a "$pkg/." "$out/"
          chmod -R u+w "$out"
        done
      '';
in
{
  inherit
    llvmPkgs
    llvmBinDir
    clangUnwrappedBinDir
    crossTools
    stage1Toolchain
    llvm-project-ios6
    ios6-compiler-rt
    ios6-runtimes
    ios6-llvm
    ios6-llvm-bundle
    ;
}
