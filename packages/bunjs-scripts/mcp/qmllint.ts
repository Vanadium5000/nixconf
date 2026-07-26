import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { exec } from "child_process";
import { promisify } from "util";
import { readdir, stat } from "fs/promises";
import { join, relative } from "path";

const execAsync = promisify(exec);

const server = new McpServer({
  name: "qmllint-mcp",
  version: "1.0.0",
});

interface LintResult {
  file: string;
  success: boolean;
  output: string;
}

interface DirectoryLintSummary {
  totalFiles: number;
  filesWithErrors: number;
  filesClean: number;
  filesFailed: number; // internal errors (permission, etc.)
  results: LintResult[];
}

/**
 * Recursively find all files matching a pattern in a directory.
 * Returns absolute paths.
 */
async function findFilesRecursive(
  dir: string,
  extension: string,
  maxDepth: number = 50,
  currentDepth: number = 0
): Promise<string[]> {
  if (currentDepth > maxDepth) return [];

  const files: string[] = [];

  try {
    const entries = await readdir(dir, { withFileTypes: true });

    for (const entry of entries) {
      const fullPath = join(dir, entry.name);

      // Skip hidden directories and common non-source dirs
      if (entry.name.startsWith(".") || entry.name === "node_modules") {
        continue;
      }

      if (entry.isDirectory()) {
        const subFiles = await findFilesRecursive(
          fullPath,
          extension,
          maxDepth,
          currentDepth + 1
        );
        files.push(...subFiles);
      } else if (entry.isFile() && entry.name.endsWith(extension)) {
        files.push(fullPath);
      }
    }
  } catch (err: any) {
    // Permission denied or other read errors - skip silently
    console.error(`Skipping directory ${dir}: ${err.message}`);
  }

  return files;
}

/**
 * Lint a single QML file, returning structured result.
 */
async function lintQmlFile(filePath: string): Promise<LintResult> {
  try {
    const { stdout, stderr } = await execAsync(
      `qmllint -E "${filePath}" 2>&1`
    );
    // qmllint -E outputs nothing on success
    const output = stdout || stderr || "";
    return {
      file: filePath,
      success: output.trim() === "",
      output: output.trim() || "No linting errors found.",
    };
  } catch (error: any) {
    // qmllint returns non-zero exit code on errors
    const output = error.stdout || error.stderr || error.message;
    return {
      file: filePath,
      success: false,
      output: output.trim(),
    };
  }
}

/**
 * Format directory lint results into a readable report.
 */
function formatDirectoryReport(
  baseDir: string,
  summary: DirectoryLintSummary
): string {
  const lines: string[] = [];

  lines.push(`# QML Lint Report: ${baseDir}`);
  lines.push("");
  lines.push("## Summary");
  lines.push(`- Total files scanned: ${summary.totalFiles}`);
  lines.push(`- Files with errors: ${summary.filesWithErrors}`);
  lines.push(`- Files clean: ${summary.filesClean}`);
  if (summary.filesFailed > 0) {
    lines.push(`- Files failed to lint: ${summary.filesFailed}`);
  }
  lines.push("");

  if (summary.filesWithErrors === 0 && summary.filesFailed === 0) {
    lines.push("✅ All files passed linting.");
    return lines.join("\n");
  }

    const errorResults = summary.results.filter((r) => !r.success);
  if (errorResults.length > 0) {
    lines.push("## Errors");
    lines.push("");

    for (const result of errorResults) {
      const relPath = relative(baseDir, result.file) || result.file;
      lines.push(`### ${relPath}`);
      lines.push("```");
      lines.push(result.output);
      lines.push("```");
      lines.push("");
    }
  }

  return lines.join("\n");
}

server.registerTool(
  "lint_qml",
  {
    description:
      "Lint a QML file using qmllint. Returns linting errors if any.",
    inputSchema: {
      filePath: z.string().describe("Path to a QML file to lint."),
    },
  },
  async ({ filePath }) => {
    try {
      try {
        const { stdout, stderr } = await execAsync(
          `qmllint -E "${filePath}" 2>&1`
        );
        // qmllint -E outputs nothing on success
        return {
          content: [
            {
              type: "text",
              text: stdout || stderr || "No linting errors found.",
            },
          ],
        };
      } catch (error: any) {
        // qmllint returns non-zero exit code on errors
        return {
          content: [
            {
              type: "text",
              text: error.stdout || error.stderr || error.message,
            },
          ],
          isError: true,
        };
      }
    } catch (err: any) {
      return {
        content: [
          {
            type: "text",
            text: `Internal error: ${err.message}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "lint_qml_directory",
  {
    description:
      "Recursively lint all QML files in a directory. Returns aggregated results with per-file errors and summary statistics.",
    inputSchema: {
      directoryPath: z
        .string()
        .describe("Path to directory to recursively scan for .qml files."),
      maxDepth: z
        .number()
        .optional()
        .describe("Maximum recursion depth (default: 50)."),
    },
  },
  async ({ directoryPath, maxDepth }) => {
    try {
      const dirStat = await stat(directoryPath).catch(() => null);
      if (!dirStat || !dirStat.isDirectory()) {
        return {
          content: [
            {
              type: "text",
              text: `Error: "${directoryPath}" is not a valid directory.`,
            },
          ],
          isError: true,
        };
      }

      const qmlFiles = await findFilesRecursive(
        directoryPath,
        ".qml",
        maxDepth ?? 50
      );

      if (qmlFiles.length === 0) {
        return {
          content: [
            {
              type: "text",
              text: `No .qml files found in "${directoryPath}".`,
            },
          ],
        };
      }

      const BATCH_SIZE = 10; // concurrent lint processes
      const results: LintResult[] = [];

      for (let i = 0; i < qmlFiles.length; i += BATCH_SIZE) {
        const batch = qmlFiles.slice(i, i + BATCH_SIZE);
        const batchResults = await Promise.all(batch.map(lintQmlFile));
        results.push(...batchResults);
      }

      const summary: DirectoryLintSummary = {
        totalFiles: results.length,
        filesWithErrors: results.filter((r) => !r.success).length,
        filesClean: results.filter((r) => r.success).length,
        filesFailed: 0, // internal errors tracked separately if needed
        results,
      };

      const report = formatDirectoryReport(directoryPath, summary);

      return {
        content: [
          {
            type: "text",
            text: report,
          },
        ],
        isError: summary.filesWithErrors > 0,
      };
    } catch (err: any) {
      return {
        content: [
          {
            type: "text",
            text: `Internal error: ${err.message}`,
          },
        ],
        isError: true,
      };
    }
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
