{
  lib,
  stdenv,
  fetchurl,
  buildPackages,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  dpkg,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  adwaita-icon-theme,
  gsettings-desktop-schemas,
  gtk3,
  gtk4,
  qt6,
  libx11,
  libxscrnsaver,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxrandr,
  libxrender,
  libxtst,
  libdrm,
  libkrb5,
  libuuid,
  libxkbcommon,
  libxshmfence,
  libgbm,
  nspr,
  nss,
  pango,
  pipewire,
  snappy,
  udev,
  wayland,
  xdg-utils,
  coreutils,
  libxcb,
  zlib,

  # Darwin dependencies
  unzip,
  makeWrapper,

  # Command-line arguments always appended to the browser wrapper.
  commandLineArgs ? "",

  # Keep PulseAudio enabled on Linux so USB/headset audio keeps working through
  # Chromium's bundled runtime. Source: upstream WitteShadovv/nixpkgs brave-origin.
  pulseSupport ? stdenv.hostPlatform.isLinux,
  libpulseaudio,

  # Needed for Chromium GPU acceleration on Wayland; without libGL in the rpath
  # the binary can start but fail hardware compositing on NixOS.
  libGL,

  # VA-API support is Linux-only and must be toggled together with Chromium
  # feature flags below. Source: https://github.com/brave/brave-browser/issues/20935
  libvaSupport ? stdenv.hostPlatform.isLinux,
  libva,
  enableVideoAcceleration ? libvaSupport,

  # Vulkan stays opt-in because upstream observed it can break VA-API decoding.
  # Source: upstream WitteShadovv/nixpkgs brave-origin make-brave.nix.
  vulkanSupport ? false,
  addDriverRunpath,
  enableVulkan ? vulkanSupport,
}:

{
  pname,
  version,
  archives,
}:

