import { access, cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const srcFile = path.join(projectRoot, "src", "index.html");
const srcAssets = path.join(projectRoot, "src", "assets");
const distDir = path.join(projectRoot, "dist");
const distFile = path.join(distDir, "index.html");
const distAssets = path.join(distDir, "assets");

const html = await readFile(srcFile, "utf8");

await rm(distDir, { recursive: true, force: true });
await mkdir(distDir, { recursive: true });
await writeFile(distFile, minifyHtml(html), "utf8");

if (await exists(srcAssets)) {
  await cp(srcAssets, distAssets, { recursive: true });
}

process.stdout.write("Built dist/index.html\n");

function minifyHtml(input) {
  return input
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/\n+/g, " ")
    .replace(/\s{2,}/g, " ")
    .replace(/>\s+</g, "><")
    .trim();
}

async function exists(targetPath) {
  try {
    await access(targetPath);
    return true;
  } catch {
    return false;
  }
}
