import { access, cp, mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const srcFile = path.join(projectRoot, "src", "index.html");
const srcAssets = path.join(projectRoot, "src", "assets");
const distDir = path.join(projectRoot, "dist");
const distFile = path.join(distDir, "index.html");
const distAssets = path.join(distDir, "assets");
const distScreenshots = path.join(distAssets, "screenshots");
const macosDownloadUrl = process.env.AUSEARCH_MACOS_DOWNLOAD_URL;
const instantshareDownloadUrl = process.env.INSTANTSHARE_DOWNLOAD_URL;
const screenshotSizeLimitBytes = 512 * 1024;
const screenshotMinDimension = 320;
const screenshotScaleFactor = 0.85;

if (!macosDownloadUrl) {
  throw new Error("AUSEARCH_MACOS_DOWNLOAD_URL is required to build dist/index.html");
}
if (!instantshareDownloadUrl) {
  throw new Error("INSTANTSHARE_DOWNLOAD_URL is required to build dist/index.html");
}

let html = await readFile(srcFile, "utf8");
html = html.replaceAll("__AUSEARCH_MACOS_DOWNLOAD_URL__", escapeHtmlAttribute(macosDownloadUrl));
html = html.replaceAll("__INSTANTSHARE_DOWNLOAD_URL__", escapeHtmlAttribute(instantshareDownloadUrl));

await rm(distDir, { recursive: true, force: true });
await mkdir(distDir, { recursive: true });
await writeFile(distFile, minifyHtml(html), "utf8");

if (await exists(srcAssets)) {
  await cp(srcAssets, distAssets, { recursive: true });
}

await downscaleLargeScreenshots(distScreenshots);

process.stdout.write("Built dist/index.html\n");

function minifyHtml(input) {
  return input
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/\n+/g, " ")
    .replace(/\s{2,}/g, " ")
    .replace(/>\s+</g, "><")
    .trim();
}

function escapeHtmlAttribute(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

async function exists(targetPath) {
  try {
    await access(targetPath);
    return true;
  } catch {
    return false;
  }
}

async function downscaleLargeScreenshots(screenshotDir) {
  if (!(await exists(screenshotDir))) {
    return;
  }

  ensureSipsAvailable();

  for (const entry of await readdir(screenshotDir, { withFileTypes: true })) {
    if (!entry.isFile() || !isResizableImage(entry.name)) {
      continue;
    }

    await downscaleScreenshot(path.join(screenshotDir, entry.name));
  }
}

async function downscaleScreenshot(filePath) {
  let currentSize = (await stat(filePath)).size;

  if (currentSize <= screenshotSizeLimitBytes) {
    return;
  }

  let currentMaxDimension = getImageMaxDimension(filePath);

  while (currentSize > screenshotSizeLimitBytes && currentMaxDimension > screenshotMinDimension) {
    const nextMaxDimension = Math.max(
      Math.floor(currentMaxDimension * screenshotScaleFactor),
      screenshotMinDimension,
    );

    if (nextMaxDimension >= currentMaxDimension) {
      break;
    }

    execFileSync("sips", ["-Z", String(nextMaxDimension), filePath], { stdio: "ignore" });
    currentSize = (await stat(filePath)).size;
    currentMaxDimension = getImageMaxDimension(filePath);
  }

  if (currentSize > screenshotSizeLimitBytes) {
    process.stdout.write(
      `Warning: ${path.basename(filePath)} is still ${(currentSize / 1024).toFixed(0)}KB after downscaling\n`,
    );
  } else {
    process.stdout.write(
      `Downscaled ${path.basename(filePath)} to ${(currentSize / 1024).toFixed(0)}KB\n`,
    );
  }
}

function ensureSipsAvailable() {
  try {
    execFileSync("sips", ["--help"], { stdio: "ignore" });
  } catch {
    throw new Error("sips is required to downscale screenshots during the build");
  }
}

function getImageMaxDimension(filePath) {
  const output = execFileSync("sips", ["-g", "pixelWidth", "-g", "pixelHeight", filePath], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  });
  const widthMatch = output.match(/pixelWidth:\s+(\d+)/);
  const heightMatch = output.match(/pixelHeight:\s+(\d+)/);

  if (!widthMatch || !heightMatch) {
    throw new Error(`Unable to read screenshot dimensions for ${filePath}`);
  }

  return Math.max(Number(widthMatch[1]), Number(heightMatch[1]));
}

function isResizableImage(fileName) {
  return /\.(png|jpe?g)$/i.test(fileName);
}
