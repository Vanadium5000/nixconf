{
  inputs,
  ...
}:
{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    let
      fishConf =
        pkgs.writeText "fish-init"
          # fish
          ''
            #fastfetch
            # shut up welcome message
            set fish_greeting

            # set options for plugins
            set sponge_regex_patterns 'password|passwd'

            # Setup GPG_TTY for GPG-support on Fish
            set -gx GPG_TTY (tty)

            # init starship
            ${self'.packages.starship}/bin/starship init fish | source
          '';
    in
    {
      packages.fish = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.fish;
        flags = {
          "-C" = "source ${fishConf}";
        };
      };
    };
}
