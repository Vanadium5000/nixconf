import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { exec } from "child_process";
import { promisify } from "util";

const execAsync = promisify(exec);

const server = new McpServer({
  name: "qmllint-mcp",
  version: "1.0.0",
});

server.registerTool(
  "lint_qml",
  {
    description: "Lint a QML file using qmllint. Returns linting errors if any.",
    inputSchema: {
      filePath: z.string().describe("Path to a QML file to lint."),
    },
  },
  async ({ filePath }) => {
    try {
      try {
        const { stdout, stderr } = await execAsync(`qmllint -E "${filePath}" 2>&1`);
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

const transport = new StdioServerTransport();
await server.connect(transport);
