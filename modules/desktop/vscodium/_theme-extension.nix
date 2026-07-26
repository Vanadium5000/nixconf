{
  lib,
  stdenv,
  _theme ? import ./_theme.nix,
  colors,
  ...
}:

let
  theme = _theme colors;
  themeJson = theme // {
    name = "Nix Cyberpunk Electric Dark";
  };

  extensionName = "nix-cyberpunk-electric-dark-theme";
  extensionVersion = "1.0.0";
  publisher = "custom";

  packageJson = {
    name = extensionName;
    displayName = "Nix Cyberpunk Electric Dark Theme";
    description = "A custom dark theme for VS Code based on Nix Cyberpunk Electric colors";
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
          label = "Nix Cyberpunk Electric Dark";
          uiTheme = "vs-dark";
          path = "./themes/Nix Cyberpunk Electric Dark-color-theme.json";
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
    cat > $out/share/vscode/extensions/${publisher}.${extensionName}-${extensionVersion}/themes/Nix\ Cyberpunk\ Electric\ Dark-color-theme.json <<EOF
    ${builtins.toJSON {
      inherit (themeJson)
        "$schema"
        name
        type
        colors
        tokenColors
        ;
    }}
    EOF
  '';

  meta = with lib; {
    description = "Custom VS Code theme based on Nix Cyberpunk Electric Dark colors";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
