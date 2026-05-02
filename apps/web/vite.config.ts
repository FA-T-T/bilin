import react from "@vitejs/plugin-react";

export default {
  plugins: [react()],
  server: {
    port: 5173,
    host: "127.0.0.1"
  },
  test: {
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
    exclude: ["node_modules", "dist", "e2e"]
  }
};
