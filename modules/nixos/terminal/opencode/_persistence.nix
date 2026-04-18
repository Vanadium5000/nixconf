{
  self,
  user,
  homeDirectory,
  ...
}:
let
  toolsPersistence = self.lib.persistence.mkPersistent {
    method = "bind";
    inherit user;
    fileName = "antigravity_tools";
    targetFile = "${homeDirectory}/.antigravity_tools";
    isDirectory = true;
  };

  opencodePersistence = self.lib.persistence.mkPersistent {
    method = "bind";
    inherit user;
    fileName = "opencode";
    targetFile = "${homeDirectory}/.local/share/opencode";
    isDirectory = true;
  };

  opencodeMemPersistence = self.lib.persistence.mkPersistent {
    method = "bind";
    inherit user;
    fileName = "opencode-mem";
    targetFile = "${homeDirectory}/.opencode-mem";
    isDirectory = true;
  };

  activationText =
    toolsPersistence.activationScript
    + opencodePersistence.activationScript
    + opencodeMemPersistence.activationScript;

  fileSystems =
    toolsPersistence.fileSystems
    // opencodePersistence.fileSystems
    // opencodeMemPersistence.fileSystems;
in
{
  inherit activationText fileSystems;
}
