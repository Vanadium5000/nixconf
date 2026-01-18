{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      ...
    }:
    let
      pythonEnv = pkgs.python3.withPackages (
        ps: with ps; [
          numpy
          pyaudio
          # faster-whisper might need to be added from unstable or custom if not present
          # We will try to use it if available, otherwise we might need a workaround.
          (if ps ? faster-whisper then ps.faster-whisper else null)
        ]
      );

      daemonScript = ./daemon.py;
      clientScript = ./client.py;
    in
    {
      packages.dictation-daemon = pkgs.writeShellScriptBin "dictation-daemon" ''
        export PATH=${pkgs.wtype}/bin:${pkgs.coreutils}/bin:$PATH
        # CUDA environment variables are expected to be set by the system module
        # if CUDA support is enabled.

        ${pythonEnv}/bin/python3 ${daemonScript}
      '';

      packages.dictation-client = pkgs.writeShellScriptBin "dictation-client" ''
        ${pythonEnv}/bin/python3 ${clientScript} "$@"
      '';
    };

  flake.nixosModules.dictation =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.preferences.dictation;
      cudaEnabled = config.nixpkgs.config.cudaSupport or false;
    in
    {
      options.preferences.dictation = {
        enable = lib.mkEnableOption "Dictation system";
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          inputs.self.packages.${pkgs.system}.dictation-daemon
          inputs.self.packages.${pkgs.system}.dictation-client
        ];

        # Add environment variables for CUDA support if enabled
        environment.variables = lib.mkIf cudaEnabled {
          USE_CUDA = "1";
          CUDA_PATH = "${pkgs.cudatoolkit}";
          LD_LIBRARY_PATH =
            "${pkgs.cudatoolkit}/lib:${pkgs.cudaPackages.cudnn}/lib"
            + (lib.optionalString (config.hardware ? nvidia) ":${config.hardware.nvidia.package}/lib")
            + ":$LD_LIBRARY_PATH";
        };
      };
    };
}
