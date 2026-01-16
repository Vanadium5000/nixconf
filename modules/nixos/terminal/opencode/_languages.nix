{ pkgs, self }:
let
  formatterBins = {
    nixfmt = "${pkgs.nixfmt-rfc-style}/bin/nixfmt";
    oxfmt = "${pkgs.unstable.oxfmt}/bin/oxfmt";
    shfmt = "${pkgs.shfmt}/bin/shfmt";
  };

  lspBins = {
    marksman = "${pkgs.marksman}/bin/marksman";
    nil = "${pkgs.nil}/bin/nil";
    tailwindcss = "${pkgs.tailwindcss-language-server}/bin/tailwindcss-language-server";
    # typescript = "${pkgs.typescript-language-server}/bin/typescript-language-server";
    html = "${pkgs.vscode-langservers-extracted}/bin/vscode-html-language-server";
    css = "${pkgs.vscode-langservers-extracted}/bin/vscode-css-language-server";
    json = "${pkgs.vscode-langservers-extracted}/bin/vscode-json-language-server";
    eslint = "${pkgs.vscode-langservers-extracted}/bin/vscode-eslint-language-server";
  };
in
{
  packages =
    (with pkgs; [
      marksman
      nil
      tailwindcss-language-server
      alejandra
      unstable.oxfmt
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
    oxfmt = {
      command = [ formatterBins.oxfmt ];
      extensions = [
        "yaml"
        "js"
        "json"
        "jsx"
        "md"
        "ts"
        "tsx"
        "css"
        "html"
        "vue"
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
    nil = {
      command = [ lspBins.nil ];
      extensions = [ "nix" ];
    };
    marksman = {
      command = [ lspBins.marksman ];
      extensions = [ "md" ];
    };
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
    # Already included by default
    # typescript = {
    #   command = [
    #     lspBins.typescript
    #     "--stdio"
    #   ];
    #   extensions = [
    #     "ts"
    #     "tsx"
    #     "js"
    #     "jsx"
    #   ];
    # };
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
