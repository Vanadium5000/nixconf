# Agent definitions for OpenCode
# Provides mkAgentConfig function for config.json agent key
_:
let
  # Load prompts from prompts/ directory
  promptsDir = ./prompts;

  # Flash model for fast/cheap agents
  flashModel = "antigravity-gemini/gemini-3-flash";
in
{
  # Function to generate agent config with parameterized expensive model
  # Returns attrset for config.json "agent" key
  mkAgentConfig = expensiveModel: {
    # Override built-in Build agent
    build = {
      model = expensiveModel;
      prompt = "{file:./prompts/builder.md}";
    };

    # Override built-in Plan agent
    plan = {
      model = expensiveModel;
      prompt = "{file:./prompts/planner.md}";
      permission = {
        edit = "deny";
        bash = "deny";
      };
    };

    # Advisor: Read-only consultation PRIMARY agent (Tab-cycleable)
    advisor = {
      mode = "primary"; # Primary so it appears in Tab cycle
      model = expensiveModel;
      description = "Read-only advisor for questions, feedback, and discussion";
      prompt = builtins.readFile (promptsDir + "/advisor.md");
      tools = {
        write = false;
        edit = false;
        bash = false;
        task = false;
      };
    };

    # Scout: Fast exploration subagent
    scout = {
      mode = "subagent";
      model = flashModel; # Fast/cheap model for exploration
      description = "Fast codebase explorer for search and pattern discovery";
      prompt = builtins.readFile (promptsDir + "/scout.md");
      tools = {
        write = false;
        edit = false;
        bash = false;
        task = false;
      };
    };

    # Researcher: Documentation lookup subagent
    researcher = {
      mode = "subagent";
      model = flashModel; # Fast/cheap model for research
      description = "Documentation and library specialist for external knowledge";
      prompt = builtins.readFile (promptsDir + "/researcher.md");
      tools = {
        write = false;
        edit = false;
        bash = false;
        task = false;
      };
    };
  };
}
