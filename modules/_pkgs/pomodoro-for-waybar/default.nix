{
  lib,
  stdenv,
  fetchFromGitHub,
  python3,
  libnotify,
  makeWrapper,
}:

stdenv.mkDerivation {
  pname = "pomodoro-for-waybar";
  version = "unstable-2024-01-14";

  src = fetchFromGitHub {
    owner = "Tejas242";
    repo = "pomodoro-for-waybar";
    rev = "master";
    hash = "sha256-weGmKyRY6TWb0J4fYGjYtJAwSkaDeTp2MmOXCsloxrY=";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3 ];

  installPhase = ''
    install -Dm755 pomodoro_timer.py $out/bin/pomodoro-for-waybar
    wrapProgram $out/bin/pomodoro-for-waybar \
      --prefix PATH : ${lib.makeBinPath [ libnotify ]}
  '';

  meta = with lib; {
    description = "Pomodoro timer for Waybar";
    homepage = "https://github.com/Tejas242/pomodoro-for-waybar";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
