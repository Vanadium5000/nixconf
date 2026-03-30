{ pkgs, self }:
let
  formatterBins = {
    clang-format = "${pkgs.clang-tools}/bin/clang-format";
    nixfmt = "${pkgs.nixfmt-rfc-style}/bin/nixfmt";
    prettier = "${pkgs.nodePackages.prettier}/bin/prettier";
    gofumpt = "${pkgs.gofumpt}/bin/gofumpt";
    ruff = "${pkgs.ruff}/bin/ruff";
    rustfmt = "${pkgs.rustfmt}/bin/rustfmt";
    shfmt = "${pkgs.shfmt}/bin/shfmt";
    sqlfluff = "${pkgs.sqlfluff}/bin/sqlfluff";
    stylua = "${pkgs.stylua}/bin/stylua";
    taplo = "${pkgs.taplo}/bin/taplo";
    typstyle = "${pkgs.typstyle}/bin/typstyle";
  };

  lspBins = {
    bash = "${pkgs.bash-language-server}/bin/bash-language-server";
    clangd = "${pkgs.clang-tools}/bin/clangd";
    cmake = "${pkgs.cmake-language-server}/bin/cmake-language-server";
    docker-compose = "${pkgs.docker-compose-language-service}/bin/docker-compose-langserver";
    dockerfile = "${pkgs.dockerfile-language-server}/bin/docker-langserver";
    nil = "${pkgs.nil}/bin/nil";
    basedpyright = "${pkgs.basedpyright}/bin/basedpyright-langserver";
    gopls = "${pkgs.gopls}/bin/gopls";
    marksman = "${pkgs.marksman}/bin/marksman";
    lua = "${pkgs.lua-language-server}/bin/lua-language-server";
    luau = "${pkgs.luau-lsp}/bin/luau-lsp";
    rust = "${pkgs.rust-analyzer}/bin/rust-analyzer";
    sql = "${pkgs.sqls}/bin/sqls";
    tailwindcss = "${pkgs.tailwindcss-language-server}/bin/tailwindcss-language-server";
    taplo = "${pkgs.taplo}/bin/taplo";
    texlab = "${pkgs.texlab}/bin/texlab";
    typst = "${pkgs.tinymist}/bin/tinymist";
    typescript = "${pkgs.typescript-language-server}/bin/typescript-language-server";
    html = "${pkgs.vscode-langservers-extracted}/bin/vscode-html-language-server";
    css = "${pkgs.vscode-langservers-extracted}/bin/vscode-css-language-server";
    json = "${pkgs.vscode-langservers-extracted}/bin/vscode-json-language-server";
    eslint = "${pkgs.vscode-langservers-extracted}/bin/vscode-eslint-language-server";
    yaml = "${pkgs.yaml-language-server}/bin/yaml-language-server";
  };
