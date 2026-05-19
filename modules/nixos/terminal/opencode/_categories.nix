{ lib }:
let
  inherit (lib) mapAttrs mapAttrsToList optionalAttrs;

  # These are local model-selection groups, not oh-my-opencode-slim schema
  # fields. The generated plugin config binds slim agents to these groups.
  # Source: https://github.com/alvinunreal/oh-my-opencode-slim/blob/master/docs/configuration.md
  presetName = "nixconf";

  categories = {
    "visual-engineering" = {
      label = "Visual Engineering";
      description = "Frontend, UI/UX, styling, and visual interaction work";
      defaultModel = "omniroute/gemini-3.1-pro-high";
    };
    ultrabrain = {
      label = "Ultrabrain";
      description = "Hard logic, architecture, and deep debugging tasks";
      defaultModel = "omniroute/gpt-5.4";
    };
    deep = {
      label = "Deep";
      description = "General implementation and autonomous end-to-end execution";
      defaultModel = "omniroute/gpt-5.3-codex";
    };
    artistry = {
      label = "Artistry";
      description = "Creative, non-conventional problem solving";
      defaultModel = "omniroute/gemini-3.1-pro-high";
    };
    quick = {
      label = "Quick";
      description = "Trivial low-effort changes and routine updates";
      defaultModel = "omniroute/gemini-3-flash";
    };
    writing = {
      label = "Writing";
      description = "Writing and communication upstream agents";
      defaultModel = "omniroute/gemini-3-flash";
    };
    "unspecified-low" = {
      label = "Unspecified (Low)";
      description = "Fallback category for low-effort uncategorized work";
      defaultModel = "omniroute/gemini-3-flash";
    };
    "unspecified-high" = {
      label = "Unspecified (High)";
      description = "Fallback category for high-effort uncategorized work";
      defaultModel = "omniroute/gpt-5.4";
    };
  };

  # Built-in slim agents and allowed MCP/skill surfaces. Keep this mapping aligned
  # with upstream agent names and defaults, then override only repo-specific model
  # groups. Sources:
  # - https://github.com/alvinunreal/oh-my-opencode-slim/blob/master/src/config/constants.ts
  # - https://github.com/alvinunreal/oh-my-opencode-slim/blob/master/src/cli/providers.ts
  agentAssignments = {
    orchestrator = {
      category = "unspecified-high";
      skills = [ "*" ];
      mcps = [
        "*"
        "!context7"
      ];
    };
    oracle = {
      category = "ultrabrain";
      skills = [ "simplify" ];
      mcps = [ ];
    };
    librarian = {
      category = "quick";
      skills = [ ];
      mcps = [
        "websearch"
        "context7"
        "grep_app"
      ];
    };
    explorer = {
      category = "quick";
      skills = [ ];
      mcps = [ ];
    };
    designer = {
      category = "visual-engineering";
      skills = [ "agent-browser" ];
      mcps = [ ];
    };
    fixer = {
      category = "deep";
      skills = [ ];
      mcps = [ ];
    };
    observer = {
      category = "deep";
      skills = [ ];
      mcps = [ ];
    };
    council = {
      category = "ultrabrain";
      skills = [ ];
      mcps = [ ];
    };
  };

  councilAssignments = {
    architect = {
      category = "ultrabrain";
      prompt = "Architecture, risk, invariants, and long-term maintainability.";
    };
    implementer = {
      category = "deep";
      prompt = "Implementation feasibility, callsites, tests, and migration mechanics.";
    };
    reviewer = {
      category = "ultrabrain";
      prompt = "Correctness, security, edge cases, and failure modes.";
    };
    designer = {
      category = "visual-engineering";
      prompt = "Frontend, UX, visual quality, accessibility, and interaction details.";
    };
  };

  extractSelection =
    raw: fallbackModel:
    if builtins.isString raw then
      { model = raw; }
    else if builtins.isAttrs raw && raw ? model then
      raw
    else
      { model = fallbackModel; };

  selectionVariant = selection: selection.variant or selection.reasoningEffort or null;

  mkAgentConfig =
    state: _agentName: assignment:
    let
      selection = state.categories.${assignment.category};
      variant = selectionVariant selection;
    in
    {
      model = selection.model;
    }
    // optionalAttrs (variant != null && variant != "") { inherit variant; }
    // optionalAttrs (assignment ? skills) { skills = assignment.skills; }
    // optionalAttrs (assignment ? mcps) { mcps = assignment.mcps; };

  mkCouncilMember =
    state: _memberName: assignment:
    let
      selection = state.categories.${assignment.category};
      variant = selectionVariant selection;
    in
    {
      model = selection.model;
      inherit (assignment) prompt;
    }
    // optionalAttrs (variant != null && variant != "") { inherit variant; };

  agentBindings = mapAttrsToList (agentName: assignment: {
    path = [
      "presets"
      presetName
      agentName
    ];
    category = assignment.category;
  }) agentAssignments;

  councilBindings = mapAttrsToList (memberName: assignment: {
    path = [
      "council"
      "presets"
      "default"
      memberName
    ];
    category = assignment.category;
  }) councilAssignments;
