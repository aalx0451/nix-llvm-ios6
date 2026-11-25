{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  gnutar,
  bzip2,
  rsync,
  spec,
}:

let
  ios6SdkZip = fetchurl {
    url = "https://github.com/GrowtopiaJaw/iPhoneOS-SDK/releases/download/v1.0/iPhoneOS6.1.sdk.zip";
    hash = "sha256-JpbfF/xI4bbqP3rNNGtfI1b7XGzGCw86rKDCRSLXYd4=";
  };

  osx108SdkTbz = fetchurl {
    url = "https://github.com/alexey-lysiuk/macos-sdk/releases/download/10.8/MacOSX10.8.tar.bz2";
    hash = "sha256-264qluFjgmhR96+M1KatUB+2FAEc33uAMEzV2oyEzXk=";
  };

  osxMissingHeaders = [
    "usr/include/xpc"
  ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "iphoneos6.1-sdk";
  version = "6.1";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  nativeBuildInputs = [
    unzip
    gnutar
    bzip2
    rsync
  ];

  installPhase = ''
    runHook preInstall

    sdkOut="$out/${spec.iosSdkName}"
    mkdir -p tmp_ios tmp_osx "$sdkOut"

    unzip -q "${ios6SdkZip}" -d tmp_ios
    shopt -s dotglob
    if [ -d "tmp_ios/${spec.iosSdkName}" ]; then
      mv "tmp_ios/${spec.iosSdkName}"/* "$sdkOut/"
    else
      mv tmp_ios/* "$sdkOut/"
    fi

    tar -xjf "${osx108SdkTbz}" -C tmp_osx
    if [ -d tmp_osx/MacOSX10.8.sdk ]; then
      osx_root="tmp_osx/MacOSX10.8.sdk"
    else
      osx_root="tmp_osx"
    fi

    chmod -R u+w "$sdkOut"

    for rel in ${lib.escapeShellArgs osxMissingHeaders}; do
      src="$osx_root/$rel"
      dst="$sdkOut/$rel"
      if [ -d "$src" ]; then
        mkdir -p "$dst"
        rsync -a --ignore-existing "$src/" "$dst/"
      elif [ -e "$src" ] && [ ! -e "$dst" ]; then
        mkdir -p "$(dirname "$dst")"
        cp -a "$src" "$dst"
      fi
    done

    chmod -R u+w "$sdkOut"

    runHook postInstall
  '';

  passthru.sdkRoot = "${finalAttrs.finalPackage}/${spec.iosSdkName}";

  meta = {
    description = "iPhoneOS 6.1 SDK with supplementary macOS 10.8 headers";
    platforms = lib.platforms.linux;
  };
})
