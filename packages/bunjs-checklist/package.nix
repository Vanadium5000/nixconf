{
  bun,
  coreutils,
  findutils,
  gnused,
  lib,
  libnotify,
  wofi,
  which,
  writeShellApplication,
}:
writeShellApplication {
  name = "qs-checklist";
  runtimeInputs = [
    bun
    coreutils
    findutils
    gnused
    libnotify
    wofi
    which
  ];
  text = ''
    exec ${bun}/bin/bun run ${./checklist.ts} "$@"
  '';
  meta = {
    description = "Quickshell daily checklist CLI";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "qs-checklist";
    platforms = lib.platforms.linux;
  };
}
