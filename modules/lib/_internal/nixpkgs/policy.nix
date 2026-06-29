_:

{
  commonConfig = {
    # Flake/package evaluation must be permissive enough to expose all package
    # outputs; NixOS policy narrows unfree packages with allowUnfreePredicate.
    allowUnfree = true;

    # CVE-2024-23342: ecdsa timing side-channel attack allowing private key recovery.
    # Required by electrum-ltc (litecoin-wallet). Low-value wallet, acceptable risk.
    permittedInsecurePackages = [
      "python3.13-ecdsa-0.19.2"
    ];
  };

  allowedUnfree = [
    "nvidia-kernel-modules"
    "nvidia-x11"
    "nvidia-settings"
    "torch"
    "triton"

    # Nvidia CUDA
    "cuda_cudart"
    "cuda_cccl"
    "libnpp"
    "libcublas"
    "libcufft"
    "cuda_nvcc"
    "cuda-merged"
    "cuda_cuobjdump"
    "cuda_gdb"
    "cuda_nvdisasm"
    "cuda_nvprune"
    "cuda_cupti"
    "cuda_cuxxfilt"
    "cuda_nvml_dev"
    "cuda_nvrtc"
    "cuda_nvtx"
    "cuda_profiler_api"
    "cuda_sanitizer_api"
    "libcurand"
    "libcusolver"
    "libnvjitlink"
    "libcusparse"
    "cudnn"

    # Dictation CUDA deps
    "libcufile"
    "libcusparse_lt"

    # Antigravity Manager
    "antigravity-manager"

    # Firmware
    "intel-ocl"
    "broadcom-bt-firmware"
    "b43-firmware"
    "xow_dongle-firmware"
    "facetimehd-calibration"
    "facetimehd-firmware"
  ];

  temporaryOverrides = { };

  unstablePackageOverrides = final: _prev: {
    # Quickshell is a fast-moving shell runtime; route stable pkgs.quickshell
    # through nixpkgs-unstable so every caller uses the same current package.
    quickshell =
      let
        quickshell = final.unstable.quickshell;
      in
      final.symlinkJoin {
        name = "${quickshell.pname or "quickshell"}-${quickshell.version or "unstable"}-sanitized";
        paths = [ quickshell ];
        nativeBuildInputs = [ final.makeWrapper ];
        postBuild = ''
          for bin in quickshell qs; do
            if [ -x ${quickshell}/bin/$bin ]; then
              rm -f $out/bin/$bin
              makeWrapper ${quickshell}/bin/$bin $out/bin/$bin \
                --unset __QUICKSHELL_CRASH_INFO_FD \
                --unset __QUICKSHELL_CRASH_DUMP_PID
            fi
          done
        '';
        meta = quickshell.meta;
      };
  };

  pythonPackageOverrides = python-final: python-prev: {
    mitmproxy-linux = python-prev.mitmproxy-linux.overridePythonAttrs (old: {
      postPatch = (old.postPatch or "") + ''

        # Fix Linux local/eBPF mode self-capture: ctx.pid() is a thread id, so
        # mitmproxy's tokio UDP worker is not excluded and curl hangs on ACKs.
        # Remove after mitmproxy_rs switches should_intercept() to ctx.tgid().
        # Source: https://github.com/mitmproxy/mitmproxy/issues/7787
        substituteInPlace mitmproxy-linux-ebpf/src/main.rs \
          --replace-fail 'let pid = ctx.pid();' 'let pid = ctx.tgid();'

      '';
    });

    mitmproxy-rs = python-prev.mitmproxy-rs.overridePythonAttrs (old: {
      postPatch = (old.postPatch or "") + ''

        # NixOS keeps the setuid sudo wrapper outside package PATH at /run/wrappers,
        # and mitmproxy.service's tight capability bounding set prevents sudo from
        # re-reading sudoers even when the service already runs as UID 0. Skip sudo
        # entirely for root services; only interactive user launches use sudo.
        patch -p1 <<'PATCH'
        diff --git a/src/packet_sources/linux.rs b/src/packet_sources/linux.rs
        index 6c0d57c..dd9b4df 100644
        --- a/src/packet_sources/linux.rs
        +++ b/src/packet_sources/linux.rs
        @@ -23,6 +23,17 @@ use tempfile::{tempdir, TempDir};
         use tokio::net::UnixDatagram;
         use tokio::process::Command;
         use tokio::time::timeout;

        +fn running_as_root() -> bool {
        +    std::fs::read_to_string("/proc/self/status")
        +        .ok()
        +        .and_then(|status| {
        +            status.lines().find(|line| line.starts_with("Uid:")).and_then(|line| {
        +                line.split_whitespace().nth(2).and_then(|uid| uid.parse::<u32>().ok())
        +            })
        +        })
        +        .is_some_and(|effective_uid| effective_uid == 0)
        +}
        +
         async fn start_redirector(
             executable: &Path,
             listener_addr: &Path,
        @@ -30,22 +41,28 @@ async fn start_redirector(
         ) -> Result<PathBuf> {
             debug!("Elevating privileges...");
             // Try to elevate privileges using a dummy sudo invocation.
        -    // The idea here is to block execution and give the user time to enter their password.
        -    // For now, we naively assume that all systems 1) have sudo and 2) timestamp_timeout > 0.
        -    let mut sudo = Command::new("sudo")
        -        .arg("echo")
        -        .arg("-n")
        -        .spawn()
        -        .context("Failed to run sudo.")?;
        -    sudo.stdin.take();
        -    if !sudo.wait().await.is_ok_and(|x| x.success()) {
        -        bail!("Failed to elevate privileges");
        +    // The idea here is to block execution and give the user time to enter their
        +    // password. Root services already have the needed privileges, and invoking
        +    // sudo from a systemd sandbox can fail while re-reading sudoers.
        +    let run_as_root = running_as_root();
        +    if !run_as_root {
        +        let mut sudo = Command::new("/run/wrappers/bin/sudo")
        +            .arg("echo")
        +            .arg("-n")
        +            .spawn()
        +            .context("Failed to run sudo.")?;
        +        sudo.stdin.take();
        +        if !sudo.wait().await.is_ok_and(|x| x.success()) {
        +            bail!("Failed to elevate privileges");
        +        }
             }

             debug!("Starting mitmproxy-linux-redirector...");
        -    let mut redirector_process = Command::new("sudo")
        -        .arg("--non-interactive")
        -        .arg("--preserve-env")
        -        .arg(executable)
        +    let mut redirector_command = if run_as_root {
        +        Command::new(executable)
        +    } else {
        +        let mut command = Command::new("/run/wrappers/bin/sudo");
        +        command.arg("--non-interactive").arg("--preserve-env").arg(executable);
        +        command
        +    };
        +    let mut redirector_process = redirector_command
             .arg(listener_addr)
             .stdin(Stdio::null())
             .stdout(Stdio::piped())
        PATCH
      '';
    });

    tenacity = python-prev.tenacity.overridePythonAttrs (_old: {
      # Disable flaky tests (AssertionError: 4 not less than 1.1)
      # Fixes build failures when system is under load.
      doCheck = false;
    });
    trezor = python-prev.trezor.overridePythonAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ python-final.pythonRelaxDepsHook ];

      # Trezor 0.20.0 tightened wheel metadata to keyring>=25.7.0, but nixpkgs still
      # ships 25.6.0 here. Relax the lower bound locally so electrum-ltc keeps building
      # until nixpkgs catches up. Source: trezor-firmware/python/pyproject.toml.
      pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "keyring" ];
    });
  };
}
