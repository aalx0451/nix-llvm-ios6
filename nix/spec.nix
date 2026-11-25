rec {
  llvmMajor = "22";
  llvmVersion = "22.1.8";
  installPrefix = "/usr/share/llvm-${llvmMajor}";
  clangResourceDir = "${installPrefix}/lib/clang/${llvmMajor}";

  iosArch = "armv7";
  iosMinVersion = "6";
  iosHostTriple = "${iosArch}-apple-ios${iosMinVersion}";
  iosDefaultTargetTriple = "${iosArch}-apple-ios6.1";

  cctoolsTarget = "arm-apple-darwin11";
  iosSdkName = "iPhoneOS6.1.sdk";
}
