{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  fetchWallpaper =
    {
      source,
      file,
      url,
      hash,
    }:
    {
      inherit source file;
      src = fetchurl {
        inherit url hash;
      };
    };

  wallpapers = [
    # Curated NixOS images only; fetching raw blobs avoids pulling the archived
    # artwork repo and its source files. Source listing:
    # https://github.com/NixOS/nixos-artwork/tree/9d2cdedd73d64a068214482902adea3d02783ba8/wallpapers
    (fetchWallpaper {
      source = "nixos";
      file = "nix-wallpaper-nineish-dark-gray.png";
      url = "https://raw.githubusercontent.com/NixOS/nixos-artwork/9d2cdedd73d64a068214482902adea3d02783ba8/wallpapers/nix-wallpaper-nineish-dark-gray.png";
      hash = "sha256-nhIUtCy/Hb8UbuxXeL3l3FMausjQrnjTVi1B3GkL9B8=";
    })
    (fetchWallpaper {
      source = "nixos";
      file = "nix-wallpaper-simple-dark-gray.png";
      url = "https://raw.githubusercontent.com/NixOS/nixos-artwork/9d2cdedd73d64a068214482902adea3d02783ba8/wallpapers/nix-wallpaper-simple-dark-gray.png";
      hash = "sha256-JaLHdBxwrphKVherDVe5fgh+3zqUtpcwuNbjwrBlAok=";
    })
    (fetchWallpaper {
      source = "nixos";
      file = "nix-wallpaper-moonscape.png";
      url = "https://raw.githubusercontent.com/NixOS/nixos-artwork/9d2cdedd73d64a068214482902adea3d02783ba8/wallpapers/nix-wallpaper-moonscape.png";
      hash = "sha256-AR3W8avHzQLxMNLfD/A1efyZH+vAdTLKllEhJwBl0xc=";
    })
    (fetchWallpaper {
      source = "nixos";
      file = "nix-wallpaper-nineish-catppuccin-mocha.png";
      url = "https://raw.githubusercontent.com/NixOS/nixos-artwork/9d2cdedd73d64a068214482902adea3d02783ba8/wallpapers/nix-wallpaper-nineish-catppuccin-mocha.png";
      hash = "sha256-zlYqSid5Q1L5sUrAcvR+7aN2jImiuoR9gygBRk8x9Wo=";
    })

    # Curated nixy images only; raw pinned URLs keep update-pkgs' fetchurl hash
    # scanner usable and avoid copying the full archived collection.
    # Source listing:
    # https://github.com/anotherhadi/nixy-wallpapers/tree/e1f2cb6208450b88cc6dfbdd39c0a01981991768/wallpapers
    (fetchWallpaper {
      source = "nixy";
      file = "Grey-mountains.png";
      url = "https://raw.githubusercontent.com/anotherhadi/nixy-wallpapers/e1f2cb6208450b88cc6dfbdd39c0a01981991768/wallpapers/Grey-mountains.png";
      hash = "sha256-9MmgwPAyKjLc0s2mO9r3HqoctXeLWQJ2JAFOLsRUDIU=";
    })
    (fetchWallpaper {
      source = "nixy";
      file = "Tokyo-skyscraper.png";
      url = "https://raw.githubusercontent.com/anotherhadi/nixy-wallpapers/e1f2cb6208450b88cc6dfbdd39c0a01981991768/wallpapers/Tokyo-skyscraper.png";
      hash = "sha256-zO8PnWPKVNucrW8RGUFZIOmNScIH553PBryKHRvk2R4=";
    })
    (fetchWallpaper {
      source = "nixy";
      file = "dark-forest.png";
      url = "https://raw.githubusercontent.com/anotherhadi/nixy-wallpapers/e1f2cb6208450b88cc6dfbdd39c0a01981991768/wallpapers/dark-forest.png";
      hash = "sha256-ApqHhEvbtvwTMtq1fwkl1y5K/ABMDJLShPcQcthQI7g=";
    })
    (fetchWallpaper {
      source = "nixy";
      file = "fuji-dark.png";
      url = "https://raw.githubusercontent.com/anotherhadi/nixy-wallpapers/e1f2cb6208450b88cc6dfbdd39c0a01981991768/wallpapers/fuji-dark.png";
      hash = "sha256-FaHwofrnxNXa1xBIdR9custxWezLYh5elm2FgKdtXCk=";
    })
    (fetchWallpaper {
      source = "nixy";
      file = "lofi-urban.png";
      url = "https://raw.githubusercontent.com/anotherhadi/nixy-wallpapers/e1f2cb6208450b88cc6dfbdd39c0a01981991768/wallpapers/lofi-urban.png";
      hash = "sha256-YGBkEkjhiHT05ZCdzw29T8HkNqfv5IIs036F9QGS4SM=";
    })

    # ItsTerm1n4l/Wallpapers is hundreds of MiB; package only selected images
    # from the upstream `images/` directory. Source tree:
    # https://github.com/ItsTerm1n4l/Wallpapers/tree/2fe8bf0b6affda0ee11c37aa11bbdafc8c15df82/images
    (fetchWallpaper {
      source = "itsterm1n4l";
      file = "Firewatch-black-sunset.jpg";
      url = "https://raw.githubusercontent.com/ItsTerm1n4l/Wallpapers/2fe8bf0b6affda0ee11c37aa11bbdafc8c15df82/images/Firewatch-black-sunset.jpg";
      hash = "sha256-mdicFxNoAmDv6M+hPbaKjhUgb49jIuSMWwq8ofYLs0Q=";
    })
    (fetchWallpaper {
      source = "itsterm1n4l";
      file = "Kanawaga-godzilla.jpg";
      url = "https://raw.githubusercontent.com/ItsTerm1n4l/Wallpapers/2fe8bf0b6affda0ee11c37aa11bbdafc8c15df82/images/Kanawaga-godzilla.jpg";
      hash = "sha256-BLcQahIHb2KFlxVfAUL7x6A0ZTGxhc/5tPBjkZRx970=";
    })
    (fetchWallpaper {
      source = "itsterm1n4l";
      file = "Nord-wave-dark.png";
      url = "https://raw.githubusercontent.com/ItsTerm1n4l/Wallpapers/2fe8bf0b6affda0ee11c37aa11bbdafc8c15df82/images/Nord-wave-dark.png";
      hash = "sha256-DbrPggVO3w7GVlH1gohYLJRD7HymWKl7GJELmxvCXcE=";
    })
    (fetchWallpaper {
      source = "itsterm1n4l";
      file = "Fantasy-woods-pool.jpg";
      url = "https://raw.githubusercontent.com/ItsTerm1n4l/Wallpapers/2fe8bf0b6affda0ee11c37aa11bbdafc8c15df82/images/Fantasy-woods-pool.jpg";
      hash = "sha256-CaTiI64Pu7yThmjrsHiWYQpL9Ih1wCMaPHDZvcvfuu0=";
    })
    (fetchWallpaper {
      source = "itsterm1n4l";
      file = "Lakeside-sunrise.png";
      url = "https://raw.githubusercontent.com/ItsTerm1n4l/Wallpapers/2fe8bf0b6affda0ee11c37aa11bbdafc8c15df82/images/Lakeside-sunrise.png";
      hash = "sha256-3jHo587/lMuxMfaFCpHqhS1657enYCZugBm5e5pJ0vo=";
    })

    # Ahwxorg/Wallpapers is close to 1 GiB; package a representative spread
    # across upstream category directories instead of the whole repo. Source tree:
    # https://github.com/Ahwxorg/Wallpapers/tree/d7530fef4f84e9e4fcdfe47f84d12189c8551ac8
    (fetchWallpaper {
      source = "ahwxorg";
      file = "aenami-alena-aenami-out-of-time-1080p.jpg";
      url = "https://raw.githubusercontent.com/Ahwxorg/Wallpapers/d7530fef4f84e9e4fcdfe47f84d12189c8551ac8/aenami/alena-aenami-out-of-time-1080p.jpg";
      hash = "sha256-rWhl2OnY80rkGawjJEiAjToIq7VwZSqCwI3XTmXRZXo=";
    })
    (fetchWallpaper {
      source = "ahwxorg";
      file = "catppuccin-rainbow.png";
      url = "https://raw.githubusercontent.com/Ahwxorg/Wallpapers/d7530fef4f84e9e4fcdfe47f84d12189c8551ac8/catppuccin/rainbow.png";
      hash = "sha256-wkXFqLpI3E2AxkU0nvn4s1vqG3KDLcjxE/ZGE2Su4ig=";
    })
    (fetchWallpaper {
      source = "ahwxorg";
      file = "nord-scenary.png";
      url = "https://raw.githubusercontent.com/Ahwxorg/Wallpapers/d7530fef4f84e9e4fcdfe47f84d12189c8551ac8/nord/nord-scenary.png";
      hash = "sha256-axxFPAIlSs0T6D8Hv7RmaQp3+EJUXqVfoifIifG/66k=";
    })
    (fetchWallpaper {
      source = "ahwxorg";
      file = "tokyo-night-stripes_night.png";
      url = "https://raw.githubusercontent.com/Ahwxorg/Wallpapers/d7530fef4f84e9e4fcdfe47f84d12189c8551ac8/tokyo-night/stripes_night.png";
      hash = "sha256-S5MyEmabnaMvPNB6Dp+07gvJyBB72+fjpGldESPUI9Y=";
    })
    (fetchWallpaper {
      source = "ahwxorg";
      file = "city-asrgvjkndcjkml.jpg";
      url = "https://raw.githubusercontent.com/Ahwxorg/Wallpapers/d7530fef4f84e9e4fcdfe47f84d12189c8551ac8/city/asrgvjkndcjkml.jpg";
      hash = "sha256-1JOANWHWpma7OYHT1FIdMNHUCivDDFgY3T8cyINp9rs=";
    })
  ];
in
stdenvNoCC.mkDerivation {
  pname = "wallpapers";
  version = "0-unstable-2026-05-04";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    ${lib.concatMapStringsSep "\n" (wallpaper: ''
      install -Dm644 ${wallpaper.src} "$out/wallpapers/${wallpaper.source}/${wallpaper.file}"
    '') wallpapers}

    runHook postInstall
  '';

  meta = {
    description = "Curated wallpaper collection assembled from pinned raw upstream images";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.unfreeRedistributable;
    platforms = lib.platforms.all;
  };
}
