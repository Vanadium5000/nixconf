{
  config = {
    google = {
      npm = "@ai-sdk/google";
      models = {
        "antigravity-gemini-3-pro-low" = {
          name = "Gemini 3 Pro Low (Antigravity)";
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
            output = [ "text" ];
          };
        };
        "antigravity-gemini-3-pro-high" = {
          name = "Gemini 3 Pro High (Antigravity)";
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
            output = [ "text" ];
          };
        };

        "antigravity-gemini-3-flash" = {
          name = "Gemini 3 Flash (Antigravity)";
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

        "antigravity-claude-sonnet-4-5" = {
          name = "Claude Sonnet 4.5 (Antigravity)";
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

        "antigravity-claude-sonnet-4-5-thinking-low" = {
          name = "Claude Sonnet 4.5 Low (Antigravity)";
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
        "antigravity-claude-sonnet-4-5-thinking-medium" = {
          name = "Claude Sonnet 4.5 Medium (Antigravity)";
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
        "antigravity-claude-sonnet-4-5-thinking-high" = {
          name = "Claude Sonnet 4.5 High (Antigravity)";
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

        "antigravity-claude-opus-4-5-thinking-low" = {
          name = "Claude Opus 4.5 Low (Antigravity)";
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
        "antigravity-claude-opus-4-5-thinking-medium" = {
          name = "Claude Opus 4.5 Medium (Antigravity)";
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
        "antigravity-claude-opus-4-5-thinking-high" = {
          name = "Claude Opus 4.5 High (Antigravity)";
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
        "antigravity-gpt-oss-120b-medium" = {
          name = "GPT-OSS 120B Medium (Antigravity)";
          limit = {
            context = 131072;
            output = 32768;
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
  };
}
