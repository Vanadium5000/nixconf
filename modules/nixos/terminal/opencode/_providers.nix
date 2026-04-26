{ self, lib, ... }:
let
  # Path to the dynamic model cache
  # This file is updated by 'opencode-models sync' in the repo
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
    npm = "@ai-sdk/openai-compatible";
    name = "CliProxyApi";
    options = {
      baseURL = "http://127.0.0.1:8317/v1";
      apiKey = self.secrets.CLIPROXYAPI_KEY;
    };
    # Dynamic models stay the base layer so sync_models() remains authoritative
    # when upstream metadata is accurate.
    #
    # Repo-owned overrides are stored in JSON so both Nix evaluation and the
    # runtime opencode-models script can apply the same trusted corrections
    # without waiting for another rebuild.
    models = lib.recursiveUpdate (dynamicData.providers.cliproxyapi.models or { }) capabilityOverrides;
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
        (
          {
            inherit (model) name;
          }
          // (if model ? modalities then { inherit (model) modalities; } else { })
          // (lib.optionalAttrs (limit != { }) { inherit limit; })
        )
      ) unifiedProvider.models;
    };
  };
in
{
  inherit config;
}
