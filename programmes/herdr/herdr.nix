{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # Preserve upstream Herdr behavior while reserving one wrapper extension point for flags, env, and runtimePkgs; sources: https://birdeehub.github.io/nix-wrapper-modules/md/intro.html and https://github.com/numtide/llm-agents.nix.
      wrapperConfig = { };
    in
    {
      packages.herdr = inputs.wrappers.lib.wrapPackage (
        {
          inherit pkgs;
          package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
        }
        // wrapperConfig
      );
    };
}
