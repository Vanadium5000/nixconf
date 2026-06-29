{ lib }:
let
  inherit (lib) concatMapStringsSep;

  environment = {
    BUN_INSTALL = "$HOME/.bun";
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    PNPM_HOME = "$HOME/.local/share/pnpm";
  };

  pathEntries = [
    "$BUN_INSTALL/bin"
    "$HOME/.cache/.bun/bin"
    "$HOME/.cache/.bun/install/global/node_modules/.bin"
    "$NPM_CONFIG_PREFIX/bin"
    "$HOME/.npm/bin"
    "$HOME/.local/share/npm/bin"
    "$PNPM_HOME"
    "$HOME/.yarn/bin"
    "$HOME/.config/yarn/global/node_modules/.bin"
    "$HOME/.local/bin"
  ];

  zshPathEntries = concatMapStringsSep "\n" (entry: ''"${entry}"'') pathEntries;
in
{
  inherit environment pathEntries;

  cacheDirectories = [
    ".bun"
    ".npm"
    ".npm-global"
    ".local/share/npm"
    ".local/share/pnpm"
    ".yarn"
    ".config/yarn"
    ".cache/.bun"
  ];

  zshSetup = ''
    # User-scoped package manager CLIs.
    # Keep mutable global installs out of the Nix store while exposing common
    # per-user bins; env defaults mirror npm prefix, Bun install, and pnpm home
    # docs. Sources: https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally,
    # https://bun.sh/docs/installation, https://pnpm.io/cli/setup.
    export BUN_INSTALL="''${BUN_INSTALL:-${environment.BUN_INSTALL}}"
    export PNPM_HOME="''${PNPM_HOME:-${environment.PNPM_HOME}}"
    export NPM_CONFIG_PREFIX="''${NPM_CONFIG_PREFIX:-${environment.NPM_CONFIG_PREFIX}}"

    typeset -U path PATH
    path=(
    ${zshPathEntries}
      $path
    )
    export PATH
  '';
}
