{ inputs, ... }:
let
  # Stable is the default package universe. Edge AI/web gateway and fast-moving
  # GUI packages are routed through nixpkgs-unstable here so their package
  # files can stay normal callPackage derivations without ambient
  # `{ unstable, ... }` parameters.
  edgePackages = [
    "acp-chat"
    "cliproxyapi"
    # Limux's GTK Rust bindings require rustc >= 1.92; keep it on unstable
    # until the stable channel's Rust toolchain catches up.
    "omniroute"
    "openchamber-web"
    "limux"
  ];

  getPackages =
    {
      lib,
      stablePkgs,
      unstablePkgs ? stablePkgs.unstable,
    }:
    let
      entries = builtins.readDir ./_pkgs;

      # Only treat top-level .nix files as exported packages so support files can
      # live in nested directories without being misread as package attrs.
      files = builtins.filter (
        name:
        entries.${name} == "regular" && builtins.match ".*\\.nix" name != null && name != "default.nix"
      ) (builtins.attrNames entries);

      callPackageFor =
        name: if builtins.elem name edgePackages then unstablePkgs.callPackage else stablePkgs.callPackage;

      # Turn filename.nix → name = callPackage ./filename.nix {};
      toPackage =
        filename:
        let
          name = builtins.replaceStrings [ ".nix" ] [ "" ] filename;
        in
        {
          "${name}" = (callPackageFor name) (./_pkgs + "/${filename}") { };
        };

      paseoDesktop = inputs.llm-agents.packages.${stablePkgs.stdenv.hostPlatform.system}.paseo-desktop;
      paseoTerminalFontFamily = [
        "JetBrainsMono Nerd Font"
        "JetBrains Mono"
        "Symbols Nerd Font"
        "Noto Color Emoji"
        "Noto Sans Symbols 2"
        "Noto Sans Symbols"
        "Noto Sans"
        "monospace"
      ];
      paseoTerminalFontFamilyJson = builtins.toJSON (lib.concatStringsSep ", " paseoTerminalFontFamily);
      paseoTerminalFontPatch = stablePkgs.writeText "patch-paseo-terminal-font.py" ''
        import os
        import re
        from pathlib import Path

        root = Path(os.environ["out"]) / "share/paseo-desktop/packages/app/dist/_expo/static/js/web"
        replacement = ${paseoTerminalFontFamilyJson}
        patched = False
        for path in root.glob("index-*.js"):
            text = path.read_text(encoding="utf-8")
            new = f'const F={replacement!r};'
            text, count = re.subn(r'const F=\[[^;]+\]\.join\(", "\);(?=function E)', new, text, count=1)
            if count != 1:
                raise SystemExit(f"Paseo terminal font-family patch target not found in {path}")
            path.write_text(text, encoding="utf-8")
            patched = True
        if not patched:
            raise SystemExit(f"Paseo terminal bundle not found under {root}")
      '';
    in
    (builtins.foldl' (acc: filename: acc // (toPackage filename)) { } files)
    // {
      # Paseo's bundled xterm defaults to web/CSS monospace fallbacks, and Electron
      # does not match Kitty's font fallback stack. Force the embedded terminal to
      # see the same symbol-capable families so zsh/OMP/Nerd glyphs do not render
      # as tofu blocks. Source: @xterm/xterm Terminal option `fontFamily`.
      paseo = paseoDesktop.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          ${stablePkgs.python3}/bin/python3 ${paseoTerminalFontPatch}
        '';
      });
    };
in
{
  flake.overlays.customPackages = final: prev: {
    customPackages = getPackages {
      inherit (final) lib;
      stablePkgs = final;
      unstablePkgs = final.unstable;
    };
  };

  perSystem =
    { pkgs, ... }:
    {
      packages = getPackages {
        inherit (pkgs) lib;
        stablePkgs = pkgs;
        unstablePkgs = pkgs.unstable;
      };
    };
}
