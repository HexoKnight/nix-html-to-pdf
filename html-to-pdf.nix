{ lib, runCommand, puppeteer-cli, makeFontsConf, qpdf, jq, ... }:

htmlFile: {
  name ? lib.removeSuffix ".html" (builtins.baseNameOf htmlFile) + ".pdf",
  fontDirectories ? [],

  paperFormat ? "Letter",

  qpdfOptions ? [
    # makes loading faster? 'Fast web view' on chrome
    "--linearize"
    # allows compression of objects
    "--object-streams=generate"
  ]
}:

# TODO:
# - maybe package and use puppeteer directly
# - allow configuring more of puppeteer (eg. backend)

let
  puppeteer-cliBin = lib.getExe puppeteer-cli;
  qpdfBin = lib.getExe' qpdf "qpdf";
  jqBin = lib.getExe jq;
in
runCommand name {
  env.FONTCONFIG_FILE = makeFontsConf {
    inherit fontDirectories;
    # the defaults shouldn't be accessible in the sandbox anyway but eh
    impureFontDirectories = [];
  };
  inherit htmlFile;
} ''
  tmpdir=$(mktemp -d)
  ${puppeteer-cliBin} print $htmlFile --format ${paperFormat} $tmpdir/init.pdf

  ${qpdfBin} $tmpdir/init.pdf \
    --json-output --json-stream-data=none |
  ${jqBin} --arg date "u:D:19700101000001+00'00'" '
    .qpdf[1] |= (
      ("obj:" + .trailer.value.["/Info"]) as $info_obj |
      {
        ($info_obj): (
          .[$info_obj] |
          .value |= . + {
            "/CreationDate" : $date,
            "/ModDate" : $date,
            "/Producer" : (.["/Producer"] + " + qpdf"),
          }
        )
      }
    )
  ' >$tmpdir/update.json

  echo 'updating with json:'
  cat $tmpdir/update.json

  ${qpdfBin} ${lib.escapeShellArgs qpdfOptions} $tmpdir/init.pdf --update-from-json=$tmpdir/update.json $out
''
