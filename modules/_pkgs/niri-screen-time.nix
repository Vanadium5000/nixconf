{
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule {
  pname = "niri-screen-time";
  version = "0.0.15";
  vendorHash = "sha256-9y1F2ZrmpiQJ9ZTq9SoRE2PxR65DDNCeBKf4M0HUQC4=";
  src = fetchFromGitHub {
    owner = "probeldev";
    repo = "niri-screen-time";
    rev = "v0.0.15";
    sha256 = "sha256-UMnjlpsRiAr3Y8xuZ3rwlrTj6P46q1e83WTUnAZkKVE=";
  };
}
