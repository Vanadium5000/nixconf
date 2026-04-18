{
  pkgs,
  lib,
  initialConfig,
  ohMyOpencodeConfig,
  opencodeModelsMetadata,
  mcpConfig,
  ...
}:
let
  # Define project MCP templates with rich comments for JSONC output.
  mcpTemplates =
    let
      allMcpNames = lib.attrNames mcpConfig;

      mkTemplateJsonC =
        _: enabledMcpNames:
        let
          globallyEnabledNotInTemplate = lib.filterAttrs (
            name: cfg: (cfg.enabled or false) && !(builtins.elem name enabledMcpNames)
          ) mcpConfig;

          availableNotInTemplate = lib.filterAttrs (
            name: cfg: !(builtins.elem name enabledMcpNames) && !(cfg.enabled or false)
          ) mcpConfig;

          globalNames = lib.attrNames globallyEnabledNotInTemplate;
          availableNames = lib.attrNames availableNotInTemplate;
          allDataNames = globalNames ++ availableNames ++ enabledMcpNames;
          lastIdx = lib.length allDataNames - 1;

          mkLine =
            i: text:
            let
              comma = if i == lastIdx then "" else ",";
            in
            "    ${text}${comma}";

          globalSection =
            if globalNames == [ ] then
              [ ]
            else
              [ "    // Globally enabled by default - disable if not needed" ]
              ++ (lib.imap0 (i: name: mkLine i "// \"${name}\": { \"enabled\": false }") globalNames);

          availableSection =
            if availableNames == [ ] then
              [ ]
            else
              [ "    // Available: uncomment to enable" ]
              ++ (lib.imap0 (
                i: name: mkLine (i + lib.length globalNames) "// \"${name}\": { \"enabled\": true }"
              ) availableNames);

          enabledSection = lib.imap0 (
            i: name:
            mkLine (i + lib.length globalNames + lib.length availableNames) "\"${name}\": { \"enabled\": true }"
          ) enabledMcpNames;

          result =
            globalSection
            ++ lib.optional (globalSection != [ ] && (availableSection != [ ] || enabledSection != [ ])) ""
            ++ availableSection
            ++ lib.optional (availableSection != [ ] && enabledSection != [ ]) ""
            ++ enabledSection;
        in
        "{\n  \"mcp\": {\n${lib.concatStringsSep "\n" result}\n  }\n}";
    in
    {
      "All MCPs" = mkTemplateJsonC "All MCPs" allMcpNames;
      "No MCPs" = mkTemplateJsonC "No MCPs" [ ];
      "Custom MCP File" = mkTemplateJsonC "Custom MCP File" [ ];
    };

  runtimeConfigDir = pkgs.runCommand "opencode-runtime-configs" { } ''
    mkdir -p $out
    cat > "$out/opencode-base.json" <<'EOF'
    ${builtins.toJSON initialConfig}
    EOF
    cat > "$out/oh-my-opencode-base.json" <<'EOF'
    ${builtins.toJSON ohMyOpencodeConfig}
    EOF
    cat > "$out/opencode-models-metadata.json" <<'EOF'
    ${builtins.toJSON opencodeModelsMetadata}
    EOF
  '';

  # Store templates in the Nix store for rapid switching.
  configVariantsDir = pkgs.runCommand "opencode-configs" { } ''
    mkdir -p $out/templates
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: value:
        let
          safeName = lib.replaceStrings [ " " "/" ] [ "_" "_" ] name;
        in
        ''
          cat > "$out/templates/${safeName}.json" << 'EOF'
          ${value}
          EOF
        ''
      ) mcpTemplates
    )}
  '';

  stateAssetsDir = pkgs.runCommand "opencode-state-assets" { } ''
    mkdir -p "$out"
    cp ${./models.json} "$out/models.json"
    cp ${./state.json} "$out/state.json"
    cp ${./presets.json} "$out/presets.json"
  '';
in
{
  inherit
    configVariantsDir
    mcpTemplates
    runtimeConfigDir
    stateAssetsDir
    ;
}
