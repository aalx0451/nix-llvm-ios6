{
  lib,
  llvmPackages_22,
  autoreconfHook,
  pkg-config,
  libuuid,
  openssl,
  zlib,
  swift-corelibs-libdispatch,
  symlinkJoin,
  cctools-port,
  llvmBinDir,
  spec,
}:

let
  cctools-ios = llvmPackages_22.stdenv.mkDerivation {
    pname = "cctools-port-ios";
    version = cctools-port.shortRev or "unstable";
    src = "${cctools-port}/cctools";

    nativeBuildInputs = [
      autoreconfHook
      pkg-config
    ];

    buildInputs = [
      libuuid
      openssl
      zlib
      swift-corelibs-libdispatch
    ];

    configureFlags = [
      "--target=${spec.cctoolsTarget}"
    ];

    env.NIX_CFLAGS_COMPILE = "-Wno-error";
    enableParallelBuilding = true;

    meta = {
      description = "cctools-port (${spec.cctoolsTarget})";
      platforms = lib.platforms.linux;
    };
  };

  ios-bintools = symlinkJoin {
    name = "ios-bintools";
    paths = [ cctools-ios ];
    postBuild = ''
      for tool in ar ranlib nm strip objcopy lipo install-name-tool otool libtool-darwin; do
        ln -sf "${llvmBinDir}/llvm-$tool" "$out/bin/llvm-$tool"
      done
      ln -sf "${spec.cctoolsTarget}-ld" "$out/bin/ld"
      ln -sf "${spec.cctoolsTarget}-as" "$out/bin/as"
    '';
    passthru.ld = "${ios-bintools}/bin/${spec.cctoolsTarget}-ld";
  };
in
{
  inherit cctools-ios ios-bintools;
}
