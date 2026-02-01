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

    # Plan Reviewer: Critical analysis of plans before implementation
    # Auto-invoked after Planner completes to validate plans
    plan-reviewer = {
      mode = "subagent";
      model = expensiveModel; # Heavy model for deep critical analysis
      description = "Critical plan reviewer that validates plans before implementation";
      prompt = builtins.readFile (promptsDir + "/plan-reviewer.md");
      tools = {
        write = false;
        edit = false;
        bash = false;
        task = false; # Cannot delegate, only review
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

    # Verifier: Automated validation after changes
    verifier = {
      mode = "subagent";
      model = flashModel; # Fast/cheap - just runs validation commands
      description = "Automated verification and linting after changes";
      prompt = builtins.readFile (promptsDir + "/verifier.md");
      tools = {
        write = false;
        edit = false;
        bash = true; # Can run linters/tests
        task = false;
      };
    };

    # Tester: Test-driven development specialist
    tester = {
      mode = "subagent";
      model = flashModel; # Tests are pattern-based, flash is sufficient
      description = "Test writer and runner for automated verification";
      prompt = builtins.readFile (promptsDir + "/tester.md");
      tools = {
        write = true; # Can write test files
        edit = true; # Can edit test files
        bash = true; # Can run tests
        task = false;
      };
    };
  };
}
