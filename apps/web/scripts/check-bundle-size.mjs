import { readdir, stat } from "node:fs/promises";
import { join } from "node:path";

const assetsDir = new URL("../dist/assets/", import.meta.url);
const maxChunkBytes = 500_000;

const files = await readdir(assetsDir);
const jsChunks = [];

for (const file of files) {
  if (!file.endsWith(".js")) continue;
  const path = join(assetsDir.pathname, file);
  const fileStat = await stat(path);
  jsChunks.push({ file, bytes: fileStat.size });
}

jsChunks.sort((left, right) => right.bytes - left.bytes);

const oversized = jsChunks.filter((chunk) => chunk.bytes > maxChunkBytes);
for (const chunk of jsChunks.slice(0, 8)) {
  console.log(`${chunk.file}: ${formatBytes(chunk.bytes)}`);
}

if (oversized.length > 0) {
  console.error(
    `\nBundle size check failed: ${oversized.length} JS chunk(s) exceed ${formatBytes(
      maxChunkBytes
    )}. Split the route or dependency before shipping.`
  );
  process.exit(1);
}

console.log(`\nBundle size check passed: all JS chunks are <= ${formatBytes(maxChunkBytes)}.`);

function formatBytes(bytes) {
  return `${(bytes / 1000).toFixed(1)} kB`;
}
