{ inputs, self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # Pi loads package directories listed in settings.json. Keep this small
      # adapter reproducibly pinned; source: https://github.com/nicobailon/pi-mcp-adapter.
      pi-mcp-adapter = pkgs.buildNpmPackage {
        pname = "pi-mcp-adapter";
        version = "2.17.0";
        src = pkgs.fetchFromGitHub {
          owner = "nicobailon";
          repo = "pi-mcp-adapter";
          rev = "82c631dca1b9217701af0ccfe763ef3b79cd1ec0";
          hash = "sha256-jP3bHSQO6toATLLE9pgoHMGUxZsoDDdEJARc5Ut0g8w=";
        };
        npmDepsHash = "sha256-9zvrv6EzzuHF5TdNdrpF1nE/nNeIxkKbyAgf1Ln579c=";
        npmDepsFetcherVersion = 2;
        dontNpmBuild = true;
        nativeBuildInputs = [ pkgs.python3 ];
        npmInstallFlags = [ "--omit=dev" ];
        npmPruneFlags = [ "--omit=dev" ];
        # npm's lockfile records dev-only nested Pi packages without integrity,
        # which prefetch-npm-deps rejects. Prune that unreachable graph before
        # both dependency prefetch and install. Source: nixpkgs
        # pkgs/build-support/node/prefetch-npm-deps/src/parse/mod.rs.
        postPatch = ''
          ${pkgs.python3}/bin/python3 - <<'PY'
          import json
          from pathlib import Path

          package = Path("package.json")
          package_data = json.loads(package.read_text())
          package_data.pop("devDependencies", None)
          package.write_text(json.dumps(package_data, indent=2) + "\n")

          lock = Path("package-lock.json")
          data = json.loads(lock.read_text())
          records = data["packages"]
          records[""].pop("devDependencies", None)
          removed = {key for key, value in records.items() if key and value.get("dev") is True}
          for key in removed:
              records.pop(key, None)
          edge_fields = ("dependencies", "optionalDependencies", "peerDependencies", "peerDependenciesMeta", "bundleDependencies", "bundledDependencies")
          changed = True
          while changed:
              changed = False
              for parent, value in list(records.items()):
                  for field in edge_fields:
                      edges = value.get(field)
                      if not isinstance(edges, dict):
                          continue
                      for dependency in list(edges):
                          nested = f"{parent}/node_modules/{dependency}" if parent else f"node_modules/{dependency}"
                          top_level = f"node_modules/{dependency}"
                          if nested in removed or (nested not in records and top_level in removed):
                              del edges[dependency]
                              changed = True
          lock.write_text(json.dumps(data, indent=2) + "\n")
          PY
        '';
      };
    in
    {
      packages.pi-mcp-adapter = pi-mcp-adapter;
      packages.pi-agent = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;
        runtimePkgs = [ pi-mcp-adapter ];
        env = {
          PI_MCP_ADAPTER_PACKAGE = "${pi-mcp-adapter}/lib/node_modules/pi-mcp-adapter";
          EXA_API_KEY = self.secrets.EXA_API_KEY;
        };
      };
    };
}
