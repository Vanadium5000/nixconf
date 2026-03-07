{ self, ... }:

# Configure API providers and their respective models
# Each provider defines its endpoint, authentication, and the models it exposes
{
  config = {
    # Antigravity Gemini Provider
    # Handles access to Gemini models via local proxy
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
            output = 65535;
          };
          modalities = {
            input = [
              "text"
              "image"
              "video"
            ];
            output = [ "text" ];
          };
        };

        "gemini-3.1-pro-low" = {
          name = "Gemini 3.1 Pro (Low)";
          limit = {
            context = 1048576;
            output = 65535;
          };
          modalities = {
            input = [
              "text"
              "image"
              "video"
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
            input = [ "text" ];
            output = [ "text" ];
          };
        };

        "gemini-3-pro-high" = {
          name = "Gemini 3 Pro (High)";
          limit = {
            context = 1048576;
            output = 65535;
          };
          modalities = {
            input = [
              "text"
              "image"
              "video"
            ];
            output = [ "text" ];
          };
        };

        "gemini-3-pro-low" = {
          name = "Gemini 3 Pro (Low)";
          limit = {
            context = 1048576;
            output = 65535;
          };
          modalities = {
            input = [
              "text"
              "image"
              "video"
            ];
            output = [ "text" ];
          };
        };

        "gemini-3-pro-preview" = {
          name = "Gemini 3 Pro Preview";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [ "text" ];
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
              "video"
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
            input = [ "text" ];
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
            input = [ "text" ];
            output = [ "text" ];
          };
        };

        "gemini-3.1-flash-lite-preview" = {
          name = "Gemini 3.1 Flash Lite Preview";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [ "text" ];
            output = [ "text" ];
          };
        };

        "gemini-2.5-pro" = {
          name = "Gemini 2.5 Pro";
          limit = {
            context = 1048576;
            output = 65536;
          };
          modalities = {
            input = [ "text" ];
            output = [ "text" ];
          };
        };

        "gemini-2.5-flash" = {
          name = "Gemini 2.5 Flash";
          limit = {
            context = 1048576;
            output = 65535;
          };
          modalities = {
            input = [
              "text"
              "image"
            ];
            output = [ "text" ];
          };
        };

        "gemini-2.5-flash-lite" = {
          name = "Gemini 2.5 Flash Lite";
          limit = {
            context = 1048576;
            output = 65535;
          };
          modalities = {
            input = [ "text" ];
            output = [ "text" ];
          };
        };

        "gpt-oss-120b-medium" = {
          name = "GPT-OSS 120B (Medium)";
          limit = {
            context = 114000;
            output = 32768;
          };
          modalities = {
            input = [ "text" ];
            output = [ "text" ];
          };
        };
      };
    };

    # Antigravity Claude Provider
    # Handles access to Claude models via local proxy
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
            ];
            output = [ "text" ];
          };
        };

        "claude-opus-4-6-thinking" = {
          name = "Claude Opus 4.6 (Thinking)";
          limit = {
            context = 200000;
            output = 64000;
          };
          modalities = {
            input = [
              "text"
              "image"
            ];
            output = [ "text" ];
          };
        };
      };
    };

    # Kilo Code Provider
    # Handles access to various free/community models via local proxy
    kilo-code = {
      npm = "@ai-sdk/anthropic";
      name = "Kilo Code";
      options = {
        baseURL = "http://127.0.0.1:8317/v1";
        apiKey = self.secrets.CLIPROXYAPI_KEY;
      };
      models = {
        "minimax/minimax-m2.5:free" = {
          name = "MiniMax M2.5 (Free)";
          limit = {
            context = 196608;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
            ];
            output = [ "text" ];
          };
        };

        "moonshotai/kimi-k2.5:free" = {
          name = "Kimi K2.5 (Free)";
          limit = {
            context = 262144;
            output = 33000;
          };
          modalities = {
            input = [
              "text"
              "image"
              "video"
            ];
            output = [ "text" ];
          };
        };

        "arcee-ai/trinity-large-preview:free" = {
          name = "Arcee Trinity Large Preview (Free)";
          limit = {
            context = 131072;
            output = 32768;
          };
          modalities = {
            input = [ "text" ];
            output = [ "text" ];
          };
        };
      };
    };
  };
}
