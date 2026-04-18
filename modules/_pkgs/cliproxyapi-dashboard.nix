{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeBinaryWrapper,
  nodejs,
  prisma-engines_7,
}:

buildNpmPackage (finalAttrs: {
  pname = "cliproxyapi-dashboard";
  version = "0.1.77";

  src = fetchFromGitHub {
    owner = "itsmylife44";
    repo = "cliproxyapi-dashboard";
    rev = "dashboard-v${finalAttrs.version}";
    hash = "sha256-Y31DyYhs5z0vfxuMufs62sZd1SyEDX5nbZPB3/pPDLI=";
  };

  sourceRoot = "source/dashboard";

  npmDepsHash = "sha256-8aYAaLrRt+U+oC5TEwIDoWma1NteYSLh5U3TrcRy1/s=";

  nativeBuildInputs = [ makeBinaryWrapper ];

  # Upstream's Next.js build emits a standalone server bundle, so packaging the
  # compiled output keeps runtime use reproducible and avoids requiring a mutable
  # source checkout. Ref: upstream dashboard/next.config.ts.
  env = {
    NEXT_TELEMETRY_DISABLED = "1";
    DATABASE_URL = "postgresql://build:build@localhost:5432/build";
    JWT_SECRET = "build-time-placeholder-at-least-32-chars";
    MANAGEMENT_API_KEY = "build-time-placeholder-16ch";
    CLIPROXYAPI_MANAGEMENT_URL = "http://127.0.0.1:8317/v0/management";
    # Prisma generate runs during the build, and Nix builds cannot fetch engine
    # binaries from prisma.sh. Pointing Prisma at nixpkgs-provided engines keeps
    # the build fully offline and reproducible.
    PRISMA_SCHEMA_ENGINE_BINARY = "${prisma-engines_7}/bin/schema-engine";
    PRISMA_QUERY_ENGINE_BINARY = "${prisma-engines_7}/bin/query-engine";
    PRISMA_QUERY_ENGINE_LIBRARY = "${prisma-engines_7}/lib/libquery_engine.node";
    PRISMA_INTROSPECTION_ENGINE_BINARY = "${prisma-engines_7}/bin/introspection-engine";
    PRISMA_FMT_BINARY = "${prisma-engines_7}/bin/prisma-fmt";
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/cliproxyapi-dashboard/.next

    cp -r .next/standalone/* $out/share/cliproxyapi-dashboard/
    cp -r .next/static $out/share/cliproxyapi-dashboard/.next/
    cp -r public $out/share/cliproxyapi-dashboard/
    cp -r messages $out/share/cliproxyapi-dashboard/

    if [ -d src/generated ]; then
      mkdir -p $out/share/cliproxyapi-dashboard/src
      cp -r src/generated $out/share/cliproxyapi-dashboard/src/
    fi

    if [ -d prisma ]; then
      cp -r prisma $out/share/cliproxyapi-dashboard/
    fi

    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/cliproxyapi-dashboard \
      --chdir $out/share/cliproxyapi-dashboard/dashboard \
      --set-default DATABASE_URL postgresql://build:build@localhost:5432/build \
      --set-default JWT_SECRET build-time-placeholder-at-least-32-chars \
      --set-default MANAGEMENT_API_KEY build-time-placeholder-16ch \
      --set-default CLIPROXYAPI_MANAGEMENT_URL http://127.0.0.1:8317/v0/management \
      --set-default HOSTNAME 127.0.0.1 \
      --set-default PORT 3000 \
      --set-default NODE_ENV production \
      --set-default NEXT_TELEMETRY_DISABLED 1 \
      --set-default PRISMA_SCHEMA_ENGINE_BINARY ${prisma-engines_7}/bin/schema-engine \
      --set-default PRISMA_QUERY_ENGINE_BINARY ${prisma-engines_7}/bin/query-engine \
      --set-default PRISMA_QUERY_ENGINE_LIBRARY ${prisma-engines_7}/lib/libquery_engine.node \
      --set-default PRISMA_INTROSPECTION_ENGINE_BINARY ${prisma-engines_7}/bin/introspection-engine \
      --set-default PRISMA_FMT_BINARY ${prisma-engines_7}/bin/prisma-fmt \
      --add-flags server.js

    runHook postInstall
  '';

  meta = {
    description = "Next.js dashboard for managing CLIProxyAPI-compatible providers and settings";
    homepage = "https://github.com/itsmylife44/cliproxyapi-dashboard";
    license = lib.licenses.mit;
    mainProgram = "cliproxyapi-dashboard";
    platforms = lib.platforms.linux;
  };
})
