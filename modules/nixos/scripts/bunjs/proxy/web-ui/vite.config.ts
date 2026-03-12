import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import path from "path";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  root: __dirname,
  build: {
    outDir: "dist",
    emptyDirBeforeWrite: true,
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname),
    },
  },
});
