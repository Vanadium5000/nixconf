{ self }:
{
  config = {
    antigravity-gemini = {
      npm = "@ai-sdk/anthropic";
      name = "Antigravity Gemini";
      options = {
        baseURL = "http://127.0.0.1:8045/v1";
        apiKey = self.secrets.ANTIGRAVITY_MANAGER_KEY;
      };
      models = {
        gemini-3-pro-high = {
          name = "Gemini 3 Pro High";
          limit = {
            context = 128000;
            output = 8192;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
            ];
          };
        };
        gemini-3-pro-low = {
          name = "Gemini 3 Pro Low";
          limit = {
            context = 128000;
            output = 8192;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
            ];
          };
        };
        gemini-3-pro-preview = {
          name = "Gemini 3 Pro Preview";
          limit = {
            context = 128000;
            output = 8192;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
            ];
          };
        };
        gemini-3-flash = {
          name = "Gemini 3 Flash";
          limit = {
            context = 128000;
            output = 8192;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
            ];
          };
        };
        "gemini-2.5-flash" = {
          name = "Gemini 2.5 Flash";
          limit = {
            context = 128000;
            output = 8192;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
            ];
          };
        };
        "gemini-2.5-flash-lite" = {
          name = "Gemini 2.5 Flash Lite";
          limit = {
            context = 128000;
            output = 8192;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
            ];
          };
        };
        "gemini-2.5-flash-thinking" = {
          name = "Gemini 2.5 Flash Thinking";
          limit = {
            context = 128000;
            output = 8192;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
            ];
          };
        };
        "gemini-3-pro-image" = {
          name = "Gemini 3 Pro Image";
          limit = {
            context = 128000;
            output = 8192;
          };
          modalities = {
            input = [
              "text"
              "image"
            ];
            output = [
              "text"
              "image"
            ];
          };
        };
      };
    };
    antigravity-claude = {
      npm = "@ai-sdk/anthropic";
      name = "Antigravity Claude";
      options = {
        baseURL = "http://127.0.0.1:8045/v1";
        apiKey = self.secrets.ANTIGRAVITY_MANAGER_KEY;
      };
      models = {
        claude-sonnet-4-5 = {
          name = "Claude Sonnet 4.5";
          limit = {
            context = 128000;
            output = 8192;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
            ];
          };
        };
        claude-sonnet-4-5-thinking = {
          name = "Claude Sonnet 4.5 Thinking";
          limit = {
            context = 128000;
            output = 8192;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
            ];
          };
        };
        claude-opus-4-5-thinking = {
          name = "Claude Opus 4.5 Thinking";
          limit = {
            context = 128000;
            output = 8192;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
            ];
          };
        };
      };
    };
  };
}
