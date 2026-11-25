# nix-llvm-ios6

Nix flake for cross-compiling LLVM 22.1.8 toolchain for iOS 6.

## Build

To build everything, run `nix build`.

The toolchain tree is placed under `./result/usr/share/llvm-22`.

Flake outputs:

- `ios6-llvm` -- cross-compiled LLVM, Clang, and `clang-tools-extra`
- `ios6-runtimes` -- target `libc++` and `libc++abi`
- `ios6-compiler-rt` -- target `compiler-rt` builtins
- `ios6-sdk` -- iOS 6.1 SDK sysroot with `xpc/` from `MacOSX10.8.sdk`
- `cctools-ios` -- host `cctools`

## Patches

- `patches/emutls/` -- EmuTLS codegen for legacy Darwin targets and `__cxa_thread_atexit` in `libc++abi`
- `patches/ios6/` -- iOS 6.1 compatibility fixes
- `patches/rtdyld/` -- ARM `SECTDIFF` relocations and Thumb symbol handling in `RuntimeDyld`
- `patches/toolchain/` -- `armv7`/`thumb` detection in `Host.cpp` and Darwin driver support for bundled `libc++.dylib`

## Known Issues

- `clang-repl` is statically linked against `libc++`, and dynamic linking against `libc++.dylib` is not supported yet. Evaluated code that references C++ stdlib symbols requires loading it manually with `%lib /usr/share/llvm-22/lib/libc++.dylib`.
- `clang-repl` crashes when invalid options are passed via `-Xcc` (see llvm-project/#225429).
- `thread_local` does not work in JIT mode because ORC JIT does not support EmuTLS.

## License

This project is in the Public Domain and licensed under The Unlicense.

Patch context is licensed under the Apache 2.0 License with LLVM exceptions.
