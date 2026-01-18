{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
    in
    {
      packages.git = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.git;
        env = rec {
          GIT_AUTHOR_NAME = "Vanadium5000";
          GIT_AUTHOR_EMAIL = "vanadium5000@gmail.com";
          GIT_COMMITTER_NAME = GIT_AUTHOR_NAME;
          GIT_COMMITTER_EMAIL = GIT_AUTHOR_EMAIL;
        };
      };
    };
}