let
  inherit (lib)
    optional
    optionals
    makeLibraryPath
    makeSearchPathOutput
    makeBinPath
    optionalString
    strings
    escapeShellArg
    ;

  # Asset paths and app name mirror upstream release contents; do not derive
  # these from pname because the .deb uses brave-origin-nightly internally.
  # Source: https://github.com/brave/brave-browser/releases/tag/v1.91.90
  packagePath = "brave-origin-nightly";
  appName = "Brave Origin Nightly";

  deps = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    gtk4
    libdrm
    libx11
    libGL
    libxkbcommon
    libxscrnsaver
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxshmfence
    libxtst
    libuuid
    libgbm
    nspr
    nss
    pango
    pipewire
    udev
    wayland
    libxcb
    zlib
    snappy
    libkrb5
    qt6.qtbase
  ]
  ++ optional pulseSupport libpulseaudio
  ++ optional libvaSupport libva;

  rpath = makeLibraryPath deps + ":" + makeSearchPathOutput "lib" "lib64" deps;
  binpath = makeBinPath deps;

  enableFeatures =
    optionals enableVideoAcceleration [
      "AcceleratedVideoDecodeLinuxGL"
      "AcceleratedVideoEncoder"
    ]
    ++ optional enableVulkan "Vulkan";

  disableFeatures = [
    # Nix owns updates, so the browser should not flag the immutable packaged
    # binary as stale. Source: upstream WitteShadovv/nixpkgs brave-origin.
    "OutdatedBuildDetector"
  ]
  # Disabling ChromeOS direct decode avoids VA-API conflicts on Linux.
  # Source: https://github.com/brave/brave-browser/issues/20935
  ++ optionals enableVideoAcceleration [ "UseChromeOSDirectVideoDecoder" ];

  archive =
    assert lib.assertMsg (builtins.hasAttr stdenv.hostPlatform.system archives)
      "${pname} is not available for ${stdenv.hostPlatform.system}";
    archives.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  inherit pname version;

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchurl { inherit (archive) url hash; };

  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  doInstallCheck = stdenv.hostPlatform.isLinux;

  nativeBuildInputs =
    lib.optionals stdenv.hostPlatform.isLinux [
      dpkg
      # wrapGAppsHook3 supplies GTK/GSettings paths; use buildPackages' wrapper
      # to avoid splicing the wrong makeWrapper offset.
      # Source: https://github.com/NixOS/nixpkgs/issues/132651
      (buildPackages.wrapGAppsHook3.override {
        makeWrapper = buildPackages.makeShellWrapper;
      })
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      unzip
      makeWrapper
    ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    # These inputs are runtime data for wrapGAppsHook3, not compiler inputs.
    glib
    gsettings-desktop-schemas
    gtk3
    gtk4
    adwaita-icon-theme
  ];

  installPhase =
    lib.optionalString stdenv.hostPlatform.isLinux ''
      runHook preInstall

      mkdir -p $out $out/bin

      cp -R usr/share $out
      cp -R opt/ $out/opt

      export BINARYWRAPPER=$out/opt/brave.com/${packagePath}/${packagePath}

      substituteInPlace $BINARYWRAPPER \
          --replace-fail /bin/bash ${stdenv.shell} \
          --replace-fail 'CHROME_WRAPPER' 'WRAPPER'

      ln -sf $BINARYWRAPPER $out/bin/brave-origin

      for exe in $out/opt/brave.com/${packagePath}/{brave,chrome_crashpad_handler}; do
          patchelf \
              --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
              --set-rpath "${rpath}" $exe
      done

      substituteInPlace $out/share/applications/{brave-origin-nightly,com.brave.Origin.nightly}.desktop \
          --replace-fail /usr/bin/brave-origin-nightly $out/bin/brave-origin
      substituteInPlace $out/share/gnome-control-center/default-apps/brave-origin-nightly.xml \
          --replace-fail /opt/brave.com $out/opt/brave.com
      substituteInPlace $out/opt/brave.com/${packagePath}/default-app-block \
          --replace-fail /opt/brave.com $out/opt/brave.com

      # The .deb stores icons under /opt, but desktop environments search
      # hicolor themes under $out/share/icons on NixOS.
      icon_sizes=("16" "24" "32" "48" "64" "128" "256")

      for icon in ''${icon_sizes[*]}
      do
          mkdir -p $out/share/icons/hicolor/$icon\x$icon/apps
          ln -s $out/opt/brave.com/${packagePath}/product_logo_''${icon}_nightly.png $out/share/icons/hicolor/$icon\x$icon/apps/brave-origin-nightly.png
      done

      # Brave's default-app helper expects xdg-utils beside the browser tree;
      # symlinks keep those calls in the Nix store instead of /usr/bin.
      ln -sf ${xdg-utils}/bin/xdg-settings $out/opt/brave.com/${packagePath}/xdg-settings
      ln -sf ${xdg-utils}/bin/xdg-mime $out/opt/brave.com/${packagePath}/xdg-mime

      runHook postInstall
    ''
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      runHook preInstall

      mkdir -p $out/{Applications,bin}

      cp -r . "$out/Applications/${appName}.app"

      makeWrapper "$out/Applications/${appName}.app/Contents/MacOS/${appName}" $out/bin/brave-origin

      runHook postInstall
    '';

  preFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : ${rpath}
      --prefix PATH : ${binpath}
      --suffix PATH : ${
        lib.makeBinPath [
          xdg-utils
          coreutils
        ]
      }
      --set CHROME_WRAPPER ${pname}
      ${optionalString (enableFeatures != [ ]) ''
        --add-flags "--enable-features=${strings.concatStringsSep "," enableFeatures}\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+,WaylandWindowDecorations --enable-wayland-ime=true}}"
      ''}
      ${optionalString (disableFeatures != [ ]) ''
        --add-flags "--disable-features=${strings.concatStringsSep "," disableFeatures}"
      ''}
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto}}"
      ${optionalString vulkanSupport ''
        --prefix XDG_DATA_DIRS  : "${addDriverRunpath.driverLink}/share"
      ''}
      --add-flags ${escapeShellArg commandLineArgs}
    )
  '';

  installCheckPhase = ''
    # Call the real binary because the upstream shell wrapper hides loader errors.
    $out/opt/brave.com/${packagePath}/brave --version
  '';

  passthru.updateScript = ./update.sh;

  meta = {
    homepage = "https://brave.com/origin/linux/nightly/";
    description = "Privacy-oriented browser for desktop and laptop computers";
    changelog =
      "https://github.com/brave/brave-browser/blob/master/CHANGELOG_DESKTOP_ORIGIN.md#"
      + lib.replaceStrings [ "." ] [ "" ] version;
    longDescription = ''
      Brave Origin is Brave's experimental browser line for Desktop and Laptop
      computers. This package tracks the Nightly assets published by Brave.
    '';
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.mpl20;
    platforms = builtins.attrNames archives;
    mainProgram = "brave-origin";
  };
}
