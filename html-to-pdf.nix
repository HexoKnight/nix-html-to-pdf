{
  lib, stdenvNoCC,

  fontconfig,
  makeFontsConf,

  buildNpmPackage,
  linkFarm,
  substitute,

  fetchzip,
  autoPatchelfHook,
  pkgs,

  firefox,

  libfaketime,
  qpdf,
}:

htmlFile: {
  name ? lib.removeSuffix ".html" (builtins.baseNameOf htmlFile) + ".pdf",
  fontDirectories ? [],

  # doesn't seem to work atm tho
  useFirefox ? false,

  # corresponds to https://pptr.dev/api/puppeteer.puppeteerlaunchoptions
  launchArgs ? {},

  # corresponds to https://pptr.dev/api/puppeteer.gotooptions
  gotoArgs ? {},

  # corresponds to https://pptr.dev/api/puppeteer.pdfoptions
  pdfArgs ? {},

  # set to null to not use qpdf at all
  qpdfOptions ? [
    # makes loading faster? chrome calls it 'Fast web view'
    "--linearize"
    # allows compression of objects
    "--object-streams=generate"
  ]
}:

let
  chrome-for-testing = stdenvNoCC.mkDerivation rec {
    pname = "chrome-for-testing";
    version = "130.0.6723.58";

    src = fetchzip {
      url = "https://storage.googleapis.com/chrome-for-testing-public/${version}/linux64/chrome-linux64.zip";
      hash = "sha256-YqK7MCaWc0PTbyYRtM7bDrNyicZMpie3RJUgkYLnLNE=";
    };

    nativeBuildInputs = [
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      alsa-lib.out at-spi2-atk.out cairo.out cups.lib dbus.lib expat.out glib.out libdrm.out libxkbcommon.out mesa.out nspr.out nss.out pango.out systemd.out xorg.libX11.out xorg.libXcomposite.out xorg.libXdamage.out xorg.libXext.out xorg.libXfixes.out xorg.libXrandr.out xorg.libxcb.out
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      mv -t $out *

      runHook postInstall
    '';

    env.dontAutoPatchelf = 1;
    postFixup = ''
      autoPatchelf -- $out
    '';
  };

  gen-pdf-args = {
    launchArgs = (
      if useFirefox then {
        executablePath = lib.getExe firefox;
        browser = "firefox";
      } else {
        executablePath = chrome-for-testing + /chrome;
        browser = "chrome";
      }
    ) // launchArgs;
    inherit gotoArgs pdfArgs;
    inherit htmlFile;
  };

  gen-pdf = buildNpmPackage {
    name = "gen-pdf";

    src = builtins.path {
      name = "gen-pdf-src";
      path = ./.;
      filter = path: type:
        type == "regular" &&
        lib.elem (baseNameOf path) [
          "package.json"
          "package-lock.json"
          "gen-pdf.js"
        ];
    };

    npmDepsHash = "sha256-0JaKwZMRaW5NE9QD+irTAymC673Je+mXBbKE5g2O3YE=";
    dontNpmBuild = true;

    meta.mainProgram = "gen-pdf";
  };

  fonts-conf-d = linkFarm "fonts-conf.d" (lib.genAttrs [
    "10-hinting-slight.conf"
  ] (name: fontconfig.out + /share/fontconfig/conf.avail/${name}));

  fonts-conf = substitute {
    src = makeFontsConf {
      inherit fontDirectories;
      # the defaults shouldn't be accessible in the sandbox anyway but eh
      impureFontDirectories = [];
    };
    substitutions = [
      "--replace-fail" "/etc/fonts/conf.d" fonts-conf-d
    ];
  };
in
stdenvNoCC.mkDerivation {
  inherit name htmlFile;

  enableParallelBuilding = true;

  env = {
    FONTCONFIG_FILE = fonts-conf;
    GEN_PDF_ARGS = builtins.toJSON gen-pdf-args;
  };

  passthru = {
    inherit gen-pdf-args gen-pdf;
  };

  nativeBuildInputs = [
    qpdf gen-pdf
  ];

  buildCommand = /* bash */ ''
    tmpdir=$(mktemp -d)

    (
      # chromium amirite
      export XDG_CONFIG_HOME=$tmpdir/config

      export LD_PRELOAD=${lib.getLib libfaketime}/lib/libfaketime.so.1
      export FAKETIME='1970-01-01 00:00:01'
      export FAKETIME_DONT_FAKE_MONOTONIC=1

      gen-pdf >${if qpdfOptions == null then "$out" else "$tmpdir/init.pdf"}
    )
    ${lib.optionalString (qpdfOptions != null) ''
      qpdf ${lib.escapeShellArgs qpdfOptions} --deterministic-id $tmpdir/init.pdf $out
    ''}
  '';
}
