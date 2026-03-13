{ self, lib, ... }:
let
  # Path to the dynamic model cache
  # This file is updated by 'opencode-models sync' in the repo
  modelsFile = ./models.json;

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

  # Minimal static fallback for the unified provider
  unifiedProvider = {
    npm = "@ai-sdk/openai-compatible";
    name = "CliProxyApi";
    options = {
      baseURL = "http://127.0.0.1:8317/v1";
      apiKey = self.secrets.CLIPROXYAPI_KEY;
    };
    # Merge all models from dynamic data into a single flat set
    # Dynamic data might have separate provider buckets, we flatten them
    models = (dynamicData.providers.cliproxyapi.models or { }) // {
      "gemini-3-flash" = {
        name = "Gemini 3 Flash";
        limit = {
          context = 1048576;
          output = 65536;
        };
        modalities = {
          input = [
            "text"
            "image"
            "video"
          ];
          output = [ "text" ];
        };
      };
    };
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
        {
          inherit (model) name;
        }
        // (if model ? modalities then { inherit (model) modalities; } else { })
        // (lib.optionalAttrs (limit != { }) { inherit limit; })
      ) unifiedProvider.models;
    };
  };
in
{
  inherit config;
}
