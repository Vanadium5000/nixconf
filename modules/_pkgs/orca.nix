{
  lib,
  stdenv,
  fetchurl,
  buildPackages,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  autoPatchelfHook,
  bashInteractive,
  cairo,
  coreutils,
  cups,
  dbus,
  dpkg,
  expat,
  fontconfig,
  freetype,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libglvnd,
  libnotify,
  libsecret,
  libuuid,
  libx11,
  libxscrnsaver,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxtst,
  libxcb,
  libxshmfence,
  nspr,
  nss,
  pango,
  trash-cli,
  udev,
  wayland,
  xdg-utils,
  commandLineArgs ? "",
  ...
}:

stdenv.mkDerivation rec {
  pname = "orca";
  version = "1.4.89";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-ide_${version}_amd64.deb";
    hash = "sha256-N6GFaQeayxZOuOQG6Bp1t5WHRS7nfBNLl2UxijKGemg=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    # Electron-builder emits GTK/GSettings-aware launchers; use the build
    # wrapper to avoid the wrong spliced makeWrapper in propagated inputs.
    # Source: nixpkgs pkgs/applications/editors/vscode/generic.nix.
    (buildPackages.wrapGAppsHook3.override { makeWrapper = buildPackages.makeShellWrapper; })
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    glib
    gtk3
    libdrm
    libgbm
    libglvnd
    libnotify
    libsecret
    libuuid
    libxkbcommon
    nspr
    nss
    pango
    udev
    wayland
    libx11
    libxscrnsaver
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxtst
    libxcb
    libxshmfence
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -R opt usr/share $out/

    chmod +x $out/opt/Orca/orca-ide \
      $out/opt/Orca/chrome_crashpad_handler \
      $out/opt/Orca/chrome-sandbox \
      $out/opt/Orca/resources/agent-browser-linux-x64
    chmod +x $out/opt/Orca/resources/bin/orca-ide

    substituteInPlace $out/opt/Orca/resources/bin/orca-ide \
      --replace-fail '#!/usr/bin/env bash' '#!${bashInteractive}/bin/bash'

    substituteInPlace $out/share/applications/orca-ide.desktop \
      --replace-fail /opt/Orca/orca-ide $out/bin/orca-ide

    ln -s $out/opt/Orca/orca-ide $out/bin/orca-ide
    ln -s $out/bin/orca-ide $out/bin/orca

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          trash-cli
          xdg-utils
        ]
      }
      # Electron's Linux shell.trashItem picks kioclient5 on KDE-like sessions;
      # that binary is absent from this lightweight package closure on NixOS.
      # Force the documented trash-cli backend instead. Ref: user log
      # "LaunchProcess: failed to execvp: kioclient5" and Electron
      # shell/common/platform_util_linux.cc MoveItemToTrash.
      --set ELECTRON_TRASH trash-cli
      # Orca's PTY daemon resolves `env.SHELL || process.env.SHELL || /bin/zsh`;
      # desktop launches on NixOS can omit SHELL, and `/bin/zsh` does not exist.
      # Source: resources/app.asar.unpacked/out/main/chunks/headless-emulator-*.js.
      --run ${lib.escapeShellArg ''[ -x "''${SHELL:-}" ] || export SHELL=${bashInteractive}/bin/bash''}
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
      --add-flags ${lib.escapeShellArg commandLineArgs}
    )
  '';

  postFixup = ''
    patchelf \
      --add-needed ${libglvnd}/lib/libGLESv2.so.2 \
      --add-needed ${libglvnd}/lib/libGL.so.1 \
      --add-needed ${libglvnd}/lib/libEGL.so.1 \
      $out/opt/Orca/orca-ide
  '';

  meta = {
    description = "IDE for orchestrating AI coding agents across terminals and worktrees";
    homepage = "https://github.com/stablyai/orca";
    downloadPage = "https://github.com/stablyai/orca/releases";
    changelog = "https://github.com/stablyai/orca/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "orca";
  };
}
