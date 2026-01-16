{ pkgs }:
let
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

  fetchSkillDir =
    {
      name,
      owner,
      repo,
      rev,
      basePath,
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
        cp -r ${basePath}/* $out/
      '';
    };

  skills = {
    technical-writing = fetchSkill {
      name = "technical-writing";
      owner = "proffesor-for-testing";
      repo = "agentic-qe";
      rev = "990aee4a6a747f2db0ef77a2f67d58462f61e608";
      path = ".claude/skills/technical-writing/SKILL.md";
      hash = "sha256-PdIVhLp5/quigz325ZeG4NaWUgPsD3PgykSD61FFjLo=";
    };

    refactoring-patterns = fetchSkill {
      name = "refactoring-patterns";
      owner = "proffesor-for-testing";
      repo = "agentic-qe";
      rev = "990aee4a6a747f2db0ef77a2f67d58462f61e608";
      path = ".claude/skills/refactoring-patterns/SKILL.md";
      hash = "sha256-PdIVhLp5/quigz325ZeG4NaWUgPsD3PgykSD61FFjLo=";
    };

    blog-post-writer = fetchSkillDir {
      name = "blog-post-writer";
      owner = "nicknisi";
      repo = "dotfiles";
      rev = "f1be3f2b669c8e3401b589141f9a56651e45a1a7";
      basePath = "home/.claude/skills/blog-post-writer";
      hash = "sha256-U1GqtQMgzimGbbDJpqIGrBnu5HiSTZDETAKFhijMU9s=";
    };

    frontend-design = fetchSkill {
      name = "frontend-design";
      owner = "anthropics";
      repo = "claude-code";
      rev = "d213a74fc8e3b6efded52729196e0c2d4c3abb3e";
      path = "plugins/frontend-design/skills/frontend-design/SKILL.md";
      hash = "sha256-SleLxTUjM7HNHc78YklikuFwix2DPaTDIACUnsSQCrA=";
    };

    architecture-patterns = fetchSkill {
      name = "architecture-patterns";
      owner = "wshobson";
      repo = "agents";
      rev = "e4dade12847a99d277d81192c2966e9b61c0d3f1";
      path = "plugins/backend-development/skills/architecture-patterns/SKILL.md";
      hash = "sha256-UiiJzLo8fJLMoCjh389v1P0Q4Nc36S8Po+fvm/j0gxo=";
    };

    flutter-development = fetchSkill {
      name = "flutter-development";
      owner = "aj-geddes";
      repo = "useful-ai-prompts";
      rev = "ce8c39c22df0e0e64c853817a7f8d79f0ea331e2";
      path = "skills/flutter-development/SKILL.md";
      hash = "sha256-BCvO+P2URoTiUOSV8PTq62ckyxXLEHtIml0EkZGRbK8=";
    };

    writing-documentation = fetchSkillDir {
      name = "writing-documentation";
      owner = "dhruvbaldawa";
      repo = "ccconfigs";
      rev = "451b604718d39fcc2c008d22e550bdf60c7115da";
      basePath = "essentials/skills/writing-documentation";
      hash = "sha256-7V1xG2FmzqWdnWmVV6WWKBAvY6QHWo+UKzh0Uu/Xg/w=";
    };

    rust-engineer = fetchSkill {
      name = "rust-engineer";
      owner = "sammcj";
      repo = "agentic-coding";
      rev = "f2ee2fb7138b78856b68c9b874d6e3d406a2a8a4";
      path = "Claude/skills_disabled/rust-engineer/SKILL.md";
      hash = "sha256-vQpInoUbctAwT/eL/27Gr6UkuNH3Au8By2PCXM5z9AQ=";
    };
  };

  allSkills = pkgs.runCommand "opencode-skills" { } ''
    mkdir -p $out/skill

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