in
{
  mkState =
    { stateFile }:
    let
      exists = builtins.pathExists stateFile;
      content = if exists then builtins.readFile stateFile else "";
      isValid = exists && content != "" && content != " " && content != "{}";
      data = if isValid then builtins.fromJSON content else { };
      dataCategories = data.categories or { };

      legacyAdvanced = data.advanced or categories.ultrabrain.defaultModel;
      legacyMedium = data.medium or categories.deep.defaultModel;
      legacyFast = data.fast or categories.quick.defaultModel;

      legacyOrchestrator = dataCategories.orchestrator or legacyAdvanced;
      legacyCoding = dataCategories.coding or legacyAdvanced;
      legacyResearch = dataCategories.research or legacyMedium;
      legacyWriting = dataCategories.writing or legacyMedium;
      legacyMultimodal = dataCategories.multimodal or legacyFast;

      rawVisualEngineering = dataCategories."visual-engineering" or null;
      rawUltrabrain = dataCategories.ultrabrain or null;
      rawDeep = dataCategories.deep or null;
      rawArtistry = dataCategories.artistry or null;
      rawQuick = dataCategories.quick or null;
      rawWriting = dataCategories.writing or null;
      rawUnspecifiedLow = dataCategories."unspecified-low" or null;
      rawUnspecifiedHigh = dataCategories."unspecified-high" or null;
    in
    {
      categories = {
        "visual-engineering" = extractSelection (
          if rawVisualEngineering == null then legacyMultimodal else rawVisualEngineering
        ) categories."visual-engineering".defaultModel;
        ultrabrain = extractSelection (
          if rawUltrabrain == null then legacyOrchestrator else rawUltrabrain
        ) categories.ultrabrain.defaultModel;
        deep = extractSelection (
          if rawDeep == null then
            (if dataCategories ? coding then legacyCoding else legacyResearch)
          else
            rawDeep
        ) categories.deep.defaultModel;
        artistry = extractSelection (
          if rawArtistry == null then legacyMultimodal else rawArtistry
        ) categories.artistry.defaultModel;
        quick = extractSelection (
          if rawQuick == null then legacyFast else rawQuick
        ) categories.quick.defaultModel;
        writing = extractSelection (
          if rawWriting == null then legacyWriting else rawWriting
        ) categories.writing.defaultModel;
        "unspecified-low" = extractSelection (
          if rawUnspecifiedLow == null then legacyMedium else rawUnspecifiedLow
        ) categories."unspecified-low".defaultModel;
        "unspecified-high" = extractSelection (
          if rawUnspecifiedHigh == null then legacyAdvanced else rawUnspecifiedHigh
        ) categories."unspecified-high".defaultModel;
      };
    };

  mkMenuMetadata = {
    menu = {
      title = "🤖 Model Configuration Manager";
      syncAction = "General: Sync Model Cache from API";
      syncConfigAction = "General: Sync OpenCode + OMO Slim Runtime Configs";
      changeCategoriesAction = "OpenCode/OMO Slim: Change Model Groups";
      replaceModelAction = "OpenCode/OMO Slim: Replace Model Across Groups";
      presetSaveAction = "OpenCode/OMO Slim: Save Model-Group Preset";
      presetManageAction = "OpenCode/OMO Slim: Model-Group Preset Manager";
      initAction = "OpenCode: Init Project MCPs (Current Dir)";
      syncOmpAction = "OMP: Sync ~/.omp/agent/models.yml";
      exitAction = "Exit";
      categoryHeader = "Select OpenCode/OMO Slim model groups to update (Space to select, Enter to confirm)";
      categoryMultiHeader = "Select one or more OpenCode/OMO Slim model groups to update (Space to select, Enter to confirm)";
      modelHeaderPrefix = "Select model for OpenCode/OMO Slim model group";
      modelHeaderMultiple = "Select model for selected OpenCode/OMO Slim model groups";
      replaceSourceHeader = "Select current OpenCode/OMO Slim group model to replace";
      replaceTargetHeader = "Select replacement model";
      presetNamePrompt = "Model-group preset name";
      presetManagerHeader = "Select model-group preset";
      presetActionHeader = "Model-group preset action";
      categoryStatePrefix = "OpenCode/OMO Slim model-group presets";
    };
    categories = mapAttrs (categoryId: category: category // { id = categoryId; }) categories;
    slimModelBindings = agentBindings ++ councilBindings;
  };

  mkSlimConfig =
    { state }:
    {
      # JSONC is preferred by upstream and project overrides use
      # `.opencode/oh-my-opencode-slim.jsonc`. Source:
      # https://github.com/alvinunreal/oh-my-opencode-slim/blob/master/docs/configuration.md
      "$schema" = "https://unpkg.com/oh-my-opencode-slim@latest/oh-my-opencode-slim.schema.json";
      preset = presetName;
      autoUpdate = false;
      setDefaultAgent = true;

      # Observer is disabled upstream by default; enable it because the deep group
      # is assigned to image-capable OmniRoute models in this repo's state/cache.
      disabled_agents = [ ];
      disabled_mcps = [ ];

      websearch = {
        provider = "exa";
      };

      sessionManager = {
        maxSessionsPerAgent = 3;
        readContextMinLines = 10;
        readContextMaxFiles = 8;
      };

      todoContinuation = {
        maxContinuations = 5;
        cooldownMs = 3000;
        autoEnable = false;
        autoEnableThreshold = 4;
      };

      multiplexer = {
        type = "none";
        layout = "main-vertical";
        main_pane_size = 60;
      };

      fallback = {
        enabled = true;
        timeoutMs = 15000;
        retryDelayMs = 500;
        retry_on_empty = true;
        chains = { };
      };

      presets.${presetName} = mapAttrs (mkAgentConfig state) agentAssignments;

      council = {
        default_preset = "default";
        timeout = 180000;
        councillor_execution_mode = "parallel";
        councillor_retries = 3;
        presets.default = mapAttrs (mkCouncilMember state) councilAssignments;
      };
    };
}
