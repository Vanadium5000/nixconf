{ lib, ... }:
let
  inherit (lib)
    concatMapStringsSep
    escapeShellArg
    hasPrefix
    mapAttrsToList
    optionalString
    ;

  normalizeFile = value: if builtins.isAttrs value then value else { source = value; };

  storeText =
    pkgs: path: text:
    if pkgs == null then
      builtins.toFile "nixconf-user-file-${builtins.baseNameOf path}" text
    else
      pkgs.writeText "nixconf-user-file-${builtins.baseNameOf path}" text;

  storeSource =
    pkgs: path: file:
    if file ? text then storeText pkgs path file.text else file.source;

  targetPath = homeDirectory: path: if hasPrefix "/" path then path else "${homeDirectory}/${path}";

  installFile =
    pkgs: homeDirectory: path: value:
    let
      file = normalizeFile value;
      source = storeSource pkgs path file;
      target = targetPath homeDirectory path;
      mode = file.permissions or null;
      copy = (file.type or null) == "copy" || file ? text;
      recursive = file.recursive or false;
      clobber = file.clobber or true;
      quotedSource = escapeShellArg source;
      quotedTarget = escapeShellArg target;
      quotedMode = if mode == null then null else escapeShellArg mode;
    in
    ''
      target=${quotedTarget}
      source=${quotedSource}
      mkdir -p "$(dirname "$target")"
      if ${if clobber then "true" else ''[ ! -e "$target" ] && [ ! -L "$target" ]''}; then
        ${
          if copy then
            ''
              rm -rf "$target"
              if [ -d "$source" ]; then
                mkdir -p "$target"
                cp -Lr --no-preserve=mode "$source"/. "$target"/
              else
                install -D ${optionalString (mode != null) "-m ${quotedMode}"} "$source" "$target"
              fi
            ''
          else if recursive then
            ''
              rm -rf "$target"
              mkdir -p "$target"
              cp -Lr --no-preserve=mode "$source"/. "$target"/
            ''
          else
            ''
              rm -rf "$target"
              ln -s "$source" "$target"
            ''
        }
        ${optionalString (mode != null && (copy || recursive)) ''
          chmod -R ${quotedMode} "$target"
        ''}
      fi
    '';
in
{
  mkActivationScript =
    {
      user,
      homeDirectory ? "/home/${user}",
      files,
      pkgs ? null,
    }:
    ''
      for target in ${
        concatMapStringsSep " " (path: escapeShellArg (targetPath homeDirectory path)) (
          builtins.attrNames files
        )
      }; do
        mkdir -p "$(dirname "$target")"
      done

      ${concatMapStringsSep "\n" (entry: installFile pkgs homeDirectory entry.name entry.value) (
        mapAttrsToList lib.nameValuePair files
      )}

      chown -R ${escapeShellArg user}:users ${escapeShellArg homeDirectory}/.config ${escapeShellArg homeDirectory}/.local ${escapeShellArg homeDirectory}/.unison ${escapeShellArg homeDirectory}/.librewolf 2>/dev/null || true
    '';
}
