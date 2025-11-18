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

            # Clears screen + scrollback
            alias c="printf '\\033[2J\\033[3J\\033[1;1H'"

            # System actions
            alias suspend "systemctl suspend"
            alias reboot "systemctl reboot"
            alias logout "hyprctl dispatch exit"
            alias poweroff "systemctl poweroff"

            # init starship
            ${self'.packages.starship}/bin/starship init fish | source
          '';
    in
    {
      packages.fish = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.fish;
        runtimeInputs = with pkgs.fishPlugins; [
          # sponge # do not add failed commands to history
          done # send notification once long-running commands finish
          fzf-fish # fzf for fish
        ];
        flags = {
          "-C" = "source ${fishConf}";
        };
      };
    };
}
