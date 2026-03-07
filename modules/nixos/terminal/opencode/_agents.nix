# Agent definitions for OpenCode
# Provides mkAgentConfig function for config.json agent key
_:
let
  # Load prompts from prompts/ directory
  promptsDir = ./prompts;
in
{
  # Function to generate agent configs
  # Returns attrset for config.json "agent" key
  mkAgentConfig =
    {
      advancedModel,
      mediumModel,
      fastModel,
    }:
    {
      # Override built-in Build agent
      build = {
        model = advancedModel;
        prompt = "{file:./prompts/builder.md}";
        permission = {
          bash = "ask";
        };
      };

      # Override built-in Plan agent
      plan = {
        model = advancedModel;
        prompt = "{file:./prompts/planner.md}";
        permission = {
          edit = "deny";
          bash = "ask";
        };
      };

      # Plan Reviewer: Critical analysis of plans before implementation
      # Auto-invoked after Planner completes to validate plans
      plan-reviewer = {
        mode = "subagent";
        model = advancedModel;
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
        model = advancedModel;
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
        model = fastModel;
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
        model = mediumModel;
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
        model = fastModel;
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
        model = mediumModel;
        description = "Test writer and runner for automated verification";
        prompt = builtins.readFile (promptsDir + "/tester.md");
        tools = {
          write = true; # Can write test files
          edit = true; # Can edit test files
          bash = true; # Can run tests
          task = false;
        };
      };

      # General: Universal assistant for miscellaneous tasks
      general = {
        mode = "primary";
        model = advancedModel;
        description = "General-purpose agent for researching complex questions and executing multi-step tasks";
      };

      # Explore: Rapid codebase discovery and search
      explore = {
        mode = "subagent";
        model = mediumModel;
        description = "Fast agent specialized for exploring codebases";
      };
    };
}
