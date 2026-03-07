{ lib }:
let
  inherit (lib) mapAttrs optionalAttrs;

  repoPromptAppend = ''
    Follow this repository's local rules in addition to your upstream defaults.
    Preserve existing comments, comment the WHY rather than the WHAT, never run
    rebuild commands, prefer `config.preferences.*` over hardcoded values, and
    verify changes with formatting, linting, and tests when relevant.
  '';

  categories = {
    orchestrator = {
      label = "Orchestrator";
      description = "Sisyphus orchestration and delegated long-running work";
      defaultModel = "cliproxyapi/gemini-3.1-pro-high";
      promptAppend = repoPromptAppend;
    };
    coding = {
      label = "Coding";
      description = "Implementation-heavy upstream coding agents";
      defaultModel = "cliproxyapi/gemini-3.1-pro-high";
      promptAppend = repoPromptAppend;
    };
    research = {
      label = "Research";
      description = "Research, exploration, and planning upstream agents";
      defaultModel = "cliproxyapi/gemini-3-flash";
      promptAppend = repoPromptAppend;
    };
    writing = {
      label = "Writing";
      description = "Writing and communication upstream agents";
      defaultModel = "cliproxyapi/gemini-3-flash";
      promptAppend = repoPromptAppend;
    };
    multimodal = {
      label = "Multimodal";
      description = "Visual and browser-oriented upstream agents";
      defaultModel = "cliproxyapi/gemini-3-flash";
      promptAppend = repoPromptAppend;
    };
  };

  mkState =
    { stateFile }:
    let
      exists = builtins.pathExists stateFile;
      content = if exists then builtins.readFile stateFile else "";
      isValid = exists && content != "" && content != " " && content != "{}";
      data = if isValid then builtins.fromJSON content else { };
      legacyAdvanced = data.advanced or categories.coding.defaultModel;
      legacyMedium = data.medium or categories.research.defaultModel;
      legacyFast = data.fast or categories.multimodal.defaultModel;
    in
    {
      categories = {
        orchestrator = data.categories.orchestrator or legacyAdvanced;
        coding = data.categories.coding or legacyAdvanced;
        research = data.categories.research or legacyMedium;
        writing = data.categories.writing or legacyMedium;
        multimodal = data.categories.multimodal or legacyFast;
      };
    };

  mkMenuMetadata = {
    menu = {
      title = "🤖 OpenCode Configuration Manager";
      syncAction = "Sync Models from API";
      changeCategoryAction = "Change Category Model";
      initAction = "Init Project MCPs (Current Dir)";
      exitAction = "Exit";
      categoryHeader = "Select category to update";
      modelHeaderPrefix = "Select model for";
      categoryStatePrefix = "Category presets";
    };
    categories = mapAttrs (
      categoryId: category:
      category
      // {
        id = categoryId;
      }
    ) categories;
  };

  mkOhMyConfig =
    { state }:
    {
      "$schema" =
        "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/dev/assets/oh-my-opencode.schema.json";
      categories = mapAttrs (
        categoryId: category:
        {
          model = state.categories.${categoryId};
        }
        // optionalAttrs (category ? promptAppend) {
          prompt_append = category.promptAppend;
        }
      ) categories;
      agents = {
        sisyphus.category = "orchestrator";
        hephaestus.category = "coding";
        prometheus.category = "coding";
        atlas.category = "coding";
        oracle.category = "research";
        librarian.category = "research";
        explore.category = "research";
        metis.category = "research";
        momus.category = "writing";
        "multimodal-looker".category = "multimodal";
      };
      disabled_mcps = [
        "websearch"
        "context7"
        "grep_app"
      ];
      background_task = {
        defaultConcurrency = 4;
        staleTimeoutMs = 180000;
      };
      tmux = {
        enabled = true;
        layout = "main-vertical";
        main_pane_size = 60;
        main_pane_min_width = 120;
        agent_pane_min_width = 40;
      };
      browser_automation_engine = {
        provider = "playwright";
      };
      experimental = {
        task_system = true;
      };
    };
in
{
  inherit
    categories
    mkMenuMetadata
    mkOhMyConfig
    mkState
    ;
}
