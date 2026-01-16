{ pkgs, ... }:

pkgs.stdenv.mkDerivation (finalAttrs: rec {
  pname = "sideloader";
  version = "1.0-pre4";

  src = pkgs.fetchurl {
    url = "https://github.com/Dadoum/Sideloader/releases/download/1.0-pre4/sideloader-cli-x86_64-linux-gnu.zip";
    hash = "sha256-4ZPALWYaXXl69LRBhshlXQeKC/3kGb3quTTFE9Gntzc=";
  };

  buildInputs = with pkgs; [
    gcc-unwrapped
    glibc
    libimobiledevice
    libplist
    makeWrapper
    openssl
    unzip
  ];

  nativeBuildInputs = with pkgs; [ autoPatchelfHook ];

  unpackPhase = ''
    unzip $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp sideloader-cli-x86_64-linux-gnu $out/bin/sideloader
    chmod u+x $out/bin/sideloader

    wrapProgram $out/bin/sideloader \
      --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs}

    runHook postInstall
  '';
})
