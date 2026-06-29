{
  lib,
  writeShellApplication,
}:

writeShellApplication {
  name = "pass-credential";
  text = builtins.readFile ./pass-credential/pass-credential;

  meta = {
    description = "Small parser for password-store credential fields";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "pass-credential";
    platforms = lib.platforms.unix;
  };
}
