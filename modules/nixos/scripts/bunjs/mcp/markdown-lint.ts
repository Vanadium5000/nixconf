import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { exec } from "child_process";
import { promisify } from "util";

const execAsync = promisify(exec);

const server = new McpServer({
  name: "markdown-lint-mcp",
  version: "1.0.0",
});

server.tool(
  "lint_markdown",
  "Lint markdown content or a file. Returns linting errors if any.",
  {
    content: z.string().optional().describe("Markdown content to lint directly."),
    filePath: z.string().optional().describe("Path to a markdown file to lint."),
  },
  async ({ content, filePath }) => {
    if (!content && !filePath) {
      return {
        content: [
          {
            type: "text",
            text: "Error: Either 'content' or 'filePath' must be provided.",
          },
        ],
        isError: true,
      };
    }

    try {
      let command: string;
      
      if (filePath) {
        command = `markdownlint "${filePath}"`;
      } else {
        command = `echo "${content?.replace(/"/g, '\\"')}" | markdownlint --stdin`;
      }

      try {
        const { stdout, stderr } = await execAsync(command);
        return {
          content: [
            {
              type: "text",
              text: stdout || stderr || "No linting errors found.",
            },
          ],
        };
      } catch (error: any) {
        return {
          content: [
            {
              type: "text",
              text: error.stderr || error.stdout || error.message,
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