in
{
  packages =
    (with pkgs; [
      bash-language-server
      basedpyright
      clang-tools
      cmake-language-server
      docker-compose-language-service
      dockerfile-language-server
      gopls
      gofumpt
      lua-language-server
      luau-lsp
      marksman
      nodePackages.markdownlint-cli
      nixfmt-rfc-style
      nodePackages.prettier
      ruff
      rust-analyzer
      rustfmt
      shfmt
      sqlfluff
      sqls
      stylua
      tailwindcss-language-server
      taplo
      texlab
      tinymist
      vscode-langservers-extracted
      typescript-language-server
      typstyle
      yaml-language-server
      eslint_d
    ])
    ++ (with self.packages.${pkgs.stdenv.hostPlatform.system}; [ daisyui-mcp ]);

  formatter = {
    clang-format = {
      command = [
        formatterBins.clang-format
        "-i"
      ];
      extensions = [
        ".c"
        ".cc"
        ".cpp"
        ".cxx"
        ".h"
        ".hh"
        ".hpp"
        ".hxx"
      ];
    };
    gofumpt = {
      command = [
        formatterBins.gofumpt
        "-w"
      ];
      extensions = [ ".go" ];
    };
    shfmt = {
      command = [
        formatterBins.shfmt
        "-i"
        "2"
      ];
      extensions = [
        ".sh"
        ".bash"
        ".zsh"
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
        ".js" # JavaScript
        ".mjs" # ES modules
        ".cjs" # CommonJS modules
        ".jsx" # React JSX
        # TypeScript family
        ".ts" # TypeScript
        ".mts" # TypeScript ES modules
        ".cts" # TypeScript CommonJS modules
        ".tsx" # React TSX
        # CSS family
        ".css" # CSS
        ".scss" # SCSS
        ".less" # Less
        # HTML family
        ".html" # HTML
        ".htm" # HTML alternate extension
        ".vue" # Vue single-file components
        # Data formats
        ".json" # JSON
        ".json5" # JSON5
        ".jsonc" # JSON with Comments
        ".yaml" # YAML
        ".yml" # YAML alternate extension
        ".graphql" # GraphQL
        ".gql" # GraphQL alternate extension
        # Markdown
        ".md" # Markdown
        ".mdx" # MDX (Markdown + JSX)
        ".markdown" # Markdown alternate extension
      ];
    };
    nixfmt = {
      command = [
        formatterBins.nixfmt
        "-q"
      ];
      extensions = [ ".nix" ];
    };
    ruff = {
      command = [
        formatterBins.ruff
        "format"
        "$FILE"
      ];
      extensions = [
        ".py"
        ".pyi"
      ];
    };
    rustfmt = {
      command = [
        formatterBins.rustfmt
        "$FILE"
      ];
      extensions = [ ".rs" ];
    };
    sqlfluff = {
      command = [
        formatterBins.sqlfluff
        "fix"
        "--force"
        "$FILE"
      ];
      extensions = [ ".sql" ];
    };
    stylua = {
      command = [
        formatterBins.stylua
        "$FILE"
      ];
      extensions = [ ".lua" ];
    };
    taplo = {
      command = [
        formatterBins.taplo
        "format"
        "$FILE"
      ];
      extensions = [ ".toml" ];
    };
    typstyle = {
      command = [
        formatterBins.typstyle
        "--inplace"
        "$FILE"
      ];
      extensions = [ ".typ" ];
    };
  };

  lsp = {
    # nixd is already included
    # nil = {
    #   command = [ lspBins.nil ];
    #   extensions = [ ".nix" ];
    # };
    bash = {
      command = [
        lspBins.bash
        "start"
      ];
      extensions = [
        ".sh"
        ".bash"
        ".zsh"
      ];
    };
    clangd = {
      command = [ lspBins.clangd ];
      extensions = [
        ".c"
        ".cc"
        ".cpp"
        ".cxx"
        ".h"
        ".hh"
        ".hpp"
        ".hxx"
      ];
    };
    cmake = {
      command = [ lspBins.cmake ];
      extensions = [ ".cmake" ];
    };
    python = {
      command = [ lspBins.basedpyright ];
      extensions = [
        ".py"
        ".pyi"
      ];
    };
    go = {
      command = [ lspBins.gopls ];
      extensions = [ ".go" ];
    };
    tailwindcss = {
      command = [
        lspBins.tailwindcss
        "--stdio"
      ];
      extensions = [
        ".css"
        ".html"
        ".jsx"
        ".tsx"
        ".vue"
      ];
    };
    markdown = {
      command = [ lspBins.marksman ];
      extensions = [
        ".md"
        ".mdx"
        ".markdown"
      ];
    };
    typescript = {
      command = [
        lspBins.typescript
        "--stdio"
      ];
      extensions = [
        ".ts"
        ".tsx"
        ".js"
        ".jsx"
        ".mjs"
        ".cjs"
        ".mts"
        ".cts"
      ];
    };
    html = {
      command = [
        lspBins.html
        "--stdio"
      ];
      extensions = [
        ".html"
        ".htm"
      ];
    };
    css = {
      command = [
        lspBins.css
        "--stdio"
      ];
      extensions = [
        ".css"
        ".scss"
        ".less"
      ];
    };
    docker-compose = {
      command = [
        lspBins.docker-compose
        "--stdio"
      ];
      extensions = [
        ".compose.yaml"
        ".compose.yml"
      ];
    };
    dockerfile = {
      command = [
        lspBins.dockerfile
        "--stdio"
      ];
      extensions = [ ".dockerfile" ];
    };
    json = {
      command = [
        lspBins.json
        "--stdio"
      ];
      extensions = [
        ".json"
        ".jsonc"
        ".json5"
      ];
    };
    eslint = {
      command = [
        lspBins.eslint
        "--stdio"
      ];
      extensions = [
        ".js"
        ".jsx"
        ".ts"
        ".tsx"
        ".vue"
      ];
    };
    lua = {
      command = [ lspBins.lua ];
      extensions = [ ".lua" ];
    };
    luau = {
      command = [
        lspBins.luau
        "lsp" # luau-lsp uses the 'lsp' subcommand to start the language server
      ];
      extensions = [ ".luau" ];
    };
    rust = {
      command = [ lspBins.rust ];
      extensions = [ ".rs" ];
    };
    sql = {
      command = [ lspBins.sql ];
      extensions = [ ".sql" ];
    };
    taplo = {
      command = [
        lspBins.taplo
        "lsp"
        "stdio"
      ];
      extensions = [ ".toml" ];
    };
    texlab = {
      command = [ lspBins.texlab ];
      extensions = [
        ".tex"
        ".bib"
      ];
    };
    typst = {
      command = [ lspBins.typst ];
      extensions = [ ".typ" ];
    };
    yaml = {
      command = [
        lspBins.yaml
        "--stdio"
      ];
      extensions = [
        ".yaml"
        ".yml"
      ];
    };
  };
}
