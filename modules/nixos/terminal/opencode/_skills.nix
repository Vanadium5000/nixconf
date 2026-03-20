{
  pkgs,
  self,
  lib,
  config,
}:
let
  skillPath = name: ".config/opencode/skill/${name}/SKILL.md";
in
{
  "${skillPath "gh_grep"}" = ''
    ---
    name: "gh_grep"
    description: "Fast AST-based regex search over public GitHub repositories"
    mcp:
      gh_grep:
        type: "remote"
        url: "https://mcp.grep.app/"
        enabled: true
        timeout: 20000
    ---

    # gh_grep

    Use this skill to quickly search over public GitHub repositories using AST-based regex matching.
  '';

  "${skillPath "context7"}" = ''
    ---
    name: "context7"
    description: "Advanced documentation index, useful for looking up up-to-date APIs"
    mcp:
      context7:
        type: "remote"
        url: "https://mcp.context7.com/mcp"
        enabled: true
        timeout: 20000
    ---

    # context7

    Use this skill to query an advanced, up-to-date documentation index for APIs and frameworks.
  '';

  "${skillPath "markdown_lint"}" = ''
    ---
    name: "markdown_lint"
    description: "Lints markdown files to ensure compliance with format standards"
    mcp:
      markdown_lint:
        type: "local"
        command: ["${
          self.packages.${pkgs.stdenv.hostPlatform.system}.markdown-lint-mcp
        }/bin/markdown-lint-mcp"]
        enabled: true
        timeout: 10000
    ---

    # markdown_lint

    Use this skill to validate markdown files against standard formatting rules.
  '';

  "${skillPath "qmllint"}" = ''
    ---
    name: "qmllint"
    description: "Validates Qt/QML syntax for NixOS widget configurations"
    mcp:
      qmllint:
        type: "local"
        command: ["${self.packages.${pkgs.stdenv.hostPlatform.system}.qmllint-mcp}/bin/qmllint-mcp"]
        enabled: true
        timeout: 20000
    ---

    # qmllint

    Use this skill to validate syntax and catch errors in Qt/QML files.
  '';

  "${skillPath "quickshell"}" = ''
    ---
    name: "quickshell"
    description: "Reads documentation for the custom Quickshell UI compositor"
    mcp:
      quickshell:
        type: "local"
        command: ["${
          self.packages.${pkgs.stdenv.hostPlatform.system}.quickshell-docs-mcp
        }/bin/quickshell-docs-mcp"]
        enabled: true
        timeout: 20000
    ---

    # quickshell

    Use this skill to query and read documentation related to Quickshell UI configuration.
  '';

  "${skillPath "powerpoint"}" = ''
    ---
    name: "powerpoint"
    description: "Create and manipulate PowerPoint presentations programmatically"
    mcp:
      powerpoint:
        type: "local"
        command: ["${
          self.packages.${pkgs.stdenv.hostPlatform.system}.powerpoint-mcp
        }/bin/ppt_mcp_server"]
        enabled: true
        timeout: 30000
    ---

    # powerpoint

    Use this skill to generate or edit PowerPoint (.pptx) presentations.
  '';

  "${skillPath "image_gen"}" = ''
    ---
    name: "image_gen"
    description: "Generates images via the primary image-capable model"
    mcp:
      image_gen:
        type: "local"
        command: ["${pkgs.writeShellScript "image-gen-mcp-wrapper" ''
          export CLIPROXYAPI_KEY="${self.secrets.CLIPROXYAPI_KEY}"
          IMAGE_MODEL="$(${pkgs.jq}/bin/jq -r '
            first(
              .providers
              | to_entries[]
              | .key as $provider
              | .value.models
              | to_entries[]
              | select(((.value.modalities.output // []) | index("image")) != null)
              | "\($provider)/\(.key)"
            ) // empty
          ' ${./models.json})"
          exec ${pkgs.bun}/bin/bun ${../../../nixos/scripts/bunjs/mcp/image-gen.ts}
        ''}"]
        enabled: true
        timeout: 60000
    ---

    # image_gen

    Use this skill to generate images based on textual descriptions using available generative models.
  '';

  "${skillPath "slide_preview"}" = ''
    ---
    name: "slide_preview"
    description: "Renders presentation slides to images for visual previewing"
    mcp:
      slide_preview:
        type: "local"
        command: ["${pkgs.writeShellScript "slide-preview-mcp-wrapper" ''
          export PATH="${
            pkgs.lib.makeBinPath [
              pkgs.libreoffice
              pkgs.poppler-utils
            ]
          }:$PATH"
          exec ${pkgs.bun}/bin/bun ${../../../nixos/scripts/bunjs/mcp/slide-preview.ts}
        ''}"]
        enabled: true
        timeout: 30000
    ---

    # slide_preview

    Use this skill to render presentation files into preview images for visual confirmation.
  '';
}
