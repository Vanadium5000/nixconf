{
  lib,
  stdenv,
  fetchFromGitHub,
}:

stdenv.mkDerivation {
  pname = "mattpocock-skills";
  version = "0-unstable-2026-05-28";

  src = fetchFromGitHub {
    owner = "mattpocock";
    repo = "skills";
    rev = "e3b90b5238f38cdea5996e16861dcae28ef52eda";
    hash = "sha256-RRVV4V4h/9GkwnHU4G4PLQtwdU1Lm4istvGncwmQ9dg=";
  };

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/opencode/skills"

    # Install reusable workflow/engineering skills only. Exclude personal,
    # deprecated, in-progress, Claude-specific, and suite bootstrap skills.
    for skill in \
      skills/productivity/caveman \
      skills/productivity/grill-me \
      skills/productivity/handoff \
      skills/productivity/write-a-skill \
      skills/engineering/diagnose \
      skills/engineering/grill-with-docs \
      skills/engineering/improve-codebase-architecture \
      skills/engineering/prototype \
      skills/engineering/tdd \
      skills/engineering/to-issues \
      skills/engineering/to-prd \
      skills/engineering/triage \
      skills/engineering/zoom-out \
      skills/misc/setup-pre-commit
    do
      cp -R "$skill" "$out/share/opencode/skills/$(basename "$skill")"
    done

    runHook postInstall
  '';

  meta = {
    description = "Selected reusable OpenCode skills from mattpocock/skills";
    homepage = "https://github.com/mattpocock/skills";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
