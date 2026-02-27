import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readdir, mkdir, rm, stat, readFile } from "fs/promises";
import { join, basename, extname } from "path";
import { tmpdir } from "os";

const SUPPORTED_EXTENSIONS = new Set([".pptx", ".ppt", ".odp", ".key", ".pdf"]);

async function fileExists(path: string): Promise<boolean> {
  try {
    await stat(path);
    return true;
  } catch {
    return false;
  }
}

async function runCommand(command: string[]): Promise<string> {
  const proc = Bun.spawn(command, {
    stdout: "pipe",
    stderr: "pipe",
  });

  const exitCode = await proc.exited;
  const stderr = await new Response(proc.stderr).text();

  if (exitCode !== 0) {
    throw new Error(
      `Command failed (exit ${exitCode}): ${command.join(" ")}\n${stderr}`,
    );
  }

  return await new Response(proc.stdout).text();
}

/**
 * Convert a presentation to per-slide PNG images.
 *
 * Two-step pipeline:
 * 1. LibreOffice converts the presentation to PDF (handles all slide formats)
 * 2. pdftocairo renders each PDF page as a separate PNG
 *
 * LibreOffice's direct PNG export only produces the first slide,
 * so the PDF intermediate step is necessary for multi-slide support.
 */
async function convertSlidesToPng(
  filePath: string,
  workDir: string,
): Promise<string[]> {
  const fileNameNoExt = basename(filePath, extname(filePath));
  const ext = extname(filePath).toLowerCase();

  // PDFs skip the LibreOffice step
  let pdfPath: string;
  if (ext === ".pdf") {
    pdfPath = filePath;
  } else {
    await runCommand([
      "soffice",
      "--headless",
      "--convert-to",
      "pdf",
      "--outdir",
      workDir,
      filePath,
    ]);

    pdfPath = join(workDir, `${fileNameNoExt}.pdf`);

    if (!(await fileExists(pdfPath))) {
      throw new Error("LibreOffice failed to produce a PDF");
    }
  }

  // pdftocairo renders each page as a numbered PNG (slide-1.png, slide-2.png, ...)
  const outputPrefix = join(workDir, "slide");
  await runCommand([
    "pdftocairo",
    "-png",
    "-r",
    "150", // 150 DPI — good balance of quality vs file size for preview
    pdfPath,
    outputPrefix,
  ]);

  const files = await readdir(workDir);
  const slideImages = files
    .filter((f) => f.startsWith("slide-") && f.endsWith(".png"))
    .sort() // Lexicographic sort works because pdftocairo zero-pads numbers
    .map((f) => join(workDir, f));

  if (slideImages.length === 0) {
    throw new Error("pdftocairo produced no PNG output from the PDF");
  }

  return slideImages;
}

const server = new McpServer({
  name: "slide-preview-mcp",
  version: "2.0.0",
});

server.registerTool(
  "preview_slides",
  {
    description: [
      "Convert a presentation file (PPTX, ODP, PDF, etc.) to per-slide PNG images.",
      "Returns inline base64 images by default so you can view them directly.",
      "Set saveToDir to persist the PNGs to a specific directory instead.",
    ].join(" "),
    inputSchema: {
      filePath: z.string().describe("Absolute path to the presentation file."),
      saveToDir: z
        .string()
        .optional()
        .describe(
          "If provided, save PNG files to this directory and return file paths instead of inline images.",
        ),
    },
  },
  async ({ filePath, saveToDir }) => {
    try {
      if (!(await fileExists(filePath))) {
        throw new Error(`File not found: ${filePath}`);
      }

      const ext = extname(filePath).toLowerCase();
      if (!SUPPORTED_EXTENSIONS.has(ext)) {
        throw new Error(
          `Unsupported format "${ext}". Supported: ${[...SUPPORTED_EXTENSIONS].join(", ")}`,
        );
      }

      // When saving, convert directly into the target directory.
      // Otherwise, use a temp directory that gets cleaned up after.
      const outputDir =
        saveToDir ?? join(tmpdir(), `slide-preview-${Date.now()}`);
      await mkdir(outputDir, { recursive: true });

      try {
        const slideImages = await convertSlidesToPng(filePath, outputDir);

        if (saveToDir) {
          // Persistent mode: return file paths
          return {
            content: [
              {
                type: "text" as const,
                text: `Generated ${slideImages.length} slide previews in ${saveToDir}:\n${slideImages.join("\n")}`,
              },
            ],
          };
        }

        // Inline mode: return base64-encoded images directly
        const imageContent = await Promise.all(
          slideImages.map(async (imgPath, index) => ({
            type: "image" as const,
            data: (await readFile(imgPath)).toString("base64"),
            mimeType: "image/png" as const,
          })),
        );

        return {
          content: [
            {
              type: "text" as const,
              text: `Preview of ${slideImages.length} slide(s) from ${basename(filePath)}:`,
            },
            ...imageContent,
          ],
        };
      } finally {
        // Clean up temp directory when not saving
        if (!saveToDir) {
          await rm(outputDir, { recursive: true, force: true });
        }
      }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      return {
        content: [{ type: "text" as const, text: `Failed: ${message}` }],
        isError: true,
      };
    }
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
