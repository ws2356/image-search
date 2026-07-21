import { createHash } from "node:crypto";
import { readFile, writeFile, readdir, rename, cp, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const srcDir = path.join(projectRoot, "src");
const distDir = path.join(projectRoot, "dist");
const envFile = path.join(projectRoot, ".env");
const assetsDir = path.join(distDir, "assets");

const IMAGE_EXTS = new Set([".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"]);

const env = Object.fromEntries(
  (await readFile(envFile, "utf8"))
    .split("\n")
    .filter((line) => line.trim() && !line.trim().startsWith("#"))
    .map((line) => {
      const eq = line.indexOf("=");
      const name = line.slice(0, eq).trim();
      const value = line.slice(eq + 1)
        .replace(/^(['"])(.*)\1$/, "$2")
        .trim();
      return [name, value];
    }),
);

await rm(distDir, { recursive: true, force: true });
await cp(srcDir, distDir, { recursive: true });

const renameMap = await hashAndRenameAssets(assetsDir);

for (const entry of await readdir(distDir)) {
  if (!entry.endsWith(".html")) continue;

  const filePath = path.join(distDir, entry);
  let html = await readFile(filePath, "utf8");

  for (const [key, value] of Object.entries(env)) {
    html = html.replaceAll(`__${key}__`, escapeHtmlAttribute(value));
  }

  for (const [original, hashed] of renameMap) {
    html = html.replaceAll(`assets/${original}`, `assets/${hashed}`);
  }

  await writeFile(filePath, html, "utf8");
}

process.stdout.write("Built dist/\n");

async function hashAndRenameAssets(dir) {
  const map = new Map();
  const entries = await readdir(dir);

  for (const name of entries) {
    const ext = path.extname(name).toLowerCase();
    if (!IMAGE_EXTS.has(ext)) continue;

    const filePath = path.join(dir, name);
    const buffer = await readFile(filePath);
    const md5 = createHash("md5").update(buffer).digest("hex").slice(0, 8);
    const base = path.basename(name, ext);
    const hashed = `${base}-${md5}${ext}`;

    await rename(filePath, path.join(dir, hashed));
    map.set(name, hashed);
  }

  return map;
}

function escapeHtmlAttribute(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}
