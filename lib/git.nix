{ lib, ... }:
let
  inherit (lib)
    concatMapStrings
    concatMapStringsSep
    filterAttrs
    isBool
    isInt
    isList
    mapAttrsToList
    optionalAttrs
    optionalString
    recursiveUpdate
    ;

  escapeGitString =
    value:
    builtins.replaceStrings
      [
        "\\"
        "\""
        "\n"
      ]
      [
        "\\\\"
        "\\\""
        "\\n"
      ]
      (toString value);

  renderValue =
    value:
    if isBool value then
      if value then "true" else "false"
    else if isInt value then
      toString value
    else
      ''"${escapeGitString value}"'';

  renderKeyValue =
    key: value:
    if isList value then
      concatMapStrings (item: renderKeyValue key item) value
    else if value == null then
      ""
    else
      "  ${key} = ${renderValue value}\n";

  renderSection =
    section:
    let
      values = filterAttrs (_: value: value != null) section.values;
    in
    optionalString (values != { }) (
      "[${section.name}]\n"
      + concatMapStrings (entry: renderKeyValue entry.name entry.value) (
        mapAttrsToList lib.nameValuePair values
      )
    );

  renderConfigAttrs =
    attrs:
    renderSections (
      mapAttrsToList (name: values: {
        inherit name values;
      }) attrs
    );

  renderSections = sections: concatMapStringsSep "\n" renderSection sections;

  sectionWithSubsection = section: subsection: ''${section} "${escapeGitString subsection}"'';

  mkIdentityConfig =
    identity:
    let
      baseConfig = {
        user = {
          inherit (identity) name email;
        }
        // optionalAttrs (identity.signingKey != null) {
          signingKey = identity.signingKey;
        };
      }
      // optionalAttrs (identity.gpgFormat != null) {
        gpg.format = identity.gpgFormat;
      }
      // optionalAttrs identity.signByDefault {
        commit.gpgSign = true;
      };
    in
    renderConfigAttrs (recursiveUpdate baseConfig identity.extraConfig);
in
{
  inherit
    escapeGitString
    mkIdentityConfig
    renderConfigAttrs
    renderSections
    sectionWithSubsection
    ;
}
