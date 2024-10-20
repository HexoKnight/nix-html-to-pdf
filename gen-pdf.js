import puppeteer from 'puppeteer-core';

const ARG_ENV_VAR = "GEN_PDF_ARGS";

function info(...args) {
    // so that it goes to stderr
    console.error(...args)
}

const argEnvVarValue = process.env[ARG_ENV_VAR];
if (argEnvVarValue === undefined) {
    console.error("gen-pdf: error: " + ARG_ENV_VAR + " is unset!");
    process.exit(1);
}

info("gen-pdf: raw args:");
info(argEnvVarValue);
const args = JSON.parse(argEnvVarValue);

info("gen-pdf: parsed args:");
info(args);

const url = "file://" + args.htmlFile.split('/').map(encodeURIComponent).join('/');
info("gen-pdf: using url: " + url);

// [0] is node, [1] is script
const outFile = process.argv[2];

const browser = await puppeteer.launch(args.launchArgs);

const page = await browser.newPage();
await page.goto(url, args.gotoArgs);

const buffer = await page.pdf(args.pdfArgs);

// checks if null or undefined
if ((args.pdfArgs ?? {}).path == null) {
    await process.stdout.write(buffer);
}

await browser.close();
