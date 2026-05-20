{
  lib,
  stdenv,
  fetchFromGitHub,
}:

stdenv.mkDerivation {
  pname = "mattpocock-skills";
  version = "0-unstable-2026-05-20";

  src = fetchFromGitHub {
    owner = "mattpocock";
    repo = "skills";
    rev = "b8be62ffacb0118fa3eaa29a0923c87c8c11985c";
    hash = "sha256-Qwuu27f95xgAJ4hdv/4TNahHhprCMIxl1H9f9ymEsno=";
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
