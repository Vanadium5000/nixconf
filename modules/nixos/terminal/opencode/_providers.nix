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
            context = 1048576;
            output = 65535;
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
            low.thinkingLevel = "low";
            high.thinkingLevel = "high";
          };
        };
        gemini-3-pro-low = {
          name = "Gemini 3 Pro Low";
          limit = {
            context = 1048576;
            output = 65535;
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
            low.thinkingLevel = "low";
            high.thinkingLevel = "high";
          };
        };
        gemini-3-flash = {
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
            output = [
              "text"
            ];
          };
          reasoning = true;
          variants = {
            minimal.thinkingLevel = "minimal";
            low.thinkingLevel = "low";
            medium.thinkingLevel = "medium";
            high.thinkingLevel = "high";
          };
        };
        gemini-3-pro-image = {
          name = "Gemini 3 Pro Image";
          limit = {
            context = 1048576;
            output = 65535;
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
            context = 200000;
            output = 64000;
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
            context = 200000;
            output = 64000;
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
          reasoning = true;
          variants = {
            low = {
              thinkingConfig.thinkingBudget = 8192;
              thinking = {
                type = "enabled";
                budget_tokens = 8192;
              };
            };
            medium = {
              thinkingConfig.thinkingBudget = 16384;
              thinking = {
                type = "enabled";
                budget_tokens = 16384;
              };
            };
            high = {
              thinkingConfig.thinkingBudget = 24576;
              thinking = {
                type = "enabled";
                budget_tokens = 24576;
              };
            };
            max = {
              thinkingConfig.thinkingBudget = 32768;
              thinking = {
                type = "enabled";
                budget_tokens = 32768;
              };
            };
          };
        };
        claude-opus-4-6-thinking = {
          name = "Claude Opus 4.6 Thinking";
          limit = {
            context = 1000000; # 1M token context window (beta)
            output = 128000;
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
          reasoning = true;
          variants = {
            low = {
              thinkingConfig.thinkingBudget = 8192;
              thinking = {
                type = "enabled";
                budget_tokens = 8192;
              };
            };
            medium = {
              thinkingConfig.thinkingBudget = 16384;
              thinking = {
                type = "enabled";
                budget_tokens = 16384;
              };
            };
            high = {
              thinkingConfig.thinkingBudget = 24576;
              thinking = {
                type = "enabled";
                budget_tokens = 24576;
              };
            };
            max = {
              thinkingConfig.thinkingBudget = 32768;
              thinking = {
                type = "enabled";
                budget_tokens = 32768;
              };
            };
          };
        };
      };
    };
  };
}
