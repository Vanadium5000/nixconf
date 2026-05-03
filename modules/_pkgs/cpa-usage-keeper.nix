{
  lib,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  pkg-config,
}:

let
  version = "1.3.2";
  src = fetchFromGitHub {
    owner = "Willxup";
    repo = "cpa-usage-keeper";
    rev = "v${version}";
    hash = "sha256-XzLufGRue4tCTEvlHe89yKC+sbBdqj7PFTYeJYd5CH8=";
  };

  web = buildNpmPackage {
    pname = "cpa-usage-keeper-web";
    inherit version src;

    sourceRoot = "${src.name}/web";
    npmDepsHash = "sha256-MHGGYiV4FY10niRYKOAi94Z9u8IwmVrEcOY+yxD93sk=";

    npmFlags = [ "--ignore-scripts" ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/cpa-usage-keeper/web
      cp -r dist $out/share/cpa-usage-keeper/web/dist
      runHook postInstall
    '';
  };
in
buildGoModule {
  pname = "cpa-usage-keeper";
  inherit version src;

  # Upstream's Docker build places Vite's production assets at /app/web/dist
  # beside the Go binary so static discovery works in packaged deployments.
  # Source: https://github.com/Willxup/cpa-usage-keeper/blob/v1.3.2/Dockerfile
  preBuild = ''
    cp -r ${web}/share/cpa-usage-keeper/web/dist web/dist
  '';

  vendorHash = "sha256-3adkU3/TjS+kzeD2fONzyfxjMzphtEtBn5QRs24TCMQ=";

  subPackages = [ "cmd/server" ];

  nativeBuildInputs = [ pkg-config ];

  # github.com/mattn/go-sqlite3 requires CGO; upstream Docker installs
  # build-base and builds with CGO_ENABLED=1 for the same reason.
  # Source: https://github.com/Willxup/cpa-usage-keeper/blob/v1.3.2/Dockerfile
  env.CGO_ENABLED = "1";

  postInstall = ''
    mv $out/bin/server $out/bin/cpa-usage-keeper
    mkdir -p $out/share/cpa-usage-keeper/web
    cp -r ${web}/share/cpa-usage-keeper/web/dist $out/share/cpa-usage-keeper/web/dist
    mkdir -p $out/bin/web
    ln -s $out/share/cpa-usage-keeper/web/dist $out/bin/web/dist
  '';

  meta = {
    description = "Persistent CLIProxyAPI usage storage and dashboard";
    homepage = "https://github.com/Willxup/cpa-usage-keeper";
    changelog = "https://github.com/Willxup/cpa-usage-keeper/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "cpa-usage-keeper";
    platforms = lib.platforms.linux;
  };
}
