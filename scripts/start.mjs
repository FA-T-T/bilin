import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const rootDir = dirname(dirname(fileURLToPath(import.meta.url)));
const args = process.argv.slice(2);

const command =
  process.platform === "win32"
    ? {
        file: "powershell",
        args: [
          "-NoProfile",
          "-ExecutionPolicy",
          "Bypass",
          "-File",
          join(rootDir, "scripts", "start.ps1"),
          ...args
        ]
      }
    : {
        file: join(rootDir, "scripts", "start-dev.sh"),
        args
      };

const child = spawn(command.file, command.args, {
  cwd: rootDir,
  stdio: "inherit",
  shell: false
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 0);
});
