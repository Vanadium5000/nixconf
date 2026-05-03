{ self, lib, ... }:
let
  publicBaseDomain = self.secrets.PUBLIC_BASE_DOMAIN;
  # Keep the synced cache repo-owned so model metadata can be reviewed before
  # it becomes part of the generated OpenCode config.
  modelsFile = ./models.json;
  capabilityOverridesFile = ./_model-capability-overrides.json;
  capabilityOverrides =
    let
      exists = builtins.pathExists capabilityOverridesFile;
      content = if exists then builtins.readFile capabilityOverridesFile else "";
      isValid = exists && content != "" && content != " " && content != "{}";
    in
    if isValid then builtins.fromJSON content else { };

  # Load the dynamic models if the file exists and is valid, otherwise use empty providers
  dynamicData =
    let
      exists = builtins.pathExists modelsFile;
      content = if exists then builtins.readFile modelsFile else "";
      # fromJSON fails on empty string, we need to ensure it's at least {}
      isValid = exists && content != "" && content != " " && content != "{}";
      data = if isValid then builtins.fromJSON content else { };
    in
    data;

  unifiedProvider = {
    # OpenCode documents @ai-sdk/openai for /v1/responses-backed models; GPT-5.x
    # reasoning quality depends on Responses semantics rather than chat-only
    # compatibility. Source: https://opencode.ai/docs/providers/
    npm = "@ai-sdk/openai";
    name = "CliProxyApi";
    options = {
      baseURL = "https://cliproxyapi.${publicBaseDomain}/v1";
      apiKey = self.secrets.CLIPROXYAPI_KEY;
    };
    # Dynamic models stay the base layer so sync_models() remains authoritative
    # when upstream metadata is accurate.
    #
    # Repo-owned overrides are stored in JSON so both Nix evaluation and the
    # runtime opencode-models script can apply the same trusted corrections
    # without waiting for another rebuild.
    models =
      let
        baseModels = dynamicData.providers.cliproxyapi.models or { };
        # Only keep overrides for real synced model IDs; `? modelId` would check
        # for a literal attr named "modelId", so use hasAttr for dynamic keys.
        filteredOverrides = lib.filterAttrs (
          modelId: _: builtins.hasAttr modelId baseModels
        ) capabilityOverrides;
      in
      lib.recursiveUpdate baseModels filteredOverrides;
  };

  # Normalize the provider structure for OpenCode
  config = {
    cliproxyapi = {
      inherit (unifiedProvider) npm name options;
      models = builtins.mapAttrs (
        modelId: model:
        let
          limit =
            (lib.optionalAttrs (model ? context || (model ? limit && model.limit ? context)) {
              context = model.context or model.limit.context;
            })
            // (lib.optionalAttrs (model ? output || (model ? limit && model.limit ? output)) {
              output = model.output or model.limit.output;
            });
        in
        # Preserve OpenCode model schema fields from overrides (`reasoning`,
        # `options`, `variants`, `tool_call`, etc.) while normalising the old
        # flat token fields returned by earlier sync output into `limit`.
        (builtins.removeAttrs model [
          "context"
          "output"
        ])
        // (lib.optionalAttrs (limit != { }) { inherit limit; })
      ) unifiedProvider.models;
    };
  };
in
{
  inherit config;
}
