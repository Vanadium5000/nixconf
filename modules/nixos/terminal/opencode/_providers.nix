{ self, lib, ... }:
let
  publicBaseDomain = self.secrets.PUBLIC_BASE_DOMAIN;
  # models.json is the reviewed cache written by `models sync`. It keeps
  # upstream metadata local while the provider config uses the same model IDs.
  modelsFile = ./models.json;
  # Local patches are reserved for exact model facts the sync API omits or gets
  # wrong. Keep token limits sourced from vendor model pages because OpenCode's
  # provider schema needs paired context/output limits and OmniRoute may expose
  # output-only defaults. Sources: https://opencode.ai/docs/models/ and
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

  baseModels = dynamicData.providers.omniroute.models or { };
  filteredPatches = lib.filterAttrs (modelId: _: builtins.hasAttr modelId baseModels) localPatches;

  normalizeModel =
    _modelId: model:
    let
      hasContext = model ? context || (model ? limit && model.limit ? context);
      hasInput = model ? input || (model ? limit && model.limit ? input);
      limit = lib.optionalAttrs hasContext (
        {
          context = model.context or model.limit.context;
        }
        // (lib.optionalAttrs hasInput {
          input = model.input or model.limit.input;
        })
        // (lib.optionalAttrs (model ? output || (model ? limit && model.limit ? output)) {
          output = model.output or model.limit.output;
        })
      );
    in
    # OpenCode model limits are a paired contract (`context` + optional output in
    # this repo's normalization); output-only API defaults are dropped so the
    # generated provider config never carries an invalid partial limit.
    # Source: https://opencode.ai/docs/models/
    (builtins.removeAttrs model [
      "context"
      "input"
      "output"
      "limit"
    ])
    // (lib.optionalAttrs (limit != { }) { inherit limit; });

  unifiedProvider = {
    # OmniRoute exposes an OpenAI-compatible chat-completions surface here; using
    # OpenCode's Responses provider makes upstream chat chunks fail schema
    # validation. Source: https://opencode.ai/docs/providers/
    npm = "@ai-sdk/openai-compatible";
    name = "OmniRoute";
    options = {
      baseURL = "https://omniroute.${publicBaseDomain}/v1";
      apiKey = self.secrets.OMNIROUTE_OPENCODE_API_KEY;

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
    omniroute = {
      inherit (unifiedProvider)
        npm
        name
        options
        models
        ;
    };
  };
}
