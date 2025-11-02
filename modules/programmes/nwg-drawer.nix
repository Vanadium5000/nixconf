{
  self,
  inputs,
  ...
}:

{
  perSystem =
    {
      pkgs,
      ...
    }:
    let
      inherit (self) theme colors colorsRgba;

      style = pkgs.writeText "style.css" ''
        window {
            background-color: ${colorsRgba.background};
            border-radius: ${toString theme.rounding}px;
        	  border-style: solid;
        	  border-width: ${toString theme.border-size}px;
        	  border-color: ${colors.border-color};
            color: #999
        }

        /* search entry */
        entry {
            background-color: rgba(0, 0, 0, 0.2)
        }

        button {
            /* background: none; */
            background-image: linear-gradient(to bottom, rgba(255,255,255,0.25)0%, rgba(0,0,0,0.5)50%, rgba(0,0,0,0.8)50%);
            border: none
        }

        image {
            border: none
        }

        button:hover {
            background-color: rgba(255, 255, 255, 0.15)
        }

        /* in case you wanted to give category buttons a different look */
        #category-button {
            margin: 0 10px 0 10px
        }

        #pinned-box {
            padding-bottom: 5px;
            border-bottom: 1px #000000
        }

        #files-box {
            padding: 5px;
            border: 1px #000000;
            border-radius: ${toString theme.rounding}
        }

        /* math operation result label */
        #math-label {
            font-weight: bold;
            font-size: 16px
        }
      '';
    in
    {

      packages.nwg-drawer = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.nwg-drawer;
        flags = {
          "-c" = "8";
          "-wm" = "hyprland";
          "-mb" = toString theme.gaps-in;
          "-ml" = toString theme.gaps-in;
          "-mr" = toString theme.gaps-in;
          "-mt" = toString theme.gaps-in;
          # HACK: THIS IS HIGHLY HACKY
          "-s" = "/../../../../${style}";
        };
      };
    };
}
