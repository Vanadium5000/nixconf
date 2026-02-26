import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { writeFileSync } from "fs";
import { join } from "path";

const server = new McpServer({
  name: "image-gen-mcp",
  version: "1.0.0",
});

server.registerTool(
  "generate_image",
  {
    description:
      "Generate an image from a prompt and save it to a file. Use concise prompts for best results.",
    inputSchema: {
      prompt: z.string().describe("The description of the image to generate."),
      outputPath: z
        .string()
        .describe(
          "The absolute path where the image should be saved (e.g., /home/matrix/Downloads/image.png).",
        ),
      model: z
        .string()
        .describe("The model to use for generation (passed by the system)."),
    },
  },
  async ({ prompt, outputPath, model }) => {
    try {
      const apiKey = process.env.CLIPROXYAPI_KEY;
      if (!apiKey) {
        throw new Error("CLIPROXYAPI_KEY environment variable is not set.");
      }

      const targetModel = model || process.env.IMAGE_MODEL;
      if (!targetModel) {
        throw new Error(
          "No image model specified and IMAGE_MODEL env var is not set.",
        );
      }

      // We use the same proxy OpenCode uses
      const response = await fetch(
        "http://127.0.0.1:8317/v1/images/generations",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${apiKey}`,
          },
          body: JSON.stringify({
            prompt,
            model: targetModel.split("/").pop(), // Extract model ID from provider/model format
            n: 1,
            size: "1024x1024",
            response_format: "b64_json",
          }),
        },
      );

      if (!response.ok) {
        const error = await response.text();
        throw new Error(`API error: ${response.status} ${error}`);
      }

      const data: any = await response.json();
      const b64Data = data.data[0].b64_json;
      const buffer = Buffer.from(b64Data, "base64");

      writeFileSync(outputPath, buffer);

      return {
        content: [
          {
            type: "text",
            text: `Image successfully generated and saved to ${outputPath}`,
          },
        ],
      };
    } catch (err: any) {
      return {
        content: [
          {
            type: "text",
            text: `Failed to generate image: ${err.message}`,
          },
        ],
        isError: true,
      };
    }
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
