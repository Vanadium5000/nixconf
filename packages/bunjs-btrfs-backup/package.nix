{
  bash,
  btrfs-progs,
  bun,
  coreutils,
  findutils,
  gnused,
  lib,
  libnotify,
  util-linux,
  wofi,
  which,
  writeShellApplication,
}:
writeShellApplication {
  name = "btrfs-backup";
  runtimeInputs = [
    bash
    btrfs-progs
    bun
    coreutils
    findutils
    gnused
    libnotify
    util-linux
    wofi
    which
  ];
  text = ''
    if [ "$(id -u)" -ne 0 ]; then
      exec pkexec env \
        HOST="$HOST" \
        WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
        XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        DISPLAY="$DISPLAY" \
        ${bun}/bin/bun run ${./btrfs-backup.ts} "$@"
    fi

    exec ${bun}/bin/bun run ${./btrfs-backup.ts} "$@"
  '';
  meta = {
    description = "Interactive Btrfs backup helper";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "btrfs-backup";
    platforms = lib.platforms.linux;
  };
}
