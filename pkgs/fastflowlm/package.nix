{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  jq,
  boost,
  curl,
  libdrm,
  libedit,
  libjpeg_turbo,
  libogg,
  libopus,
  libuuid,
  libvorbis,
  libwebp,
  cargo,
  rustc,
  rustPlatform,
  autoPatchelfHook,
  versionCheckHook,
  makeWrapper,
  callPackage,
}: let
  # XRT, the amdxdna plugin and their join live inside this package on purpose:
  # the flake discovers every pkgs/<name>/package.nix and calls it with plain
  # pkgs.callPackage, so sibling packages could not see each other, and a
  # top-level `xrt` would shadow nixpkgs' in the overlay.
  xrt = callPackage ./xrt {};
  xrt-plugin-amdxdna = callPackage ./xrt-plugin-amdxdna {inherit xrt;};
  # Not plain xrt: the plugin has to sit next to the libxrt_coreutil flm
  # loads, see ./xrt-combined.
  xrt-combined = callPackage ./xrt-combined {inherit xrt xrt-plugin-amdxdna;};
in
  stdenv.mkDerivation (finalAttrs: {
  pname = "fastflowlm";
  version = "1.0.11";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "FastFlowLM";
    tag = "v${finalAttrs.version}";
    hash = "sha256-XSm9mCO/NjN9obzQgMr6DmHm3cdI23RezkGxWsk1b5s=";
    # third_party/tokenizers-cpp is built below; third_party/xgrammar's
    # sources are compiled straight into flm.
    fetchSubmodules = true;
  };

  # Only the build fix is kept: use-system-codecs.patch links the codecs from
  # nixpkgs instead of letting CMake ExternalProject download tarballs during
  # the build (the Nix sandbox has no network). The 23 server-hardening patches
  # of github:noamsto/nix-amd-ai were deliberately left out: ~3000 lines of C++
  # that were only keyword-scanned, not reviewed. See README.md.
  patches = [
    ./patches/use-system-codecs.patch
  ];

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ./Cargo.lock;
  };

  cargoRoot = "third_party/tokenizers-cpp/rust";

  nativeBuildInputs = [
    cmake
    jq
    ninja
    pkg-config
    cargo
    rustc
    rustPlatform.cargoSetupHook
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    boost
    curl
    libdrm
    libedit
    libjpeg_turbo
    libogg
    libopus
    libuuid
    libvorbis
    libwebp
    stdenv.cc.cc.lib
    xrt-combined
  ];

  postPatch = ''
    # Cargo.lock is not committed upstream; inject our copy
    cp ${./Cargo.lock} third_party/tokenizers-cpp/rust/Cargo.lock
  '';

  # The source root stays at the top of the checkout for cargoRoot and the
  # patches; the CMake project is in src/.
  cmakeDir = "../src";

  # XRT is found through its pkg-config file, so no XRT_INCLUDE_DIR/XRT_LIB_DIR.
  cmakeFlags = [
    (lib.cmakeFeature "FLM_VERSION" finalAttrs.version)
    (lib.cmakeFeature "CMAKE_XCLBIN_PREFIX" "${placeholder "out"}/share/flm")
    # The cmake setup hook passes these as absolute paths, but CMakeLists.txt
    # joins CMAKE_INSTALL_LIBDIR onto $ORIGIN/.. for flm's RPATH. Single output,
    # so the relative forms are equivalent.
    # See https://github.com/NixOS/nixpkgs/issues/144170
    (lib.cmakeFeature "CMAKE_INSTALL_BINDIR" "bin")
    (lib.cmakeFeature "CMAKE_INSTALL_LIBDIR" "lib")
  ];

  # NPU_VERSION is the minimum AMD NPU driver version, kept in
  # src/CMakePresets.json upstream. Currently only used on Windows.
  preConfigure = ''
    cmakeFlagsArray+=(
      "-DNPU_VERSION=$(jq -er '
        .configurePresets[]
        | select(.name == "common-default")
        | .cacheVariables.NPU_VERSION
      ' src/CMakePresets.json)"
    )
  '';

  # Point flm at the combined XRT (plugin next to libxrt_coreutil) and silence
  # its update probe: Nix owns the version, and the probe is a network call on
  # every run/serve. --set-default keeps the caller able to override both.
  postFixup = ''
    wrapProgram $out/bin/flm \
      --set-default XRT_PATH ${xrt-combined} \
      --set-default XILINX_XRT ${xrt-combined} \
      --set-default FLM_DISABLE_UPDATE_CHECK 1
  '';

  nativeInstallCheckInputs = [
    versionCheckHook
  ];
  doInstallCheck = true;

  passthru = {
    # For the NixOS side (environment variables, services).
    inherit xrt xrt-plugin-amdxdna xrt-combined;
  };

  meta = {
    description = "NPU-optimized LLM runtime for AMD Ryzen AI";
    homepage = "https://github.com/ROCm/FastFlowLM";
    changelog = "https://github.com/ROCm/FastFlowLM/releases/tag/${finalAttrs.src.tag}";
    # Source is MIT; the NPU kernels in share/flm are proprietary
    # (see LICENSE_BINARY.txt upstream).
    license = [lib.licenses.mit lib.licenses.unfree];
    # The prebuilt engine libraries (src/lib/xrt/*.so) are host code; the
    # xclbins are NPU firmware.
    sourceProvenance = with lib.sourceTypes; [fromSource binaryNativeCode binaryFirmware];
    platforms = ["x86_64-linux"];
    mainProgram = "flm";
  };
})
