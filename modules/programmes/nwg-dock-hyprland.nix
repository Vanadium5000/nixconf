{
  self,
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
      inherit (self) theme colors colorsRgba;

      style = pkgs.writeText "style.css" ''
        window {
          background: ${colorsRgba.background};
        	border-radius: ${toString theme.rounding}px;
        	border-style: solid;
        	border-width: ${toString theme.border-size}px;
        	border-color: ${colors.border-color};
        }

        #box {
            /* Define attributes of the box surrounding icons here */
            padding: ${toString theme.gaps-in}px;
        }

        #active {
        	/* This is to underline the button representing the currently active window */
        	/*border-bottom: solid 1px;
        	border-color: ${colors.border-color};*/
        }

        button, image {
        	background: none;
        	border-style: none;
        	box-shadow: none;
        	color: #999;
        }

        button {
          background-image: linear-gradient(to bottom, rgba(255,255,255,0.25)0%, rgba(0,0,0,0.5)50%, rgba(0,0,0,0.8)50%);
        	padding: 3px;
          margin: 3px;
        	margin-left: 2px;
        	margin-right: 2px;
          font-size: ${toString theme.system.font-size}px;
        }

        button:hover {
        	background-color: rgba(255, 255, 255, 0.15);
        	border-radius: ${toString theme.rounding}px;
        }

        button:focus {
        	box-shadow: none;
        }
      '';
    in
    {
      packages.nwg-dock = self'.packages.nwg-dock-hyprland;

      packages.nwg-dock-hyprland = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.nwg-dock-hyprland;
        flags = {
          "-x" = { };
          "-mb" = toString theme.gaps-out;
          "-ml" = toString theme.gaps-out;
          "-mr" = "0";
          "-mt" = toString theme.gaps-out;
          "-f" = { };
          "-p" = "left";
          "-c" = "${self'.packages.nwg-drawer}/bin/nwg-drawer";
          "-a" = "start";
          "-i" = "34";
          # HACK: THIS IS HIGHLY HACKY
          "-s" = "/../../../../${style}";
        };
      };
    };
}
