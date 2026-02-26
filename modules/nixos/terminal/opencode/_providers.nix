{ self, ... }:

{
  config = {
    antigravity-gemini = {
      npm = "@ai-sdk/anthropic";
      name = "Antigravity Gemini";
      options = {
        baseURL = "http://127.0.0.1:8317/v1";
        apiKey = self.secrets.CLIPROXYAPI_KEY;
      };
      models = {
        "gemini-3.1-pro-high" = {
          name = "Gemini 3.1 Pro (High)";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
              "video"
              "audio"
            ];
            output = [ "text" ];
          };
        };

        "gemini-3.1-pro-low" = {
          name = "Gemini 3.1 Pro (Low)";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
              "video"
              "audio"
            ];
            output = [ "text" ];
          };
        };

        "gemini-3.1-pro-preview" = {
          name = "Gemini 3.1 Pro Preview";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
              "video"
              "audio"
            ];
            output = [ "text" ];
          };
        };

        "gemini-3-pro-high" = {
          name = "Gemini 3 Pro (High)";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
              "video"
              "audio"
            ];
            output = [ "text" ];
          };
        };

        "gemini-3-flash-preview" = {
          name = "Gemini 3 Flash Preview";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
              "video"
              "audio"
            ];
            output = [ "text" ];
          };
        };

        "gemini-3-flash" = {
          name = "Gemini 3 Flash";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
              "video"
              "audio"
            ];
            output = [ "text" ];
          };
        };

        "gemini-3.1-flash-image" = {
          name = "Gemini 3.1 Flash Image";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
              "video"
              "audio"
            ];
            output = [
              "text"
              "image"
            ];
          };
        };

        "gemini-3-pro-image" = {
          name = "Gemini 3 Pro Image";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
              "video"
              "audio"
            ];
            output = [
              "text"
              "image"
            ];
          };
        };

        "gemini-2.5-pro" = {
          name = "Gemini 2.5 Pro";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [ "text" ];
          };
        };

        "gemini-2.5-flash" = {
          name = "Gemini 2.5 Flash";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [ "text" ];
          };
        };

        "gemini-2.5-flash-lite" = {
          name = "Gemini 2.5 Flash Lite";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [ "text" ];
          };
        };

        "tab_jump_flash_lite_preview" = {
          name = "tab_jump_flash_lite_preview";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
              "video"
              "audio"
            ];
            output = [ "text" ];
          };
        };

        "tab_flash_lite_preview" = {
          name = "tab_flash_lite_preview";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
              "video"
              "audio"
            ];
            output = [ "text" ];
          };
        };

        "gpt-oss-120b-medium" = {
          name = "GPT-OSS 120B (Medium)";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [ "text" ];
          };
        };
      };
    };

    antigravity-claude = {
      npm = "@ai-sdk/anthropic";
      name = "Antigravity Claude";
      options = {
        baseURL = "http://127.0.0.1:8317/v1";
        apiKey = self.secrets.CLIPROXYAPI_KEY;
      };
      models = {
        "claude-sonnet-4-6" = {
          name = "Claude Sonnet 4.6 (Thinking)";
          limit = {
            context = 200000;
            output = 64000;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
              "video"
              "audio"
            ];
            output = [ "text" ];
          };
        };

        "claude-opus-4-6-thinking" = {
          name = "Claude Opus 4.6 (Thinking)";
          limit = {
            context = 1000000;
            output = 128000;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
              "video"
              "audio"
            ];
            output = [ "text" ];
          };
        };
      };
    };
  };
}
