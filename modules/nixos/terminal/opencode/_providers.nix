{ self, lib, ... }:
let
  publicBaseDomain = self.secrets.PUBLIC_BASE_DOMAIN;
  routerProviderId = "router";
  routerProviderName = "Router";
  # models.json is the reviewed cache written by `models sync`. It keeps
  # upstream metadata local while the provider config uses the same model IDs.
  modelsFile = ./models.json;
  # Local patches are reserved for exact model facts the sync API omits or gets
  # wrong. Prefer vendor pages for real context/output pairs; OmniRoute often
  # returns context-only rows and OpenCode rejects partial `limit` objects, so
  # normalizeModel fills output with the upstream openai-compatible default
  # until a patch lands. Sources: https://opencode.ai/docs/models/ and
  # https://github.com/diegosouzapw/OmniRoute/pull/578
  localPatchesFile = ./_model-local-patches.json;
  localPatches =
    let
      exists = builtins.pathExists localPatchesFile;
      content = if exists then builtins.readFile localPatchesFile else "";
      isValid = exists && content != "" && content != " " && content != "{}";
    in
    if isValid then builtins.fromJSON content else { };

  dynamicData =
    let
      exists = builtins.pathExists modelsFile;
      content = if exists then builtins.readFile modelsFile else "";
      # fromJSON fails on empty strings, so missing/empty caches evaluate as no models.
      isValid = exists && content != "" && content != " " && content != "{}";
    in
    if isValid then builtins.fromJSON content else { };

  baseModels =
    dynamicData.providers.${routerProviderId}.models or dynamicData.providers.omniroute.models or { };
  filteredPatches = lib.filterAttrs (modelId: _: builtins.hasAttr modelId baseModels) localPatches;

  # OpenCode custom-provider models validate `limit.context` + `limit.output`
  # together. Upstream's openai-compatible placeholder uses output=8192 when the
  # catalog omits max completion tokens; keep that same floor here so context-only
  # OmniRoute rows stay schema-valid until a vendor patch lands.
  # Source: opencode 1.17.11 bundled provider defaults (limit:{context:128000,output:8192})
  # Source: https://opencode.ai/docs/models/
  defaultOutputLimit = 8192;

  normalizeModel =
    _modelId: model:
    let
      hasContext = model ? context || (model ? limit && model.limit ? context);
      hasInput = model ? input || (model ? limit && model.limit ? input);
      hasOutput = model ? output || (model ? limit && model.limit ? output);
      # Drop output-only rows: context anchors compaction and OpenCode rejects a
      # partial limit object. Pair missing output with the upstream default.
      limit = lib.optionalAttrs hasContext (
        {
          context = model.context or model.limit.context;
          output = if hasOutput then model.output or model.limit.output else defaultOutputLimit;
        }
        // (lib.optionalAttrs hasInput {
          input = model.input or model.limit.input;
        })
      );
    in
    # Preserve optional wire `id` when the catalog key is a short alias of the
    # gateway model path. Source: https://opencode.ai/docs/models/ and
    # https://opencode.ai/docs/providers/
    (builtins.removeAttrs model [
      "context"
      "input"
      "output"
      "limit"
    ])
    // (lib.optionalAttrs (limit != { }) { inherit limit; });

  unifiedProvider = {
    # The concrete gateway is mutable (`models provider ...`); OpenCode only sees
    # one stable Router provider so agent/category model IDs do not churn when
    # switching CLIProxyAPI, Bifrost, or OmniRoute. Source: https://opencode.ai/docs/providers/
    npm = "@ai-sdk/openai-compatible";
    name = routerProviderName;
    options = {
      baseURL = "https://cliproxyapi.${publicBaseDomain}/v1";
      apiKey = self.secrets.CLIPROXYAPI_KEY;

      # OpenCode's request timeout covers slow first events from gateway-routed
      # providers; 200000ms matches the shared models timeout and is 2x OMP's
      # first-event stream watchdog default, while still failing visibly.
      # Source: https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/config/provider.ts
      timeout = 200000;

      # OpenCode default: no SSE idle watchdog unless `chunkTimeout` is set.
      # OmniRoute/OpenAI-compatible tool streams have had chunk-shape/finish
      # compatibility bugs; abort idle streams so a half-closed gateway response
      # cannot leave the session busy forever.
      # Source: https://github.com/anomalyco/opencode/issues/21173
      chunkTimeout = 45000;
    };
    models = builtins.mapAttrs normalizeModel (lib.recursiveUpdate baseModels filteredPatches);
  };
in
{
  config = {
    ${routerProviderId} = {
      inherit (unifiedProvider)
        npm
        name
        options
        models
        ;
    };
  };
}
