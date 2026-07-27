{
  bun,
  coreutils,
  git,
  gnupg,
  lib,
  openssh,
  pinentry-qt,
  which,
  writeShellApplication,
}:
writeShellApplication {
  name = "git-sync-debug";
  runtimeInputs = [
    bun
    coreutils
    git
    gnupg
    openssh
    pinentry-qt
    which
  ];
  text = ''
    exec ${bun}/bin/bun run ${./git-sync-debug.ts} "$@"
  '';
  meta = {
    description = "Git sync authentication diagnostics";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "git-sync-debug";
    platforms = lib.platforms.linux;
  };
}
