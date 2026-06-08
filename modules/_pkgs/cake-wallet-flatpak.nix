{
  lib,
  fetchurl,
  stdenvNoCC,
}:
let
  pname = "cake-wallet-flatpak";
  version = "6.2.0";
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  src = fetchurl {
    # Upstream ships Cake Wallet as a standalone Flatpak bundle on GitHub
    # releases rather than a Flathub-published app, so we package the bundle
    # itself and let the desktop Flatpak module install it declaratively.
    url = "https://github.com/cake-tech/cake_wallet/releases/download/v${version}/Cake_Wallet_v${version}_Linux.flatpak";
    hash = "sha256-GBybiogmaL+3mDxjRQuhqwtVEgx4UOqigwpWHR8iEq4=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm644 "$src" "$out/share/cake-wallet/Cake_Wallet.flatpak"

    runHook postInstall
  '';

  meta = {
    description = "Upstream Cake Wallet Flatpak bundle";
    homepage = "https://cakewallet.com/";
    downloadPage = "https://github.com/cake-tech/cake_wallet/releases";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    platforms = [ "x86_64-linux" ];
  };
}
