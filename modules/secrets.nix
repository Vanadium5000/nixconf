{
  ...
}:
let
  secrets = [ "PASSWORD_HASH" ];

  fetchAll = builtins.map (
    name:
    let
      envname = "SECRETS_${name}";
      val = builtins.getEnv envname;
    in
    {
      inherit envname name val;
    }
  ) secrets;

  missing = builtins.filter (s: s.val == "") fetchAll;

  missingEnv = builtins.map (s: s.envname) missing;

  missingList =
    if builtins.length missingEnv == 0 then
      ""
    else
      builtins.concatStringsSep "\n" (builtins.map (e: "- ${e}") missingEnv);

  exports =
    if builtins.length missingEnv == 0 then
      ""
    else
      builtins.concatStringsSep "\n" (builtins.map (e: "  export ${e}=value") missingEnv);

in
if builtins.length missing > 0 then
  throw ''
    ERROR: The following secrets are not set:

    ${missingList}

    You must export the environment variables before building, e.g.:

    ${exports}

    and always build with --impure:
      sudo nixos-rebuild switch --flake .#your-host --impure
  ''
else
  let
    secretAttrs = builtins.listToAttrs (
      builtins.map (s: {
        name = s.name;
        value = s.val;
      }) fetchAll
    );
  in
  {
    flake = {
      secrets = secretAttrs;
    };
  }
