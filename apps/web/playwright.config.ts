import { defineConfig, devices } from "@playwright/test";

const webPort = process.env.BILIN_WEB_PORT ?? "4173";
const baseURL = `http://127.0.0.1:${webPort}`;
const apiBaseURL = "http://127.0.0.1:8000";

export default defineConfig({
  testDir: "./e2e",
  timeout: 30_000,
  use: {
    baseURL,
    trace: "on-first-retry"
  },
  webServer: {
    command: "pnpm dev",
    url: baseURL,
    env: {
      BILIN_DEV_HOST: "127.0.0.1",
      BILIN_WEB_HOST: "127.0.0.1",
      BILIN_WEB_PORT: webPort,
      VITE_BILIN_API_URL: apiBaseURL
    },
    reuseExistingServer: true
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] }
    }
  ]
});
