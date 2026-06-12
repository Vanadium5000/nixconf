{
  bun,
  coreutils,
  lib,
  nodejs_latest,
  playerctl,
  writeShellApplication,
}:

writeShellApplication {
  name = "lyricsctl";
  runtimeInputs = [
    bun
    coreutils
    nodejs_latest
    playerctl
  ];
  text = ''
    exec ${bun}/bin/bun run ${../nixos/scripts/bunjs/synced-lyrics.ts} "$@"
  '';

  meta = {
    description = "Synced lyrics CLI, TUI, and shell-widget JSON source";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "lyricsctl";
    platforms = lib.platforms.linux;
  };
}
