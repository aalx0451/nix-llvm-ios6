{
  emutls = {
    llvm = ../patches/emutls/llvm-emutls-darwin.patch;
    clang = ../patches/emutls/clang-emutls-darwin.patch;
  };

  monorepo = [
    ../patches/emutls/libcxxabi-cxa-thread-atexit-darwin.patch
    ../patches/ios6/llvm-support-clonefile-guard.patch
    ../patches/ios6/llvm-support-pthread-qos-guard.patch
    ../patches/ios6/compiler-rt-arm-fnan2-branch.patch
    ../patches/ios6/libcxx-clock-gettime-fallback.patch
    ../patches/ios6/libcxx-filesystem-remove-all-fallback.patch
    ../patches/ios6/libcxx-aligned-alloc-posix-memalign.patch
    ../patches/ios6/libcxx-disable-overridable-function-arm.patch
    ../patches/rtdyld/llvm-rtdyld-macho-arm-sectdiff.patch
    ../patches/rtdyld/llvm-rtdyld-thumb-symbol-addr.patch
    ../patches/toolchain/llvm-host-preserve-arm-subarch.patch
    ../patches/toolchain/clang-darwin-bundled-libcxx.patch
    ../patches/toolchain/clang-repl-emutls-wrapper-decl.patch
    ../patches/toolchain/clang-repl-init-error-guard.patch
  ];
}
