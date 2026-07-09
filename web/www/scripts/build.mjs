import { readFile, writeFile, cp, rm, mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const srcDir = path.join(projectRoot, "src");
const distDir = path.join(projectRoot, "dist");
const envFile = path.join(projectRoot, ".env");

const env = Object.fromEntries(
  (await readFile(envFile, "utf8"))
    .split("\n")
    .filter((line) => line.trim() && !line.trim().startsWith("#"))
    .map((line) => {
      const eq = line.indexOf("=");
      return [line.slice(0, eq).trim(), line.slice(eq + 1).trim().replace(/^"|"$/g, "")];
    }),
);

await rm(distDir, { recursive: true, force: true });
await cp(srcDir, distDir, { recursive: true });

for (const name of await readdirHtml(distDir)) {
  const filePath = path.join(distDir, name);
  let html = await readFile(filePath, "utf8");
  for (const [key, value] of Object.entries(env)) {
    html = html.replaceAll(`__${key}__`, escapeHtmlAttribute(value));
  }
  await writeFile(filePath, html, "utf8");
}

process.stdout.write("Built dist/\n");

function escapeHtmlAttribute(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

async function readdirHtml(dir) {
  const entries = await import("node:fs/promises").then((m) => m.readdir(dir));
  return entries.filter((name) => name.endsWith(".html"));
}
