{ self, lib, ... }:
let
  publicBaseDomain = self.secrets.PUBLIC_BASE_DOMAIN;
  # models.json is the reviewed cache written by opencode-models sync. It keeps
  # upstream metadata local while the provider config uses the same model IDs.
  modelsFile = ./models.json;
  # Local patches are reserved for repo policy that the API cannot know, such as
  # preferred labels or OpenCode-specific options. Source data belongs in models.json.
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
      limit =
        (lib.optionalAttrs (model ? context || (model ? limit && model.limit ? context)) {
          context = model.context or model.limit.context;
        })
        // (lib.optionalAttrs (model ? output || (model ? limit && model.limit ? output)) {
          output = model.output or model.limit.output;
        });
    in
    # OpenCode accepts fields such as reasoning, reasoning_effort, tool_call,
    # modalities, options, and variants; old flat token fields are normalized to
    # limit for compatibility with pre-rich-sync caches.
    (builtins.removeAttrs model [
      "context"
      "output"
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
