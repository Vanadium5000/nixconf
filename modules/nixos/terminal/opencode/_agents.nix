# Agent definitions for OpenCode
# Replaces oh-my-opencode's 10 agents with 5 focused agents
{ }:
let
  # Load prompts from prompts/ directory
  promptsDir = ./prompts;

  # Flash model for fast/cheap agents
  flashModel = "antigravity-gemini/gemini-3-flash";
in
{
  # Function to generate agents config with parameterized expensive model
  mkAgentsConfig = expensiveModel: {
    # Planner: Strategic planning, work breakdown, read-only
    planner = {
      model = expensiveModel;
      description = "Strategic planner for work breakdown and task decomposition";
      tools = {
        # Read-only - can delegate but not modify
        Write = false;
        Edit = false;
        Bash = false;
        interactive_bash = false;
      };
      prompt_append = builtins.readFile (promptsDir + "/planner.md");
    };

    # Builder: Implementation, code writing, full tool access
    builder = {
      model = expensiveModel;
      description = "Implementation specialist with full tool access";
      # Full tool access - no restrictions
      prompt_append = builtins.readFile (promptsDir + "/builder.md");
    };

    # Advisor: Read-only consultation, Q&A, intuitive feedback
    advisor = {
      model = expensiveModel;
      description = "Read-only advisor for questions, feedback, and discussion";
      tools = {
        # Strictly read-only - no modifications, no delegation
        Write = false;
        Edit = false;
        Bash = false;
        todowrite = false;
        delegate_task = false;
        task = false;
        interactive_bash = false;
      };
      prompt_append = builtins.readFile (promptsDir + "/advisor.md");
    };

    # Scout: Fast exploration, grep, codebase search
    scout = {
      model = flashModel; # Fast/cheap model for exploration
      description = "Fast codebase explorer for search and pattern discovery";
      tools = {
        # Read-only exploration
        Write = false;
        Edit = false;
        Bash = false;
        delegate_task = false;
        interactive_bash = false;
      };
      prompt_append = builtins.readFile (promptsDir + "/scout.md");
    };

    # Researcher: Documentation lookup, web search, library research
    researcher = {
      model = flashModel; # Fast/cheap model for research
      description = "Documentation and library specialist for external knowledge";
      tools = {
        # Read-only with MCP access for web search
        Write = false;
        Edit = false;
        Bash = false;
        delegate_task = false;
        interactive_bash = false;
      };
      prompt_append = builtins.readFile (promptsDir + "/researcher.md");
    };
  };

  # Simplified category system: quick, standard, heavy
  mkCategoriesConfig = expensiveModel: {
    # Quick: Trivial tasks - single file changes, typo fixes
    quick = {
      model = flashModel;
    };

    # Standard: General tasks, moderate complexity
    standard = {
      model = "antigravity-gemini/gemini-3-pro-preview";
    };

    # Heavy: Complex reasoning, architecture decisions
    heavy = {
      model = expensiveModel;
    };
  };
}
