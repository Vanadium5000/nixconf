{ lib }:
let
  inherit (lib) mapAttrs;

  # Source of category IDs and supported agent keys:
  # https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/dev/assets/oh-my-opencode.schema.json
  #
  # Local compatibility assumptions:
  # - Keep only official category IDs in generated OMO config.
  # - Continue accepting legacy local state keys used previously in this repo
  #   (`orchestrator`, `coding`, `research`, `multimodal`) via mkState fallback.
  # - Prompt guidance is centralized in AGENTS.md, so we intentionally do not
  #   duplicate it as per-category `prompt_append` fields here.

  categories = {
    "visual-engineering" = {
      label = "Visual Engineering";
      description = "Frontend, UI/UX, styling, and visual interaction work";
      defaultModel = "cliproxyapi/gemini-3.1-pro-high";
    };
    ultrabrain = {
      label = "Ultrabrain";
      description = "Hard logic, architecture, and deep debugging tasks";
      defaultModel = "cliproxyapi/gpt-5.4";
    };
    deep = {
      label = "Deep";
      description = "General implementation and autonomous end-to-end execution";
      defaultModel = "cliproxyapi/gpt-5.3-codex";
    };
    artistry = {
      label = "Artistry";
      description = "Creative, non-conventional problem solving";
      defaultModel = "cliproxyapi/gemini-3.1-pro-high";
    };
    quick = {
      label = "Quick";
      description = "Trivial low-effort changes and routine updates";
      defaultModel = "cliproxyapi/gemini-3-flash";
    };
    writing = {
      label = "Writing";
      description = "Writing and communication upstream agents";
      defaultModel = "cliproxyapi/gemini-3-flash";
    };
    "unspecified-low" = {
      label = "Unspecified (Low)";
      description = "Fallback category for low-effort uncategorized work";
      defaultModel = "cliproxyapi/gemini-3-flash";
    };
    "unspecified-high" = {
      label = "Unspecified (High)";
      description = "Fallback category for high-effort uncategorized work";
      defaultModel = "cliproxyapi/gpt-5.4";
    };
  };

  mkState =
    { stateFile }:
    let
      exists = builtins.pathExists stateFile;
      content = if exists then builtins.readFile stateFile else "";
      isValid = exists && content != "" && content != " " && content != "{}";
      data = if isValid then builtins.fromJSON content else { };
      legacyAdvanced = data.advanced or categories.ultrabrain.defaultModel;
      legacyMedium = data.medium or categories.deep.defaultModel;
      legacyFast = data.fast or categories.quick.defaultModel;

      legacyOrchestrator = data.categories.orchestrator or legacyAdvanced;
      legacyCoding = data.categories.coding or legacyAdvanced;
      legacyResearch = data.categories.research or legacyMedium;
      legacyWriting = data.categories.writing or legacyMedium;
      legacyMultimodal = data.categories.multimodal or legacyFast;
    in
    {
      categories = {
        "visual-engineering" = data.categories."visual-engineering" or legacyMultimodal;
        ultrabrain = data.categories.ultrabrain or legacyOrchestrator;
        deep = data.categories.deep or (if data.categories ? coding then legacyCoding else legacyResearch);
        artistry = data.categories.artistry or legacyMultimodal;
        quick = data.categories.quick or legacyFast;
        writing = data.categories.writing or legacyWriting;
        "unspecified-low" = data.categories."unspecified-low" or legacyMedium;
        "unspecified-high" = data.categories."unspecified-high" or legacyAdvanced;
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
      categories = mapAttrs (categoryId: _: { model = state.categories.${categoryId}; }) categories;
      agents = {
        sisyphus.category = "unspecified-high";
        "sisyphus-junior".category = "deep";
        hephaestus.category = "deep";
        prometheus.category = "deep";
        atlas.category = "deep";
        oracle.category = "ultrabrain";
        librarian.category = "deep";
        explore.category = "deep";
        metis.category = "ultrabrain";
        momus.category = "writing";
        "multimodal-looker".category = "visual-engineering";
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
      new_task_system_enabled = true;
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
