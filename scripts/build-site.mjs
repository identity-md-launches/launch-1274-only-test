#!/usr/bin/env node
// Packaging only: source is directly runnable without compilation or dependencies.
import { cp, mkdir, readdir, readFile, rm, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
const root = fileURLToPath(new URL("../", import.meta.url));
const source = path.join(root, "site");
const destination = path.join(root, "dist");
const allowed = new Set([
  ".html",
  ".css",
  ".js",
  ".webp",
  ".svg",
  ".woff2",
  ".txt",
]);
async function check(directory) {
  for (const item of await readdir(directory, { withFileTypes: true })) {
    if (item.isSymbolicLink()) throw new Error("No symlinks in site assets");
    const file = path.join(directory, item.name);
    if (item.isDirectory()) {
      if (["node_modules", ".cache", ".git"].includes(item.name))
        throw new Error("Unexpected dependency directory");
      await check(file);
    } else if (!allowed.has(path.extname(file)))
      throw new Error(`Unexpected production file: ${file}`);
  }
}
await check(source);
await rm(destination, { recursive: true, force: true });
await mkdir(destination, { recursive: true });
await cp(source, destination, { recursive: true });
let bytes = 0,
  count = 0;
async function measure(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) await measure(file);
    else {
      bytes += (await stat(file)).size;
      count++;
    }
  }
}
await measure(destination);
const html = await readFile(path.join(destination, "index.html"), "utf8");
for (const marker of [
  "<title>",
  'name="description"',
  'property="og:title"',
  'property="og:image"',
  'rel="icon"',
])
  if (!html.includes(marker)) throw new Error(`Missing metadata: ${marker}`);
console.log(
  `PASS: copied ${count} production files (${bytes} bytes), with metadata. No compilation or runtime dependencies.`,
);
