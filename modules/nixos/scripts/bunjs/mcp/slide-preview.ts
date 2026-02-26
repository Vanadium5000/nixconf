import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { exec } from "child_process";
import { promisify } from "util";
import { readdir, mkdir } from "fs/promises";
import { join, basename, extname } from "path";

const execAsync = promisify(exec);

const server = new McpServer({
  name: "slide-preview-mcp",
  version: "1.0.0",
});

server.registerTool(
  "preview_slides",
  {
    description:
      "Convert a presentation file (PPTX, ODP, etc.) to a series of PNG images for previewing.",
    inputSchema: {
      filePath: z
        .string()
        .describe("The absolute path to the presentation file."),
      outputDir: z
        .string()
        .describe(
          "The absolute path to a directory where preview images should be saved.",
        ),
    },
  },
  async ({ filePath, outputDir }) => {
    try {
      // Ensure output directory exists
      await mkdir(outputDir, { recursive: true });

      // Use libreoffice (soffice) to convert slides to PNG
      // --headless: No UI
      // --convert-to png: Target format
      // --outdir: Where to put the results
      const command = `soffice --headless --convert-to png --outdir "${outputDir}" "${filePath}"`;

      const { stdout, stderr } = await execAsync(command);

      // List the generated files
      const files = await readdir(outputDir);
      const fileNameNoExt = basename(filePath, extname(filePath));
      const previewImages = files
        .filter((f) => f.startsWith(fileNameNoExt) && f.endsWith(".png"))
        .map((f) => join(outputDir, f))
        .sort();

      if (previewImages.length === 0) {
        throw new Error(
          `No preview images generated. Output: ${stdout} ${stderr}`,
        );
      }

      return {
        content: [
          {
            type: "text",
            text: `Successfully generated ${previewImages.length} preview images in ${outputDir}.\n\nFiles:\n${previewImages.join("\n")}`,
          },
        ],
      };
    } catch (err: any) {
      return {
        content: [
          {
            type: "text",
            text: `Failed to preview slides: ${err.message}`,
          },
        ],
        isError: true,
      };
    }
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
