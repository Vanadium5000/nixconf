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

      # Helper to extract full category config from either string or object format
      # Handles: "cliproxyapi/model" or { model = "cliproxyapi/model"; reasoningEffort = "high" }
      # Returns full object to preserve reasoningEffort, not just the model string
      extractModel =
        raw:
        if builtins.isString raw then
          { model = raw; }
        else if builtins.isAttrs raw && raw ? model then
          raw
        else
          { model = null; };

      legacyAdvanced = data.advanced or categories.ultrabrain.defaultModel;
      legacyMedium = data.medium or categories.deep.defaultModel;
      legacyFast = data.fast or categories.quick.defaultModel;

      legacyOrchestrator = data.categories.orchestrator or legacyAdvanced;
      legacyCoding = data.categories.coding or legacyAdvanced;
      legacyResearch = data.categories.research or legacyMedium;
      legacyWriting = data.categories.writing or legacyMedium;
      legacyMultimodal = data.categories.multimodal or legacyFast;

      # Extract model strings from state, falling back to legacy defaults
      rawVisualEngineering = data.categories."visual-engineering" or null;
      rawUltrabrain = data.categories.ultrabrain or null;
      rawDeep = data.categories.deep or null;
      rawArtistry = data.categories.artistry or null;
      rawQuick = data.categories.quick or null;
      rawWriting = data.categories.writing or null;
      rawUnspecifiedLow = data.categories."unspecified-low" or null;
      rawUnspecifiedHigh = data.categories."unspecified-high" or null;

      catVisualEngineering =
        if rawVisualEngineering == null then legacyMultimodal else extractModel rawVisualEngineering;
      catUltrabrain = if rawUltrabrain == null then legacyOrchestrator else extractModel rawUltrabrain;
      catDeep =
        if rawDeep == null then
          (if data.categories ? coding then legacyCoding else legacyResearch)
        else
          extractModel rawDeep;
      catArtistry = if rawArtistry == null then legacyMultimodal else extractModel rawArtistry;
      catQuick = if rawQuick == null then legacyFast else extractModel rawQuick;
      catWriting = if rawWriting == null then legacyWriting else extractModel rawWriting;
      catUnspecifiedLow =
        if rawUnspecifiedLow == null then legacyMedium else extractModel rawUnspecifiedLow;
      catUnspecifiedHigh =
        if rawUnspecifiedHigh == null then legacyAdvanced else extractModel rawUnspecifiedHigh;
    in
    {
      categories = {
        "visual-engineering" = catVisualEngineering;
        ultrabrain = catUltrabrain;
        deep = catDeep;
        artistry = catArtistry;
        quick = catQuick;
        writing = catWriting;
        "unspecified-low" = catUnspecifiedLow;
        "unspecified-high" = catUnspecifiedHigh;
      };
    };

  mkMenuMetadata = {
    menu = {
      title = "🤖 OpenCode Configuration Manager";
      syncAction = "Sync Models from API";
      syncConfigAction = "Sync Config from State";
      changeCategoriesAction = "Change Category Models";
      replaceModelAction = "Replace Model Across Categories";
      presetSaveAction = "Save Current Config as Preset";
      presetManageAction = "Preset Manager";
      initAction = "Init Project MCPs (Current Dir)";
      exitAction = "Exit";
      categoryHeader = "Select categories to update";
      categoryMultiHeader = "Select one or more categories to update";
      modelHeaderPrefix = "Select model for";
      modelHeaderMultiple = "Select model for selected categories";
      replaceSourceHeader = "Select current model to replace";
      replaceTargetHeader = "Select replacement model";
      presetNamePrompt = "Preset name";
      presetManagerHeader = "Select preset";
      presetActionHeader = "Preset action";
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
    let
      # Extract category config, handling both legacy string format and new object format
      extractCategory =
        categoryId:
        let
          raw = state.categories.${categoryId};
        in
        if builtins.isString raw then { model = raw; } else raw;

      # Get reasoning effort from category config
      getReasoningEffort =
        categoryId:
        let
          cat = extractCategory categoryId;
        in
        cat.reasoningEffort or null;
    in
    {
      "$schema" =
        "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/dev/assets/oh-my-opencode.schema.json";
      categories = mapAttrs (categoryId: _: extractCategory categoryId) categories;
      agents = {
        # Main orchestrator — Claude Opus (communicator type, 1100-line prompt)
        sisyphus = {
          category = "unspecified-high";
        }
        // (lib.optionalAttrs (getReasoningEffort "unspecified-high" != null) {
          variant = getReasoningEffort "unspecified-high";
        });
        # Task executor — category overridden dynamically per-task by orchestrator
        "sisyphus-junior" = {
          category = "unspecified-low";
        }
        // (lib.optionalAttrs (getReasoningEffort "unspecified-low" != null) {
          variant = getReasoningEffort "unspecified-low";
        });
        # Autonomous deep worker — requires GPT-5.3 Codex (no fallback)
        hephaestus = {
          category = "deep";
        }
        // (lib.optionalAttrs (getReasoningEffort "deep" != null) {
          variant = getReasoningEffort "deep";
        });
        # Strategic planner — Claude-optimized dual-prompt agent
        prometheus = {
          category = "unspecified-high";
        }
        // (lib.optionalAttrs (getReasoningEffort "unspecified-high" != null) {
          variant = getReasoningEffort "unspecified-high";
        });
        # Todo orchestrator/conductor — Sonnet-class sufficient
        atlas = {
          category = "unspecified-low";
        }
        // (lib.optionalAttrs (getReasoningEffort "unspecified-low" != null) {
          variant = getReasoningEffort "unspecified-low";
        });
        # Architecture consultant — GPT-5.4 for deep reasoning (read-only)
        oracle = {
          category = "ultrabrain";
        }
        // (lib.optionalAttrs (getReasoningEffort "ultrabrain" != null) {
          variant = getReasoningEffort "ultrabrain";
        });
        # Docs/code search — utility runner, speed over intelligence
        librarian = {
          category = "quick";
        }
        // (lib.optionalAttrs (getReasoningEffort "quick" != null) {
          variant = getReasoningEffort "quick";
        });
        # Fast codebase grep — utility runner, fire many in parallel
        explore = {
          category = "quick";
        }
        // (lib.optionalAttrs (getReasoningEffort "quick" != null) {
          variant = getReasoningEffort "quick";
        });
        # Gap analyzer — Claude-optimized communicator type
        metis = {
          category = "unspecified-high";
        }
        // (lib.optionalAttrs (getReasoningEffort "unspecified-high" != null) {
          variant = getReasoningEffort "unspecified-high";
        });
        # Ruthless plan reviewer — GPT-5.4 for deep verification
        momus = {
          category = "ultrabrain";
        }
        // (lib.optionalAttrs (getReasoningEffort "ultrabrain" != null) {
          variant = getReasoningEffort "ultrabrain";
        });
        # Vision/screenshots — GPT-5.3 Codex preferred (multimodal)
        "multimodal-looker" = {
          category = "deep";
        }
        // (lib.optionalAttrs (getReasoningEffort "deep" != null) {
          variant = getReasoningEffort "deep";
        });
      };
      disabled_mcps = [
        # Example Content:
        # "websearch"
        # "context7"
        # "grep_app"
      ];
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
