{
  inputs,
  ...
}:
{
  perSystem =
    {
      pkgs,
      ...
    }:
    {
      packages.toggle-crosshair = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "toggle-crosshair" ''
          hyprctl dispatch exec "${pkgs.quickshell}/bin/qs kill -p ${./crosshair.qml} || ${pkgs.quickshell}/bin/qs -p ${./crosshair.qml}"
        '';
      };
    };
}
