{ pkgs, self }:
let
  formatterBins = {
    nixfmt = "${pkgs.nixfmt-rfc-style}/bin/nixfmt";
    prettier = "${pkgs.nodePackages.prettier}/bin/prettier";
    shfmt = "${pkgs.shfmt}/bin/shfmt";
  };

  lspBins = {
    nil = "${pkgs.nil}/bin/nil";
    tailwindcss = "${pkgs.tailwindcss-language-server}/bin/tailwindcss-language-server";
    typescript = "${pkgs.typescript-language-server}/bin/typescript-language-server";
    html = "${pkgs.vscode-langservers-extracted}/bin/vscode-html-language-server";
    css = "${pkgs.vscode-langservers-extracted}/bin/vscode-css-language-server";
    json = "${pkgs.vscode-langservers-extracted}/bin/vscode-json-language-server";
    eslint = "${pkgs.vscode-langservers-extracted}/bin/vscode-eslint-language-server";
  };
in
{
  packages =
    (with pkgs; [
      nodePackages.markdownlint-cli
      # nil
      tailwindcss-language-server
      nixfmt-rfc-style
      nodePackages.prettier
      shfmt
      vscode-langservers-extracted
      typescript-language-server
      eslint_d
    ])
    ++ (with self.packages.${pkgs.stdenv.hostPlatform.system}; [ daisyui-mcp ]);

  formatter = {
    shfmt = {
      command = [
        formatterBins.shfmt
        "-i"
        "2"
      ];
      extensions = [
        "sh"
        "bash"
      ];
    };
    prettier = {
      command = [
        formatterBins.prettier
        "--write" # Format file in-place
        "$FILE" # OpenCode replaces $FILE with actual path
      ];
      extensions = [
        # JavaScript family
        "js" # JavaScript
        "mjs" # ES modules
        "cjs" # CommonJS modules
        "jsx" # React JSX
        # TypeScript family
        "ts" # TypeScript
        "mts" # TypeScript ES modules
        "cts" # TypeScript CommonJS modules
        "tsx" # React TSX
        # CSS family
        "css" # CSS
        "scss" # SCSS
        "less" # Less
        # HTML family
        "html" # HTML
        "htm" # HTML alternate extension
        "vue" # Vue single-file components
        # Data formats
        "json" # JSON
        "json5" # JSON5
        "jsonc" # JSON with Comments
        "yaml" # YAML
        "yml" # YAML alternate extension
        "graphql" # GraphQL
        "gql" # GraphQL alternate extension
        # Markdown
        "md" # Markdown
        "mdx" # MDX (Markdown + JSX)
        "markdown" # Markdown alternate extension
      ];
    };
    nixfmt = {
      command = [
        formatterBins.nixfmt
        "-q"
      ];
      extensions = [ "nix" ];
    };
  };

  lsp = {
    # nixd is already included
    # nil = {
    #   command = [ lspBins.nil ];
    #   extensions = [ "nix" ];
    # };
    tailwindcss = {
      command = [
        lspBins.tailwindcss
        "--stdio"
      ];
      extensions = [
        "css"
        "html"
        "jsx"
        "tsx"
      ];
    };
    typescript = {
      command = [
        lspBins.typescript
        "--stdio"
      ];
      extensions = [
        "ts"
        "tsx"
        "js"
        "jsx"
      ];
    };
    html = {
      command = [
        lspBins.html
        "--stdio"
      ];
      extensions = [ "html" ];
    };
    css = {
      command = [
        lspBins.css
        "--stdio"
      ];
      extensions = [ "css" ];
    };
    json = {
      command = [
        lspBins.json
        "--stdio"
      ];
      extensions = [ "json" ];
    };
    eslint = {
      command = [
        lspBins.eslint
        "--stdio"
      ];
      extensions = [
        "js"
        "jsx"
        "ts"
        "tsx"
        "vue"
      ];
    };
  };
}
