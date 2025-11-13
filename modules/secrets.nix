{ ... }:

let
  # Function: makeSecrets
  # Args:
  #   secrets: list of strings (secret names, e.g. [ "PASSWORD_HASH" "API_KEY" ])
  # Returns: attrset { PASSWORD_HASH = "..."; API_KEY = "..."; }
  # Throws: helpful error with export instructions if any are missing
  makeSecrets =
    secrets:
    let
      fetchAll = builtins.map (
        name:
        let
          envname = "SECRETS_${name}";
          val = builtins.getEnv envname;
        in
        {
          inherit name envname val;
        }
      ) secrets;

      missing = builtins.filter (s: s.val == "") fetchAll;
      missingEnv = builtins.map (s: s.envname) missing;

      missingList =
        if builtins.length missingEnv == 0 then
          ""
        else
          builtins.concatStringsSep "\n" (builtins.map (e: "  - ${e}") missingEnv);

      exports =
        if builtins.length missingEnv == 0 then
          ""
        else
          builtins.concatStringsSep "\n" (builtins.map (e: "export ${e}=<your-value>") missingEnv);

    in
    if builtins.length missing > 0 then
      throw ''
                [1;31mERROR: Missing required secrets![0m

                The following environment variables must be set:
        ${missingList}

                [1mExample:[0m
        ${exports}

                [1mTo build:[0m
                  sudo nixos-rebuild switch --flake .#your-host --impure
      ''
    else
      builtins.listToAttrs (
        builtins.map (s: {
          name = s.name;
          value = s.val;
        }) fetchAll
      );

in
{
  flake.secrets = makeSecrets;
}
