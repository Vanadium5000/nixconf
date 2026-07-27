{
  bun,
  coreutils,
  curl,
  lib,
  libcanberra-gtk3,
  libnotify,
  writeShellApplication,
}:
writeShellApplication {
  name = "pomodoro";
  runtimeInputs = [
    bun
    coreutils
    curl
    libcanberra-gtk3
    libnotify
  ];
  text = ''
    exec ${bun}/bin/bun run ${./pomodoro.ts} "$@"
  '';
  meta = {
    description = "Pomodoro timer CLI";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "pomodoro";
    platforms = lib.platforms.linux;
  };
}
