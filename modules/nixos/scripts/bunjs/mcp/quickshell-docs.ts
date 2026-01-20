import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readdir, readFile, stat } from "fs/promises";
import { join, relative, resolve } from "path";

// The path to the docs is provided via environment variable
const DOCS_PATH = process.env.QUICKSHELL_DOCS_PATH;

if (!DOCS_PATH) {
  console.error("Error: QUICKSHELL_DOCS_PATH environment variable is not set.");
  process.exit(1);
}

const server = new McpServer({
  name: "quickshell-docs",
  version: "1.0.0",
});

// Helper to recursively get all markdown files
async function getMarkdownFiles(dir: string): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = await Promise.all(
    entries.map(async (entry) => {
      const res = resolve(dir, entry.name);
      if (entry.isDirectory()) {
        return getMarkdownFiles(res);
      } else {
        return res;
      }
    })
  );
  return Array.prototype.concat(...files).filter((f) => f.endsWith(".md"));
}

server.tool(
  "list_docs",
  "List all available Quickshell documentation files.",
  {},
  async () => {
    try {
      const files = await getMarkdownFiles(DOCS_PATH!);
      const relativeFiles = files.map((f) => relative(DOCS_PATH!, f));
      
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(relativeFiles, null, 2),
          },
        ],
      };
    } catch (error: any) {
      return {
        content: [{ type: "text", text: `Error listing files: ${error.message}` }],
        isError: true,
      };
    }
  }
);

server.tool(
  "read_doc",
  "Read the content of a specific Quickshell documentation file.",
  {
    path: z.string().describe("The relative path of the file to read (e.g., 'docs/configuration/intro.md')."),
  },
  async ({ path }) => {
    try {
      // Security check to prevent path traversal
      const fullPath = resolve(DOCS_PATH!, path);
      if (!fullPath.startsWith(resolve(DOCS_PATH!))) {
        throw new Error("Invalid path: Access denied.");
      }

      const content = await readFile(fullPath, "utf-8");
      return {
        content: [
          {
            type: "text",
            text: content,
          },
        ],
      };
    } catch (error: any) {
      return {
        content: [{ type: "text", text: `Error reading file: ${error.message}` }],
        isError: true,
      };
    }
  }
);

server.tool(
  "search_docs",
  "Search for a string in all Quickshell documentation files.",
  {
    query: z.string().describe("The string to search for."),
  },
  async ({ query }) => {
    try {
      const files = await getMarkdownFiles(DOCS_PATH!);
      const results: string[] = [];

      for (const file of files) {
        const content = await readFile(file, "utf-8");
        if (content.toLowerCase().includes(query.toLowerCase())) {
          results.push(relative(DOCS_PATH!, file));
        }
      }

      if (results.length === 0) {
        return {
            content: [{ type: "text", text: "No matches found." }],
        };
      }

      return {
        content: [
          {
            type: "text",
            text: `Found matches in:\n${results.join("\n")}`,
          },
        ],
      };
    } catch (error: any) {
      return {
        content: [{ type: "text", text: `Error searching docs: ${error.message}` }],
        isError: true,
      };
    }
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
