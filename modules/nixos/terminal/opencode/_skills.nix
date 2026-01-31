{ pkgs }:
let
  # Local skills directory (relative to this file)
  localSkillsDir = ./skill;

  fetchSkill =
    {
      name,
      owner,
      repo,
      rev,
      path,
      hash,
    }:
    pkgs.stdenv.mkDerivation {
      name = "opencode-skill-${name}";
      src = pkgs.fetchFromGitHub {
        inherit
          owner
          repo
          rev
          hash
          ;
      };

      installPhase = ''
        mkdir -p $out
        cp ${path} $out/SKILL.md
      '';
    };

  # fetchSkillDir =
  #   {
  #     name,
  #     owner,
  #     repo,
  #     rev,
  #     basePath,
  #     hash,
  #   }:
  #   pkgs.stdenv.mkDerivation {
  #     name = "opencode-skill-${name}";
  #     src = pkgs.fetchFromGitHub {
  #       inherit
  #         owner
  #         repo
  #         rev
  #         hash
  #         ;
  #     };

  #     installPhase = ''
  #       mkdir -p $out
  #       cp -r ${basePath}/* $out/
  #     '';
  #   };

  skills = {
    refactoring-patterns = fetchSkill {
      name = "refactoring-patterns";
      owner = "proffesor-for-testing";
      repo = "agentic-qe";
      rev = "990aee4a6a747f2db0ef77a2f67d58462f61e608";
      path = ".claude/skills/refactoring-patterns/SKILL.md";
      hash = "sha256-PdIVhLp5/quigz325ZeG4NaWUgPsD3PgykSD61FFjLo=";
    };
  };

  allSkills = pkgs.runCommand "opencode-skills" { } ''
    mkdir -p $out/skill

    # Copy local skills from ./skill directory
    if [ -d "${localSkillsDir}" ]; then
      cp -r ${localSkillsDir}/* $out/skill/
    fi

    # Copy fetched remote skills
    ${pkgs.lib.concatStringsSep "\n" (
      pkgs.lib.mapAttrsToList (name: skill: ''
        mkdir -p $out/skill/${name}
        cp -r ${skill}/* $out/skill/${name}/
      '') skills
    )}
  '';
in
{
  packages = [ ];
  skillsSource = allSkills;
}
