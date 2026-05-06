import react from "@vitejs/plugin-react";

export default {
  plugins: [react()],
  build: {
    rollupOptions: {
      output: {
        // Keep route code and heavy reader libraries out of the startup chunk.
        manualChunks: {
          "vendor-react": ["react", "react-dom", "react-router-dom"],
          "vendor-mantine": ["@mantine/core", "@mantine/hooks"],
          "vendor-state": ["@tanstack/react-query", "zustand"],
          "reader-rendering": ["katex", "react-markdown"]
        }
      }
    }
  },
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
