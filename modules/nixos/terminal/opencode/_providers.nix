{ ... }:

{
  config = {
    antigravity-gemini = {
      npm = "@ai-sdk/openai-compatible";
      name = "Antigravity Gemini";
      options = {
        baseURL = "http://127.0.0.1:8317/v1";
      };
      models = {
        "gemini-3.1-pro-high" = {
          name = "Gemini 3.1 Pro High";
          limit = {
            context = 2097152;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
              "image"
            ];
          };
          reasoning = true;
          variants = {
            high = {
              thinkingLevel = "high";
            };
          };
        };

        "gemini-3.1-pro-low" = {
          name = "Gemini 3.1 Pro Low";
          limit = {
            context = 2097152;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
              "image"
            ];
          };
          reasoning = true;
          variants = {
            low = {
              thinkingLevel = "low";
            };
          };
        };

        "gemini-3-pro-high" = {
          name = "Gemini 3 Pro High";
          limit = {
            context = 2097152;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
              "image"
            ];
          };
          reasoning = true;
          variants = {
            high = {
              thinkingLevel = "high";
            };
          };
        };

        "gemini-3-pro-preview" = {
          name = "Gemini 3 Pro Preview";
          limit = {
            context = 2097152;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [
              "text"
              "image"
            ];
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
            ];
            output = [
              "text"
            ];
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
            ];
            output = [ "text" ];
          };
          reasoning = true;
          variants = {
            minimal = {
              thinkingLevel = "minimal";
            };
            low = {
              thinkingLevel = "low";
            };
            medium = {
              thinkingLevel = "medium";
            };
            high = {
              thinkingLevel = "high";
            };
          };
        };

        "gemini-3-pro-image" = {
          name = "Gemini 3 Pro Image";
          limit = {
            context = 2097152;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
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
            context = 2097152;
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
            context = 1048576;
            output = 8192;
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
            output = 8192;
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
          name = "Tab Jump Flash Lite Preview";
          limit = {
            context = 1048576;
            output = 8192;
          };
          modalities = {
            input = [ "text" ];
            output = [ "text" ];
          };
        };

        "tab_flash_lite_preview" = {
          name = "Tab Flash Lite Preview";
          limit = {
            context = 1048576;
            output = 8192;
          };
          modalities = {
            input = [ "text" ];
            output = [ "text" ];
          };
        };
      };
    };

    antigravity-claude = {
      npm = "@ai-sdk/anthropic";
      name = "Antigravity Claude";
      options = {
        baseURL = "http://127.0.0.1:8317/compatible";
      };
      models = {
        "claude-sonnet-4-6" = {
          name = "Claude Sonnet 4.6";
          limit = {
            context = 200000;
            output = 64000;
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

        "claude-opus-4-6-thinking" = {
          name = "Claude Opus 4.6 Thinking";
          limit = {
            context = 200000;
            output = 64000;
          };
          modalities = {
            input = [
              "text"
              "image"
              "pdf"
            ];
            output = [ "text" ];
          };
          reasoning = true;
          variants = {
            low = {
              thinkingConfig = {
                thinkingBudget = 8192;
              };
              thinking = {
                type = "enabled";
                budget_tokens = 8192;
              };
            };
            medium = {
              thinkingConfig = {
                thinkingBudget = 16384;
              };
              thinking = {
                type = "enabled";
                budget_tokens = 16384;
              };
            };
            high = {
              thinkingConfig = {
                thinkingBudget = 24576;
              };
              thinking = {
                type = "enabled";
                budget_tokens = 24576;
              };
            };
            max = {
              thinkingConfig = {
                thinkingBudget = 32768;
              };
              thinking = {
                type = "enabled";
                budget_tokens = 32768;
              };
            };
          };
        };
      };
    };

    antigravity-oss = {
      npm = "@ai-sdk/openai-compatible";
      name = "Antigravity OSS";
      options = {
        baseURL = "http://127.0.0.1:8317/v1";
      };
      models = {
        "gpt-oss-120b-medium" = {
          name = "GPT OSS 120B Medium";
          limit = {
            context = 128000;
            output = 16384;
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
