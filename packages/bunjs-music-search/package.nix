{
  bun,
  coreutils,
  ffmpeg,
  lib,
  libnotify,
  mpc,
  qs-dmenu,
  yt-dlp,
  writeShellApplication,
}:
writeShellApplication {
  name = "qs-music-search";
  runtimeInputs = [
    bun
    coreutils
    ffmpeg
    libnotify
    mpc
    qs-dmenu
    yt-dlp
  ];
  text = ''
    export QS_DMENU_IMAGES="''${QS_DMENU_IMAGES:-${qs-dmenu}/bin/qs-dmenu}"
    exec ${bun}/bin/bun run ${./music-search.ts} "$@"
  '';
  meta = {
    description = "Quickshell online music search helper";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "qs-music-search";
    platforms = lib.platforms.linux;
  };
}
