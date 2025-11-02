{
  flake.nixosModules.chromium =
    { pkgs, ... }:
    {
      programs.chromium = {
        enable = true;
        extensions = [
          "chlffgpmiacpedhhbkiomidkjlcfhogd" # pushbullet
          "gcbommkclmclpchllfjekcdonpmejbdp" # https everywhere
          "cjpalhdlnbpafiamejdnhcphjbkeiagm" # ublock origin
          "mnjggcdmjocbbbhaepdhchncahnbgone" # sponsor block
          "eimadpbcbfnmbkopoojfekhnkhdbieeh" # dark reader
          "fnaicdffflnofjppbagibeoednhnbjhg" # floccus bookmarks sync
          "lodbfhdipoipcjmlebjbgmmgekckhpfb" # private grammar checker - harper
          "gebbhagfogifgggkldgodflihgfeippi" # return youtube dislike
          "dhdgffkkebhmkfjojejmpbldmpobfkfo" # tamper monkey
          "kchfmpdcejfkipopnolndinkeoipnoia" # user agent switcher
        ];
      };

      environment.systemPackages = [
        pkgs.ungoogled-chromium
      ];

      # Persist data
      persistance.home.cache.directories = [
        ".config/chromium"
      ];
    };
}
