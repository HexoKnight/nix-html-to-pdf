{
  lib, stdenvNoCC,

  fontconfig,
  makeFontsConf,

  buildNpmPackage,
  linkFarm,
  substitute,

  chromium,
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
  gen-pdf-args = {
    launchArgs = (
      if useFirefox then {
        executablePath = lib.getExe firefox;
        browser = "firefox";
      } else {
        executablePath = lib.getExe chromium;
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
