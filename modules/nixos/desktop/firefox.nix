{
  flake.nixosModules.firefox =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      ext = name: "https://addons.mozilla.org/firefox/downloads/latest/${name}/latest.xpi";

      extensions =
        extensionStrings: lib.strings.concatStringsSep ", " (builtins.map ext extensionStrings);
    in
    {
      programs.firefox = {
        enable = true;
        package = pkgs.librewolf;

        /*
          * [NOTE] Cookie Clear Exceptions: For cross-domain logins, add exceptions for both sites
          * e.g. https://www.youtube.com (site) + https://accounts.google.com (single sign on)
          * [WARNING] Be selective with what sites you "Allow", as they also disable partitioning (1767271)
          * [SETTING] to add site exceptions: Ctrl+I>Permissions>Cookies>Allow (when on the website in question)
          * [SETTING] to manage site exceptions: Options>Privacy & Security>Permissions>Settings **
        */
        preferences = {
          "sidebar.verticalTabs" = true;
          "sidebar.visibility" = "expand-on-hover";
          "layout.spellcheckDefault" = 0; # Disable spellcheck - use Harper spellcheck instead
          "widget.gtk.overlay-scrollbars.enabled" = false; # Always show scrollbars
          "layout.css.always_underline_links" = true;

          # Don't suggest stuff in the urlbar
          "browser.urlbar.suggest.history" = false;

          # Re-enable browser rendering stuff
          "webgl.disabled" = false;

          # Disable annoying swipe gestures (alt + left/right arrow is so much easier)
          "browser.gesture.swipe.left" = "";
          "browser.gesture.swipe.right" = "";

          # Extensions
          "browser.policies.runOncePerModification.extensionsInstall" = extensions [
            # Ad block
            "ublock-origin"

            # Bookmarks & tabs sync across browsers any WebDAV or Git service,
            # via local file, Nextcloud, or Google Drive
            "floccus"

            # Dark mode for every website
            "darkreader"

            # YouTube enhancements
            "sponsorblock"
            "return-youtube-dislikes"
            #youtube-enhancer-vc # Block YT shorts & general improvements

            "tampermonkey" # Userscripts
            "private-grammar-checker-harper" # Private spellcheck
          ];
        };
      };

      impermanence.home.cache.directories = [
        ".mozilla"
        ".librewolf"
      ];
    };
}
