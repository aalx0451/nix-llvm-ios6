{
  pkgs,
  spec,
  sdk,
  bintools,
  llvmHost,
  llvm-project-src,
}:

let
  inherit (pkgs) lib;
  patches = import ./patches.nix;
in
{
  patches = pkgs.runCommand "ios6-patches-check" { } ''
    cp -a "${llvm-project-src}" src
    chmod -R u+w src

    apply_patch() {
      local dir="$1"
      local p="$2"
      echo "==> $p (in $dir)"
      patch -p1 --no-backup-if-mismatch -d "$dir" < "$p"
      echo "$p" >> "$out"
    }

    : > "$out"
    apply_patch src/llvm "${patches.emutls.llvm}"
    apply_patch src/clang "${patches.emutls.clang}"

    for p in ${lib.escapeShellArgs patches.monorepo}; do
      apply_patch src "$p"
    done
  '';

  cross-smoke =
    pkgs.runCommand "ios6-cross-smoke-test"
      {
        nativeBuildInputs = [
          llvmHost.llvmPkgs.clang
          llvmHost.llvmPkgs.llvm
          bintools.ios-bintools
        ];
      }
      ''
        cat > main.cpp <<'EOF'
        #include <chrono>
        #include <iostream>

        struct TlsObj {
          int v = 42;
          ~TlsObj() { v = 0; }
        };
        thread_local TlsObj tls;

        int main() {
          auto now = std::chrono::steady_clock::now().time_since_epoch().count();
          std::cout << tls.v << " " << now << "\n";
          return 0;
        }
        EOF

        "${llvmHost.clangUnwrappedBinDir}/clang++" \
          -target "${spec.iosHostTriple}" \
          -arch "${spec.iosArch}" \
          -miphoneos-version-min="${spec.iosMinVersion}" \
          -isysroot "${sdk.sdkRoot}" \
          -B"${bintools.ios-bintools}/bin" \
          --ld-path="${bintools.ios-bintools.ld}" \
          -Wl,-syslibroot,"${sdk.sdkRoot}" \
          -D_LIBCPP_DISABLE_AVAILABILITY \
          -nostdinc++ -isystem "${llvmHost.ios6-runtimes.includeDir}" \
          -nostdlib++ \
          -L"${llvmHost.ios6-runtimes.libDir}" -lc++ \
          -L"${llvmHost.ios6-compiler-rt.libDir}" -lclang_rt.ios \
          -std=c++20 main.cpp -o main

        llvm-readobj --file-headers --needed-libs main | tee "$out"
        grep -q "libc++.1.dylib" "$out"
      '';
}
