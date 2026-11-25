{
  description = "Cross-compile LLVM 22.1.8 for iOS 6.1 (armv7)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    cctools-port = {
      url = "github:tpoechtrager/cctools-port";
      flake = false;
    };
    llvm-project-src = {
      url = "github:llvm/llvm-project/llvmorg-22.1.8";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      cctools-port,
      llvm-project-src,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      spec = import ./nix/spec.nix;

      forAllSystems =
        f:
        lib.genAttrs supportedSystems (
          system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
            sdk = pkgs.callPackage ./nix/sdk.nix { inherit spec; };
            llvmHost = import ./nix/llvm.nix {
              inherit
                pkgs
                lib
                spec
                llvm-project-src
                ;
              ios6-sdk = sdk;
              inherit (bintools) cctools-ios ios-bintools;
            };
            bintools = pkgs.callPackage ./nix/cctools.nix {
              inherit cctools-port spec;
              llvmBinDir = llvmHost.llvmBinDir;
            };
          in
          f {
            inherit
              pkgs
              sdk
              bintools
              llvmHost
              ;
          }
        );
    in
    {
      packages = forAllSystems (
        {
          sdk,
          bintools,
          llvmHost,
          ...
        }:
        {
          default = llvmHost.ios6-llvm-bundle;
          llvm-bundle = llvmHost.ios6-llvm-bundle;
          ios6-sdk = sdk;
          inherit (bintools) cctools-ios ios-bintools;
          inherit (llvmHost)
            llvm-project-ios6
            ios6-compiler-rt
            ios6-runtimes
            ios6-llvm
            ;
        }
      );

      devShells = forAllSystems (
        {
          pkgs,
          sdk,
          bintools,
          llvmHost,
        }:
        {
          default = (pkgs.mkShell.override { stdenv = llvmHost.llvmPkgs.stdenv; }) {
            packages =
              llvmHost.crossTools
              ++ [ bintools.ios-bintools ]
              ++ (with pkgs; [
                git
                pkg-config
              ]);

            env = {
              TARGET_CC = "${llvmHost.clangUnwrappedBinDir}/clang";
              TARGET_CXX = "${llvmHost.clangUnwrappedBinDir}/clang++";
              LLVM_TOOLS_BIN = llvmHost.llvmBinDir;
              CCTOOLS_BIN = "${bintools.ios-bintools}/bin";
              CCTOOLS_LD = bintools.ios-bintools.ld;
              IOS_SDK_PATH = sdk.sdkRoot;
              IOS_TOOLCHAIN_FILE = llvmHost.stage1Toolchain;
              LLVM_SRC = "${llvmHost.llvm-project-ios6}";
              PREFIX = spec.installPrefix;
            };

            shellHook = ''
              echo "Host clang:   $(clang --version | head -n1)"
              echo "Target clang: $TARGET_CC"
              echo "ld64:         $CCTOOLS_LD"
              echo "SDK:          $IOS_SDK_PATH"
              echo "Toolchain:    $IOS_TOOLCHAIN_FILE"
              echo "LLVM_SRC:     $LLVM_SRC"
            '';
          };
        }
      );

      checks = forAllSystems (
        {
          pkgs,
          sdk,
          bintools,
          llvmHost,
        }:
        import ./nix/checks.nix {
          inherit
            pkgs
            spec
            sdk
            bintools
            llvmHost
            llvm-project-src
            ;
        }
      );

      formatter = forAllSystems ({ pkgs, ... }: pkgs.nixfmt-tree);
    };
}
