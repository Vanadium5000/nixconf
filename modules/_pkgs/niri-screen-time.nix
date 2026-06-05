{
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule {
  pname = "niri-screen-time";
  version = "0.0.16";
  vendorHash = "sha256-9y1F2ZrmpiQJ9ZTq9SoRE2PxR65DDNCeBKf4M0HUQC4=";
  src = fetchFromGitHub {
    owner = "probeldev";
    repo = "niri-screen-time";
    rev = "v0.0.16";
    sha256 = "sha256-/I8fLD04VMnmpXKCftq5YmD/4Cobus2FPa4thV7chzA=";
  };
}
