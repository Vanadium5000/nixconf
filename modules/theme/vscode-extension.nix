{
  lib,
  stdenv,
  renderTheme ? import ./vscode-theme.nix,
  theme,
}:

let
  themeJson = renderTheme (theme.colors // { inherit (theme) scheme; });

  extensionName = "nixconf-${lib.toLower (lib.replaceStrings [ " " ] [ "-" ] theme.scheme)}-theme";
  extensionVersion = "1.0.0";
  publisher = "custom";

  packageJson = {
    name = extensionName;
    displayName = theme.name;
    description = "Nix-declared ${theme.type} colour theme";
    version = extensionVersion;
    publisher = publisher;
    engines = {
      vscode = "^1.74.0";
    };
    categories = [
      "Themes"
    ];
    contributes = {
      themes = [
        {
          label = theme.name;
          uiTheme = if theme.type == "dark" then "vs-dark" else "vs";
          path = "./themes/${theme.scheme}-color-theme.json";
        }
      ];
    };
  };
in

stdenv.mkDerivation {
  pname = extensionName;
  version = extensionVersion;

  vscodeExtUniqueId = "${publisher}.${extensionName}-${extensionVersion}";
  vscodeExtPublisher = publisher;

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/share/vscode/extensions/${publisher}.${extensionName}-${extensionVersion}

    # Create package.json
    cat > $out/share/vscode/extensions/${publisher}.${extensionName}-${extensionVersion}/package.json <<EOF
    ${builtins.toJSON packageJson}
    EOF

    # Create themes directory and theme file
    mkdir -p $out/share/vscode/extensions/${publisher}.${extensionName}-${extensionVersion}/themes
    cat > $out/share/vscode/extensions/${publisher}.${extensionName}-${extensionVersion}/themes/${theme.scheme}-color-theme.json <<EOF
    ${builtins.toJSON {
      inherit (themeJson)
        "$schema"
        colors
        tokenColors
        ;
      name = theme.name;
      type = theme.type;
    }}
    EOF
  '';

  meta = with lib; {
    description = "Custom VS Code theme generated from the Nix theme registry";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
