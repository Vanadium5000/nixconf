{
  bun,
  coreutils,
  ffmpeg,
  lib,
  libnotify,
  mpc,
  qs-dmenu,
  writeShellApplication,
}:
writeShellApplication {
  name = "qs-music-local";
  runtimeInputs = [
    bun
    coreutils
    ffmpeg
    libnotify
    mpc
    qs-dmenu
  ];
  text = ''
    export QS_DMENU_IMAGES="''${QS_DMENU_IMAGES:-${qs-dmenu}/bin/qs-dmenu}"
    exec ${bun}/bin/bun run ${./music-local.ts} "$@"
  '';
  meta = {
    description = "Quickshell local music browser";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "qs-music-local";
    platforms = lib.platforms.linux;
  };
}
