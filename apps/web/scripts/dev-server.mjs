import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { fileURLToPath } from "node:url";

const host = process.env.BILIN_DEV_HOST ?? process.env.BILIN_WEB_HOST ?? "127.0.0.1";
const cli = parseCliArgs(process.argv.slice(2));
const requestedHost = cli.host ?? host;
const requestedPort = parsePort(cli.port ?? process.env.BILIN_WEB_PORT ?? process.env.PORT, 5173);
const explicitPort = Boolean(process.env.BILIN_WEB_PORT ?? process.env.PORT);
const viteBin = fileURLToPath(new URL("../node_modules/vite/bin/vite.js", import.meta.url));

const port = explicitPort
  ? await assertPortAvailable(requestedPort)
  : await findAvailablePort(requestedPort);

const child = spawn(
  process.execPath,
  [viteBin, "--host", requestedHost, "--port", String(port), "--clearScreen", "false", ...cli.rest],
  {
    stdio: "inherit",
    env: {
      ...process.env,
      BILIN_WEB_PORT: String(port)
    }
  }
);

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 0);
});

function parsePort(value, fallback) {
  const parsed = Number(value);
  if (Number.isInteger(parsed) && parsed > 0 && parsed < 65536) return parsed;
  return fallback;
}

function parseCliArgs(args) {
  const parsed = { rest: [] };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--host") {
      parsed.host = args[index + 1];
      index += 1;
      continue;
    }
    if (arg.startsWith("--host=")) {
      parsed.host = arg.slice("--host=".length);
      continue;
    }
    if (arg === "--port") {
      parsed.port = args[index + 1];
      index += 1;
      continue;
    }
    if (arg.startsWith("--port=")) {
      parsed.port = arg.slice("--port=".length);
      continue;
    }
    parsed.rest.push(arg);
  }
  return parsed;
}

async function assertPortAvailable(port) {
  const result = await canListen(port);
  if (result.ok) return port;
  throw new Error(
    `BILIN_WEB_PORT=${port} is not available on ${requestedHost}: ${result.code ?? "unknown error"}`
  );
}

async function findAvailablePort(preferredPort) {
  const candidates = unique([
    preferredPort,
    4173,
    6173,
    7173,
    8173,
    9173,
    10173,
    12173,
    15173
  ]);
  for (const candidate of candidates) {
    const result = await canListen(candidate);
    if (result.ok) {
      if (candidate !== preferredPort) {
        console.warn(
          `Port ${preferredPort} is not available on ${requestedHost}; starting Bilin web on ${candidate}.`
        );
      }
      return candidate;
    }
  }
  throw new Error(
    `No usable local web port found for ${requestedHost}. Tried: ${candidates.join(", ")}`
  );
}

function canListen(port) {
  return new Promise((resolve) => {
    const server = createServer();
    server.once("error", (error) => {
      resolve({ ok: false, code: error?.code });
    });
    server.listen(port, requestedHost, () => {
      server.close(() => resolve({ ok: true }));
    });
  });
}

function unique(values) {
  return [...new Set(values)];
}
