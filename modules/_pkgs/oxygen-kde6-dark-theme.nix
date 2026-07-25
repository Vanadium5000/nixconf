{
  fetchFromGitLab,
  lib,
  stdenvNoCC,
  ...
}:

stdenvNoCC.mkDerivation rec {
  pname = "oxygen-kde6-dark-theme";
  version = "6.7.3";

  src = fetchFromGitLab {
    domain = "invent.kde.org";
    owner = "plasma";
    repo = "oxygen";
    rev = "v${version}";
    hash = "sha256-EcUA2XbLPLeiegCTqUgPV1YKOJXFpXnX2SXcH2QS2xE=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm644 color-schemes/OxygenDark.colors \
      $out/share/color-schemes/OxygenDark.colors

    mkdir -p $out/share/plasma/look-and-feel/org.kde.oxygendark
    cp -R lookandfeel/org.kde.oxygen/contents \
      $out/share/plasma/look-and-feel/org.kde.oxygendark/contents
    install -Dm644 lookandfeel/org.kde.oxygen/metadata.json \
      $out/share/plasma/look-and-feel/org.kde.oxygendark/metadata.json

    # Plasma requires the KPlugin Id to match the look-and-feel package
    # directory; upstream v6.7.3 ships the dark Oxygen variant as
    # org.kde.oxygen, while nixpkgs 26.05 still uses that id for the light
    # variant. Give the dark metadata a distinct id so both themes are
    # selectable without a system-path collision.
    # Source: https://invent.kde.org/plasma/oxygen/-/raw/v6.7.3/lookandfeel/CMakeLists.txt
    substituteInPlace $out/share/plasma/look-and-feel/org.kde.oxygendark/metadata.json \
      --replace-fail '"Id": "org.kde.oxygen"' '"Id": "org.kde.oxygendark"'

    runHook postInstall
  '';

  meta = {
    description = "KDE Plasma 6 Oxygen Dark global theme metadata and color scheme";
    homepage = "https://invent.kde.org/plasma/oxygen";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
}
