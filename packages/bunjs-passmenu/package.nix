{
  bun,
  buildNpmPackage,
  coreutils,
  findutils,
  gnupg,
  importNpmLock,
  lib,
  libnotify,
  pass,
  qs-dmenu,
  wl-clipboard,
  wofi,
  wtype,
  which,
  writeShellApplication,
  ydotool,
}:
let
  src = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _type:
      !(builtins.elem (baseNameOf path) [
        "node_modules"
        ".bun"
      ]);
  };
  bundle = buildNpmPackage {
    pname = "bunjs-passmenu-bundle";
    version = "0-unstable";
    inherit src;
    npmDeps = importNpmLock { npmRoot = src; };
    npmConfigHook = importNpmLock.npmConfigHook;
    nativeBuildInputs = [ bun ];
    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      bun build --target=bun --outfile=passmenu.js passmenu.ts
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm444 passmenu.js "$out/share/bunjs-passmenu/passmenu.js"
      runHook postInstall
    '';
  };
in
writeShellApplication {
  name = "qs-passmenu";
  runtimeInputs = [
    bun
    coreutils
    findutils
    gnupg
    libnotify
    (pass.withExtensions (exts: [ exts.pass-otp ]))
    qs-dmenu
    wl-clipboard
    wofi
    wtype
    which
    ydotool
  ];
  text = ''
    exec ${bun}/bin/bun ${bundle}/share/bunjs-passmenu/passmenu.js "$@"
  '';
  meta = {
    description = "Quickshell pass menu and credential generator";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "qs-passmenu";
    platforms = lib.platforms.linux;
  };
}
