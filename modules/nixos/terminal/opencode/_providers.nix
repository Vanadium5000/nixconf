{ self, lib, ... }:
let
  publicBaseDomain = self.secrets.PUBLIC_BASE_DOMAIN;
  # models.json is the reviewed cache written by opencode-models sync. It keeps
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
      limit = lib.optionalAttrs hasContext (
        {
          context = model.context or model.limit.context;
        }
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
      "output"
      "limit"
    ])
    // (lib.optionalAttrs (limit != { }) { inherit limit; });

  unifiedProvider = {
    # OpenCode documents @ai-sdk/openai for /v1/responses-backed providers.
    # Source: https://opencode.ai/docs/providers/
    npm = "@ai-sdk/openai";
    name = "OmniRoute";
    options = {
      baseURL = "https://omniroute.${publicBaseDomain}/v1";
      apiKey = self.secrets.OMNIROUTE_OPENCODE_API_KEY;
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
