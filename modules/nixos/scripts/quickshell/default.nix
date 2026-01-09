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
          # Toggle QuickShell for crosshair.qml with slurp selection, using hyprctl dispatch exec to spawn

          QML_FILE="${./crosshair.qml}"
          QS_BIN="${pkgs.quickshell}/bin/qs"

          # Try to kill existing instance (toggling)
          if ! "$QS_BIN" kill -p "$QML_FILE"; then
              # No instance running → allow user to select a region
              geometry=$(
                  {
                      # 1. All mapped windows on active workspace
                      hyprctl clients -j | jq -r --argjson ws "$(hyprctl activeworkspace -j | jq '.id')" '
                          .[]
                          | select(.workspace.id == $ws and .mapped)
                          | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"
                      '
                      # 2. All layer surfaces on monitor with active workspace
                      hyprctl layers -j | jq -r --arg mon "$(hyprctl activeworkspace -j | jq -r '.monitor')" '
                          .[$mon] // {}
                          | .levels // []
                          | .[]
                          | .[]
                          | select(.namespace != "")
                          | "\(.x),\(.y) \(.w)x\(.h)"
                      '
                  } | slurp -r
              )

              # Parse slurp output: "x,y wxh"
              pos=''${geometry%% *}   # extract "x,y"
              size=''${geometry#* }   # extract "wxh"

              IFS=',' read -r x y <<< "$pos"
              IFS='x' read -r w h <<< "$size"

              # Compute center
              center_x=$(( x + w / 2 ))
              center_y=$(( y + h / 2 ))

              # Launch QuickShell via hyprctl dispatch exec
              # Uses QML_FILE, passing X and Y coordinates. Color can be overridden by env variable if needed.
              hyprctl dispatch exec "X=$center_x Y=$center_y \"$QS_BIN\" -p \"$QML_FILE\""
          fi
        '';
      };
    };
}
