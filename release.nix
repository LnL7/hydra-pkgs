{ packageAttrs ? [ "hello" ], systemPackageAttrs ? {}
, nixpkgs ? <nixpkgs>
, supportedSystems ? [ "x86_64-linux" "x86_64-darwin" ]
, scrubJobs ? true
}:

with import ./release-lib.nix {
  inherit supportedSystems scrubJobs;
  packageSet = import nixpkgs;
};

with lib;

let

  darwinPkgs = pkgsFor "x86_64-darwin";

  defaultPackages = {
    inherit pkgs;
    inherit (pkgs) stdenv
      bash bison bzip2 coreutils ed findutils gawk gmp gettext gnugrep
      gnum4 gnumake gnused gzip ncurses patch pcre perl unzip xz zlib;
    perlPackages = pkgs.recurseIntoAttrs { inherit (pkgs.perlPackages) LocaleGettext; };
    tests = pkgs.recurseIntoAttrs { inherit (pkgs.tests) cc-wrapper stdenv-inputs; };
  }
  // optionalAttrs (elem "x86_64-linux" supportedSystems) {
    inherit (pkgs) gcc
      acl binutils busybox diffutils glibc isl libelf libmpc
      libsigsegv linuxHeaders m4 mpfr patchelf paxctl texinfo which;
  }
  // optionalAttrs (elem "x86_64-darwin" supportedSystems) {
    inherit (pkgs) clang
      autoconf automake cmake cpio flex groff help2man libcxx
      libcxxabi libedit libffi libtool libxml2 llvm pkgconfig python
      unzip;
  };

  defaultSystemPackages = {
  };

  extraPackages = {
  }
  // filterPkgs packageAttrs pkgs;

  overridePackages = {
    bootstrapTools = testOn supportedSystems (pkgs: pkgs.stdenv.bootstrapTools // { meta.platforms = platforms.all; });
    cc = testOn supportedSystems (pkgs: pkgs.stdenv.cc);
    cc-unwrapped = testOn supportedSystems (pkgs: pkgs.stdenv.cc.cc);
  }
  // optionalAttrs (elem "x86_64-darwin" supportedSystems) {
    darwin = {
      inherit (darwinPkgs.darwin)
        CF CarbonHeaders CommonCrypto Csu IOKit Libinfo Libm Libnotify Libsystem
        architecture bootstrap_cmds bsdmake cctools configd copyfile dyld eap8021x launchd
        libclosure libdispatch libiconv libpthread libresolv libutil objc4 ppp removefile xnu;
    };
  }
  // optionalAttrs (systemPackageAttrs ? "x86_64-linux") (filterPkgs systemPackageAttrs.x86_64-linux (pkgsFor "x86_64-linux"))
  // optionalAttrs (systemPackageAttrs ? "i686-linux") (filterPkgs systemPackageAttrs.i686-linux (pkgsFor "i686-linux"))
  // optionalAttrs (systemPackageAttrs ? "x86_64-darwin") (filterPkgs systemPackageAttrs.x86_64-darwin (pkgsFor "x86_64-darwin"));

  jobs = {

    unstable = pkgs.releaseTools.aggregate {
      name = "nixpkgs-unstable-${nixpkgsVersion}";
      constituents = [ ];
    };

    tested = pkgs.releaseTools.aggregate {
      name = "nixpkgs-tested-${nixpkgsVersion}";
      constituents =
        [ jobs.stdenv.x86_64-linux
          jobs.stdenv.x86_64-darwin
          jobs.cc.x86_64-linux
          jobs.cc.x86_64-darwin
          jobs.cc-unwrapped.x86_64-linux
          jobs.cc-unwrapped.x86_64-darwin

          jobs.tests.cc-wrapper.x86_64-linux
          jobs.tests.cc-wrapper.x86_64-darwin
          jobs.tests.stdenv-inputs.x86_64-linux
          jobs.tests.stdenv-inputs.x86_64-darwin
        ]
        ++ collect isDerivation jobs.makeBootstrapTools;
    };

    stdenvMetrics = pkgs.stdenv.mkDerivation {
      name = "stdenv-metrics";
      nativeBuildInputs = [ pkgs.nix ];
      buildCommand = ''
        export NIX_REMOTE=$NIX_BUILD_TOP
        nix-store --init

        nix-store -qR $(nix-instantiate ${nixpkgs} -A stdenv --argstr system x86_64-linux) > linux-stdenv
        nix-store -qR $(nix-instantiate ${nixpkgs} -A stdenv --argstr system x86_64-darwin) > darwin-stdenv

        mkdir -p $out/nix-support
        touch $out/nix-support/hydra-build-products
        echo "linux-stdenv.requisites.count $(wc -l linux-stdenv)" >> $out/nix-support/hydra-metrics
        echo "darwin-stdenv.requisites.count $(wc -l darwin-stdenv)" >> $out/nix-support/hydra-metrics
      '';
    };

    makeBootstrapTools =
      genAttrs supportedSystems
        (system: {
          inherit (import (nixpkgs + "/pkgs/stdenv/linux/make-bootstrap-tools.nix") { inherit system; })
            dist test;
        })
      # darwin is special in this
      // optionalAttrs (builtins.elem "x86_64-darwin" supportedSystems) {
        x86_64-darwin =
          let
            bootstrap = import (nixpkgs + "/pkgs/stdenv/darwin/make-bootstrap-tools.nix") { system = "x86_64-darwin"; };
          in {
            # Lightweight distribution and test
            inherit (bootstrap) dist test;
            # Test a full stdenv bootstrap from the bootstrap tools definition
            inherit (bootstrap.test-pkgs) stdenv;
          };
        };
  }
  // mapTestOn (packagePlatforms defaultPackages)
  // mapTestOn (packagePlatforms extraPackages)
  // overridePackages;

in
  jobs
