{
  pkgs,
  opencode,
  languages,
  ...
}:
let
  opencodeEnv = pkgs.buildEnv {
    name = "opencode-env";
    paths = languages.packages ++ [
      pkgs.libreoffice
      pkgs.python3
      pkgs.stdenv.cc
      pkgs.gnumake
    ];
  };

  # Init script creates required cache/plugin directories before launching opencode.
  opencodeInitScript = pkgs.writeShellScript "opencode-init" ''
    mkdir -p "$HOME/.local/cache/opencode/node_modules/@opencode-ai"
    mkdir -p "$HOME/.config/opencode/node_modules/@opencode-ai"
    if [ -d "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" ]; then
      if [ ! -L "$HOME/.local/cache/opencode/node_modules/@opencode-ai/plugin" ]; then
        ln -sf "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" \
               "$HOME/.local/cache/opencode/node_modules/@opencode-ai/plugin"
      fi
    fi

    if command -v opencode-models >/dev/null 2>&1; then
      opencode-models sync-config >/dev/null 2>&1 || true
    fi

    exec ${opencode}/bin/opencode "$@"
  '';

  opencodeWrapped = pkgs.runCommand "opencode-wrapped" { buildInputs = [ pkgs.makeWrapper ]; } ''
    mkdir -p $out/bin
    makeWrapper ${opencodeInitScript} $out/bin/opencode \
      --prefix PATH : ${opencodeEnv}/bin \
      --set OPENCODE_LIBC ${pkgs.glibc}/lib/libc.so.6
  '';
in
{
  inherit opencodeEnv opencodeInitScript opencodeWrapped;
}
