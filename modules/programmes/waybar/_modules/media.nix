pkgs:
let
  album_art = pkgs.writeShellScriptBin "album_art" ''
    # File to store the last URL
    CACHE_FILE="/tmp/last_album_art_url.txt"
    # Output file for the album art
    OUTPUT_FILE="/tmp/cover.jpeg"

    # Get the current album art URL
    album_art=$(${pkgs.playerctl}/bin/playerctl metadata mpris:artUrl 2>/dev/null)

    # Exit if no URL is found
    if [[ -z "$album_art" ]]; then
        echo ""
        exit 1
    fi

    # Check if cache file exists, if not create it
    if [[ ! -f "$CACHE_FILE" ]]; then
        touch "$CACHE_FILE"
    fi

    # Read the last URL from cache
    last_url=$(cat "$CACHE_FILE")

    # Compare current URL with cached URL
    if [[ "$album_art" == "$last_url" && -f "$OUTPUT_FILE" ]]; then
        # If URL hasn't changed and file exists, output cached file path
        echo "$OUTPUT_FILE"
    else
        # Download new album art and update cache
        curl -s "$album_art" --output "$OUTPUT_FILE" --fail
        if [[ $? -eq 0 ]]; then
            # Only update cache if download was successful
            echo "$album_art" > "$CACHE_FILE"
            echo "$OUTPUT_FILE"
        else
            # If download fails, output empty string and exit
            echo ""
            exit 1
        fi
    fi
  '';
in
{
  # Options: https://github.com/Alexays/Waybar/wiki/Configuration
  mpris = {
    format = "{status_icon} {position}/{length}";
    format-paused = "{status_icon} {position}/{length}";
    interval = 1;
    status-icons = {
      playing = "󰐊";
      paused = "󰏤";
    };
  };
  # Waybar lyrics
  "custom/lyrics" = {
    return-type = "json";
    format = "{icon} {0}";
    hide-empty-text = true;
    format-icons = {
      playing = "";
      paused = "";
      lyric = "";
      music = "󰝚";
    };
    exec = "${pkgs.waybar-lyric}/bin/waybar-lyric --quiet -m50";
    on-click = "${pkgs.waybar-lyric}/bin/waybar-lyric --toggle";

    # Restart interval (secs) - only with continuous scripts
    restart-interval = 2;
  };
  "image#album-art" = {
    exec = "${album_art}/bin/album_art";
    size = 24;
    interval = 2;
  };
  "group/media" = {
    orientation = "horizontal";
    modules = [
      "image#album-art"
      #"mpris"
      "custom/lyrics"
      "custom/pomodoro"
    ];
  };
}
