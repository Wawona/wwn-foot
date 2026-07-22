{ lib, stdenv, pkgs, simulator ? false, iosToolchain, xcodeUtils ? iosToolchain, ... }:

let
  isTVOS = (iosToolchain ? isTVOSToolchain) && iosToolchain.isTVOSToolchain;
  sdkPlatform =
    if isTVOS then
      (if simulator then "AppleTVSimulator" else "AppleTVOS")
    else
      (if simulator then "iPhoneSimulator" else "iPhoneOS");
  minVerFlag =
    if isTVOS && simulator then
      "-mtvos-simulator-version-min=${iosToolchain.deploymentTarget}"
    else if isTVOS then
      "-mtvos-version-min=${iosToolchain.deploymentTarget}"
    else if simulator then
      "-mios-simulator-version-min=${iosToolchain.deploymentTarget}"
    else
      "-miphoneos-version-min=${iosToolchain.deploymentTarget}";
in
stdenv.mkDerivation {
  pname = "foot-ios-shim";
  version = "1.0.0";

  # Needs the host Xcode toolchain (/Applications, xcode-select), which the
  # relaxed nix sandbox hides unless the derivation opts out (CI parity with
  # the other Apple-mobile shims, e.g. weston-simple-shm).
  __noChroot = true;

  dontUnpack = true;
  nativeBuildInputs = [ xcodeUtils.findXcodeScript ];

  buildPhase = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
      fi
    fi
    export SDKROOT="$DEVELOPER_DIR/Platforms/${sdkPlatform}.platform/Developer/SDKs/${sdkPlatform}.sdk"
    CLANG="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"

    cat > foot_shim.c <<'EOF'
    #include <stdlib.h>
    /* Apple mobile: real foot is not shipped yet. Route fuzzel/Machines
     * "Foot Terminal" to weston-terminal (in-process zsh), never to
     * weston-simple-shm (that left users staring at the SHM demo). */
    extern int weston_terminal_main(int argc, char **argv);
    int wwn_foot_is_compat_shim(void) { return 1; }
    int foot_main(int argc, char **argv) {
      (void)argc;
      (void)argv;
      const char *shell = getenv("WAWONA_SHELL");
      char *shim_argv[] = {
          "weston-terminal",
          "--shell",
          (char *)(shell && shell[0] ? shell : "/usr/bin/zsh"),
          0,
      };
      return weston_terminal_main(3, shim_argv);
    }
    EOF

    "$CLANG" -c foot_shim.c -arch arm64 -isysroot "$SDKROOT" ${minVerFlag} -fPIC -o foot_shim.o
    "$AR" rcs libfoot.a foot_shim.o
  '';

  installPhase = ''
    mkdir -p $out/lib
    cp libfoot.a $out/lib/
  '';

  meta = with lib; {
    description = "Foot terminal in-process shim for iOS Wawona (routes to weston-terminal)";
    platforms   = platforms.darwin;
  };
}
