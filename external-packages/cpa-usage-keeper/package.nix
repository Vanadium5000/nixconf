{
  lib,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  pkg-config,
}:

let
  version = "1.14.1";
  src = fetchFromGitHub {
    owner = "Willxup";
    repo = "cpa-usage-keeper";
    rev = "v${version}";
    hash = "sha256-8PffsHbl22+iyiiXrbUw96zeSTd20/C7esF9jPAl9o0=";
  };

  web = buildNpmPackage {
    pname = "cpa-usage-keeper-web";
    inherit version src;

    sourceRoot = "${src.name}/web";
    npmDepsHash = "sha256-bisxIQDHJ1Fc0nGjglJgD4cM+d2j0aVHxKlfwE6wRhU=";

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
  # Source: https://github.com/Willxup/cpa-usage-keeper/blob/v${version}/Dockerfile
  preBuild = ''
    rm -rf web/dist
    cp -r ${web}/share/cpa-usage-keeper/web/dist web/dist
  '';

  vendorHash = "sha256-aPHZro8Qwy5ptgudMgnfpcktwyVVZTi+XMrr0RTtl6k=";

  subPackages = [ "cmd/server" ];

  nativeBuildInputs = [ pkg-config ];

  # github.com/mattn/go-sqlite3 requires CGO; upstream Docker installs
  # build-base and builds with CGO_ENABLED=1 for the same reason.
  # Source: https://github.com/Willxup/cpa-usage-keeper/blob/v${version}/Dockerfile
  env.CGO_ENABLED = "1";

  postInstall = ''
    mv $out/bin/server $out/bin/cpa-usage-keeper
    mkdir -p $out/share/cpa-usage-keeper/web
    cp -r ${web}/share/cpa-usage-keeper/web/dist $out/share/cpa-usage-keeper/web/dist
    mkdir -p $out/bin/web
    ln -s $out/share/cpa-usage-keeper/web/dist $out/bin/web/dist
  '';

  passthru = {
    inherit web;
  };

  meta = {
    description = "Persistent CLIProxyAPI usage storage and dashboard";
    homepage = "https://github.com/Willxup/cpa-usage-keeper";
    changelog = "https://github.com/Willxup/cpa-usage-keeper/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "cpa-usage-keeper";
    platforms = lib.platforms.linux;
  };
}
