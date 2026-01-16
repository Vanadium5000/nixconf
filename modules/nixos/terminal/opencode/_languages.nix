{ pkgs }:
let
  formatterBins = {
    alejandra = "${pkgs.alejandra}/bin/alejandra";
    biome = "${pkgs.biome}/bin/biome";
    oxfmt = "${pkgs.unstable.oxfmt}/bin/oxfmt";
    shfmt = "${pkgs.shfmt}/bin/shfmt";
  };

  lspBins = {
    biome = "${pkgs.biome}/bin/biome";
    marksman = "${pkgs.marksman}/bin/marksman";
    nil = "${pkgs.nil}/bin/nil";
    tailwindcss = "${pkgs.tailwindcss-language-server}/bin/tailwindcss-language-server";
  };
in
{
  packages = with pkgs; [
    biome
    marksman
    nil
    tailwindcss-language-server
    alejandra
    unstable.oxfmt
    shfmt
  ];

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
    biome = {
      command = [
        formatterBins.biome
        "format"
        "--stdin-file-path"
      ];
      extensions = [ "astro" ];
    };
    alejandra = {
      command = [
        formatterBins.alejandra
        "-q"
      ];
      extensions = [ "nix" ];
    };
  };

  lsp = {
    biome = {
      command = [
        lspBins.biome
        "lsp-proxy"
      ];
      extensions = [
        "js"
        "ts"
        "json"
        "jsx"
        "tsx"
      ];
    };
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
      ];
    };
  };
}
