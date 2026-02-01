# PersonaLive - Real-time streamable portrait animation
# https://github.com/GVCLab/PersonaLive
#
# Models are downloaded at runtime via tools/download_weights.py to ./pretrained_weights/
# Required models: sd-vae-ft-mse, sd-image-variations-diffusers, personalive weights
#
# Usage:
#   personalive              - Offline batch inference (generates video file)
#   personalive-online       - Real-time webcam streaming (opens browser UI)
#   personalive-download     - Download model weights
#
# CUDA Support:
#   Uses torch-bin (pre-built CUDA binaries) with forced cudaSupport config.
#   Runtime CUDA libs are added via LD_LIBRARY_PATH in wrapper scripts.
#
# Version Pinning (CRITICAL):
#   PersonaLive requires specific dependency versions from requirements_base.txt:
#   - diffusers==0.27.0: Newer versions have breaking API changes in embeddings.py
#   - protobuf<4.0: mediapipe uses deprecated MessageFactory.GetPrototype() removed in protobuf 5.x
#   - transformers==4.36.2: Tested configuration matching diffusers 0.27.0
#   - xformers removed: 0.0.22.post7 requires PyTorch 2.1, incompatible with torch-bin 2.9.x
{
  lib,
  pkgs,
  fetchFromGitHub,
  makeWrapper,
  stdenv,
  cudaSupport ? true, # GPU-accelerated ML tool - default true
}:

let
  version = "2025-01-29"; # Based on commit date

  # Force cudaSupport for torch-bin regardless of global nixpkgs config
  # This ensures torch-bin pulls CUDA variant even if cudaSupport is false globally
  cudaPkgs =
    if cudaSupport then
      import pkgs.path {
        system = pkgs.stdenv.hostPlatform.system;
        config = pkgs.config // {
          cudaSupport = true;
        };
      }
    else
      pkgs;

  # Override python to fix upstream test failures and add custom packages
  # Using Python 3.11 for tokenizers <0.19 compatibility (required by transformers 4.36.2)
  # tokenizers 0.15.x lacks Python 3.12 wheels
  python = cudaPkgs.python311.override {
    packageOverrides = self: super: {
      # Use pre-built torch binaries with CUDA support baked in
      # Must add cudaSupport/cudaPackages/cudaCapabilities attrs for xformers compatibility
      torch = super.torch-bin.overrideAttrs (old: {
        passthru = (old.passthru or { }) // {
          cudaSupport = cudaSupport;
          cudaPackages = cudaPkgs.cudaPackages;
          # Common CUDA capabilities for modern GPUs (Ada Lovelace, Ampere, etc.)
          cudaCapabilities = [
            "8.0"
            "8.6"
            "8.9"
            "9.0"
          ];
        };
      });
      torchvision = super.torchvision-bin;

      # scikit-image tests pull heavy deps - skip them
      scikit-image = super.scikit-image.overridePythonAttrs (old: {
        doCheck = false;
      });

      # accelerate tests fail in Nix sandbox (torch inductor needs filesystem access)
      accelerate = super.accelerate.overridePythonAttrs (old: {
        doCheck = false;
      });

      # peft tests require accelerate tests to pass first
      peft = super.peft.overridePythonAttrs (old: {
        doCheck = false;
      });

      # =========================================================================
      # Version-pinned packages for PersonaLive compatibility
      # These MUST match requirements_base.txt versions to avoid runtime errors
      # =========================================================================

      # Protobuf 3.20.3 - mediapipe uses MessageFactory.GetPrototype() removed in 5.x
      # Pure Python wheel works on all platforms including Python 3.12
      protobuf = self.buildPythonPackage {
        pname = "protobuf";
        version = "3.20.3";
        format = "wheel";

        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/8d/14/619e24a4c70df2901e1f4dbc50a6291eb63a759172558df326347dce1f0d/protobuf-3.20.3-py2.py3-none-any.whl";
          hash = "sha256-p8ptSIqo/38ynUxUWy262KwxRk8dixyHrRNGcXcx5Ns=";
        };

        doCheck = false;
        pythonImportsCheck = [ "google.protobuf" ];
      };

      # Diffusers 0.27.0 - newer versions have breaking API changes
      # get_1d_sincos_pos_embed_from_grid() was deprecated in 0.34.0, removed in 0.35.x
      diffusers = self.buildPythonPackage {
        pname = "diffusers";
        version = "0.27.0";
        format = "wheel";

        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/54/ea/3848667fc018341916a3677f9cc376154a381ba43e1dd08105b0777bc81c/diffusers-0.27.0-py3-none-any.whl";
          hash = "sha256-8mop7Eir7noJ/vPCB/9kjrOHE4+vjKE6YF85dgNsxww=";
        };

        propagatedBuildInputs = [
          self.importlib-metadata
          self.filelock
          self.huggingface-hub
          self.numpy
          self.regex
          self.requests
          self.safetensors
          self.pillow
        ];

        doCheck = false;
        pythonImportsCheck = [ "diffusers" ];
      };

      # Transformers 4.36.2 - tested configuration matching diffusers 0.27.0
      transformers = self.buildPythonPackage {
        pname = "transformers";
        version = "4.36.2";
        format = "wheel";

        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/20/0a/739426a81f7635b422fbe6cb8d1d99d1235579a6ac8024c13d743efa6847/transformers-4.36.2-py3-none-any.whl";
          hash = "sha256-RiBmxPdO5SUW8SiQ3MnscdGl6XmY22IWaEVRF6VDMPY=";
        };

        propagatedBuildInputs = [
          self.filelock
          self.huggingface-hub
          self.numpy
          self.packaging
          self.pyyaml
          self.regex
          self.requests
          self.safetensors
          self.tokenizers
          self.tqdm
        ];

        doCheck = false;
        pythonImportsCheck = [ "transformers" ];
      };

      # huggingface-hub 0.25.2 - last version with cached_download()
      # Required by diffusers 0.27.0 which imports this deprecated function
      # cached_download was removed in huggingface-hub 0.26+
      huggingface-hub = self.buildPythonPackage {
        pname = "huggingface-hub";
        version = "0.25.2";
        format = "wheel";

        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/64/09/a535946bf2dc88e61341f39dc507530411bb3ea4eac493e5ec833e8f35bd/huggingface_hub-0.25.2-py3-none-any.whl";
          hash = "sha256-GJfK+Izn+X/gEQYD2PZqwmTjumrM3zDNZswP7VKCrSU=";
        };

        propagatedBuildInputs = [
          self.filelock
          self.fsspec
          self.packaging
          self.pyyaml
          self.requests
          self.tqdm
          self.typing-extensions
        ];

        doCheck = false;
        pythonImportsCheck = [ "huggingface_hub" ];
      };

      # tokenizers 0.15.2 - required by transformers 4.36.2 (needs >=0.14,<0.19)
      # Using manylinux wheel with Rust bindings - cp311 for Python 3.11
      tokenizers = self.buildPythonPackage {
        pname = "tokenizers";
        version = "0.15.2";
        format = "wheel";

        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/15/0b/c09b2c0dc688c82adadaa0d5080983de3ce920f4a5cbadb7eaa5302ad251/tokenizers-0.15.2-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
          hash = "sha256-zNc6gnUcUjs/wx/4GUcC5K9Nsh3CDlWzDswgecXUPLc=";
        };

        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [ pkgs.stdenv.cc.cc.lib ];

        propagatedBuildInputs = [ self.huggingface-hub ];

        doCheck = false;
        pythonImportsCheck = [ "tokenizers" ];
      };

      # =========================================================================
      # Custom Python packages not in nixpkgs
      # =========================================================================

      # Mediapipe - Google's ML framework for face mesh detection (468 landmarks)
      # Pre-built wheel for Linux x86_64 - needs autoPatchelfHook for bundled libs
      # Using 0.10.14 with cp311 wheel for Python 3.11
      # Requires protobuf 3.x - pinned above to fix GetPrototype() errors
      mediapipe = self.buildPythonPackage {
        pname = "mediapipe";
        version = "0.10.14";
        format = "wheel";

        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/2f/ee/2e9e730dc4d98c8a9541b57bad173bebddf0e4c78f179acc100248c58066/mediapipe-0.10.14-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
          hash = "sha256-qAcygznnNW/aC7FN8S/tvx0zvfgWScX4ZmsAJrHMMLQ=";
        };

        nativeBuildInputs = [
          pkgs.autoPatchelfHook
        ];

        buildInputs = [
          pkgs.stdenv.cc.cc.lib # libstdc++
        ];

        propagatedBuildInputs = [
          self.absl-py
          self.attrs
          self.flatbuffers
          self.matplotlib
          self.numpy
          self.opencv4
          self.protobuf
          self.sounddevice
        ];

        # Mediapipe uses precompiled binaries - no tests needed
        doCheck = false;

        pythonImportsCheck = [ "mediapipe" ];
      };

      # Decord - efficient video reader for ML
      # Uses autoPatchelfHook to fix bundled library paths in manylinux wheel
      decord = self.buildPythonPackage {
        pname = "decord";
        version = "0.6.0";
        format = "wheel";

        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/11/79/936af42edf90a7bd4e41a6cac89c913d4b47fa48a26b042d5129a9242ee3/decord-0.6.0-py3-none-manylinux2010_x86_64.whl";
          hash = "sha256-UZl/IL6JWOI7fEBhukXQ782Gv/1f6BxpXQvv7g1EKXY=";
        };

        nativeBuildInputs = [
          pkgs.autoPatchelfHook
        ];

        buildInputs = [
          pkgs.stdenv.cc.cc.lib # libstdc++
          pkgs.bzip2
          pkgs.zlib
        ];

        propagatedBuildInputs = [
          self.numpy
        ];

        # Skip import check - the wheel has bundled libs that need runtime patching
        doCheck = false;
        dontCheckRuntimeDeps = true;

        # Allow bundled libraries with mangled names
        autoPatchelfIgnoreMissingDeps = [ "*" ];
      };

      # Markdown2 - fast Markdown to HTML converter
      markdown2 = self.buildPythonPackage {
        pname = "markdown2";
        version = "2.5.4";
        format = "wheel";

        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/b8/06/2697b5043c3ecb720ce0d21943f7cf5024c0b5b1e450506e9b21939019963/markdown2-2.5.4-py3-none-any.whl";
          hash = "sha256-PEspNOZ3vn/sDm8t5EEOEWaB9K1Q7I5bp1V75QbT9Dk=";
        };

        doCheck = false;
      };

      # xformers - Memory-efficient attention operations
      # Pre-built wheel to avoid 50GB+ RAM / multi-hour source build with CUDA
      # Version 0.0.33.post2 is compatible with PyTorch 2.5-2.9 (nixpkgs has 2.9.1)
      # Note: 0.0.34 requires PyTorch 2.10+ which isn't in nixpkgs yet
      # Uses stable ABI (cp39-abi3) for broad Python compatibility
      xformers = self.buildPythonPackage {
        pname = "xformers";
        version = "0.0.33.post2";
        format = "wheel";

        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/7d/c8/2957d8a8bf089a4e57f046867d4c9b31fc2e1d16013bc57cd7ae651a65b5/xformers-0.0.33.post2-cp39-abi3-manylinux_2_28_x86_64.whl";
          hash = "sha256-nqYDLe+mA5VVm2pEbCrpRSNnB+mNqr2I/qV80IZxwXQ=";
        };

        nativeBuildInputs = [ pkgs.autoPatchelfHook ];

        buildInputs = [
          pkgs.stdenv.cc.cc.lib # libstdc++
          cudaPkgs.cudaPackages.cuda_cudart
          cudaPkgs.cudaPackages.libcublas
          cudaPkgs.cudaPackages.cuda_nvrtc
        ];

        propagatedBuildInputs = [
          self.torch
          self.numpy
        ];

        # Skip checks - wheel has bundled CUDA kernels
        doCheck = false;
        dontCheckRuntimeDeps = true;

        # These libs are provided at runtime via Python imports:
        # - libtorch/libc10: torch-bin libs in site-packages (loaded when xformers imports torch)
        # - libcuda.so.1: nvidia driver via LD_LIBRARY_PATH
        autoPatchelfIgnoreMissingDeps = [
          "libc10.so"
          "libtorch.so"
          "libtorch_cpu.so"
          "libc10_cuda.so"
          "libtorch_cuda.so"
          "libcuda.so.1"
        ];

        pythonImportsCheck = [ "xformers" ];
      };
    };
  };

  # Python environment with all dependencies from requirements_base.txt
  # torch/torchvision are overridden to torch-bin/torchvision-bin above
  pythonEnv = python.withPackages (
    ps: with ps; [
      # Core ML frameworks - uses torch-bin via override above
      torch
      torchvision
      accelerate
      # xformers removed: requires PyTorch 2.1, incompatible with torch-bin 2.9.x
      # Use --acceleration none for online mode

      # Diffusion models
      diffusers
      transformers
      peft
      einops
      safetensors

      # Computer vision
      opencv4
      pillow
      scikit-image
      mediapipe # Custom package

      # Video processing
      av
      decord # Custom package

      # Web server (for online mode)
      fastapi
      uvicorn
      starlette
      pydantic
      python-multipart

      # Configuration & utilities
      omegaconf
      huggingface-hub
      tqdm
      numpy
      markdown2 # Custom package

      # Huggingface model downloading
      requests
    ]
  );

in
stdenv.mkDerivation {
  pname = "personalive";
  inherit version;

  src = fetchFromGitHub {
    owner = "GVCLab";
    repo = "PersonaLive";
    rev = "32f401d2053857b9d822b14cd63e861a16767bf4";
    hash = "sha256-w0xwz8sMncddGtrthrX33YtJbKgtRW8OCVWQZ+C31PM=";
  };

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [
    pythonEnv
    pkgs.ffmpeg
    pkgs.nodejs_22 # Required for web UI
  ]
  ++ lib.optionals stdenv.isLinux [
    pkgs.libv4l # V4L2 for webcam access
    pkgs.xorg.libX11
    pkgs.xorg.libXcursor
    pkgs.xorg.libXrandr
    pkgs.xorg.libXi
  ];

  dontBuild = true;

  installPhase = ''
        runHook preInstall

        # Install the application
        mkdir -p $out/lib/personalive
        cp -r . $out/lib/personalive/

        # Create bin directory
        mkdir -p $out/bin

        # =========================================================================
        # Offline inference wrapper (batch video generation)
        # =========================================================================
        cat > $out/bin/personalive << 'WRAPPER'
    #!/usr/bin/env bash
    set -e

    # Setup cache/working directory
    CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/personalive"
    WEIGHTS_DIR="$CACHE_DIR/pretrained_weights"
    WORK_DIR="$CACHE_DIR/runtime"
    mkdir -p "$WEIGHTS_DIR" "$WORK_DIR"

    # Copy app files if not present or version changed
    INSTALLED_VERSION=""
    [ -f "$WORK_DIR/.version" ] && INSTALLED_VERSION=$(cat "$WORK_DIR/.version")

    if [ ! -f "$WORK_DIR/inference_offline.py" ] || [ "$INSTALLED_VERSION" != "@version@" ]; then
      # Remove old runtime to ensure clean state
      [ -d "$WORK_DIR" ] && chmod -R u+w "$WORK_DIR" 2>/dev/null || true
      rm -rf "$WORK_DIR"
      mkdir -p "$WORK_DIR"

      # Copy app files and make writable (Nix store files are read-only)
      cp -r @out@/lib/personalive/* "$WORK_DIR/"
      chmod -R u+w "$WORK_DIR"

      # Track installed version
      echo "@version@" > "$WORK_DIR/.version"
    fi

    # Symlink weights directory to user cache (models downloaded at runtime)
    if [ -e "$WORK_DIR/pretrained_weights" ] || [ -L "$WORK_DIR/pretrained_weights" ]; then
      if [ ! -L "$WORK_DIR/pretrained_weights" ] || [ "$(readlink "$WORK_DIR/pretrained_weights")" != "$WEIGHTS_DIR" ]; then
        rm -rf "$WORK_DIR/pretrained_weights"
        ln -sf "$WEIGHTS_DIR" "$WORK_DIR/pretrained_weights"
      fi
    else
      ln -sf "$WEIGHTS_DIR" "$WORK_DIR/pretrained_weights"
    fi

    # Create output directory
    mkdir -p "$WORK_DIR/output"

    # Pre-flight check for model weights
    check_weights() {
      local missing=""
      [ ! -f "$WEIGHTS_DIR/sd-vae-ft-mse/config.json" ] && missing="$missing  - sd-vae-ft-mse (VAE model)\n"
      [ ! -f "$WEIGHTS_DIR/sd-image-variations-diffusers/model_index.json" ] && missing="$missing  - sd-image-variations-diffusers (base model)\n"
      [ ! -f "$WEIGHTS_DIR/personalive/denoising_unet.pth" ] && missing="$missing  - personalive (main weights)\n"

      if [ -n "$missing" ]; then
        echo "ERROR: Required model weights not found."
        echo ""
        echo "Missing:"
        printf "$missing"
        echo ""
        echo "Please download weights first (~10GB):"
        echo "  personalive-download"
        echo ""
        echo "Weights location: $WEIGHTS_DIR"
        exit 1
      fi
    }
    check_weights

    cd "$WORK_DIR"
    exec @pythonEnv@/bin/python inference_offline.py "$@"
    WRAPPER

        substituteInPlace $out/bin/personalive \
          --replace "@out@" "$out" \
          --replace "@pythonEnv@" "${pythonEnv}" \
          --replace "@version@" "${version}"
        chmod +x $out/bin/personalive

        # =========================================================================
        # Online inference wrapper (real-time webcam streaming)
        # =========================================================================
        cat > $out/bin/personalive-online << 'WRAPPER'
    #!/usr/bin/env bash
    set -e

    # Setup cache/working directory
    CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/personalive"
    WEIGHTS_DIR="$CACHE_DIR/pretrained_weights"
    WORK_DIR="$CACHE_DIR/runtime"
    mkdir -p "$WEIGHTS_DIR" "$WORK_DIR"

    # Copy app files if not present or version changed
    INSTALLED_VERSION=""
    [ -f "$WORK_DIR/.version" ] && INSTALLED_VERSION=$(cat "$WORK_DIR/.version")

    if [ ! -f "$WORK_DIR/inference_online.py" ] || [ "$INSTALLED_VERSION" != "@version@" ]; then
      [ -d "$WORK_DIR" ] && chmod -R u+w "$WORK_DIR" 2>/dev/null || true
      rm -rf "$WORK_DIR"
      mkdir -p "$WORK_DIR"
      cp -r @out@/lib/personalive/* "$WORK_DIR/"
      chmod -R u+w "$WORK_DIR"
      echo "@version@" > "$WORK_DIR/.version"
    fi

    # Symlink weights directory
    if [ -e "$WORK_DIR/pretrained_weights" ] || [ -L "$WORK_DIR/pretrained_weights" ]; then
      if [ ! -L "$WORK_DIR/pretrained_weights" ] || [ "$(readlink "$WORK_DIR/pretrained_weights")" != "$WEIGHTS_DIR" ]; then
        rm -rf "$WORK_DIR/pretrained_weights"
        ln -sf "$WEIGHTS_DIR" "$WORK_DIR/pretrained_weights"
      fi
    else
      ln -sf "$WEIGHTS_DIR" "$WORK_DIR/pretrained_weights"
    fi

    # Build web frontend if not already built
    if [ ! -d "$WORK_DIR/webcam/frontend/build" ]; then
      echo "Building web frontend (first run only)..."
      cd "$WORK_DIR/webcam/frontend"
      npm install --legacy-peer-deps 2>/dev/null || npm install
      npm run build
    fi

    # Pre-flight check for model weights
    check_weights() {
      local missing=""
      [ ! -f "$WEIGHTS_DIR/sd-vae-ft-mse/config.json" ] && missing="$missing  - sd-vae-ft-mse (VAE model)\n"
      [ ! -f "$WEIGHTS_DIR/sd-image-variations-diffusers/model_index.json" ] && missing="$missing  - sd-image-variations-diffusers (base model)\n"
      [ ! -f "$WEIGHTS_DIR/personalive/denoising_unet.pth" ] && missing="$missing  - personalive (main weights)\n"

      if [ -n "$missing" ]; then
        echo "ERROR: Required model weights not found."
        echo ""
        echo "Missing:"
        printf "$missing"
        echo ""
        echo "Please download weights first (~10GB):"
        echo "  personalive-download"
        echo ""
        echo "Weights location: $WEIGHTS_DIR"
        exit 1
      fi
    }
    check_weights

    cd "$WORK_DIR"

    # Default to no acceleration (xformers incompatible with torch-bin 2.9.x)
    # User can override with --acceleration xformers if they have compatible setup
    if [[ ! " $* " =~ " --acceleration " ]]; then
      exec @pythonEnv@/bin/python inference_online.py --acceleration none "$@"
    else
      exec @pythonEnv@/bin/python inference_online.py "$@"
    fi
    WRAPPER

        substituteInPlace $out/bin/personalive-online \
          --replace "@out@" "$out" \
          --replace "@pythonEnv@" "${pythonEnv}" \
          --replace "@version@" "${version}"
        chmod +x $out/bin/personalive-online

        # =========================================================================
        # Weight download wrapper
        # =========================================================================
        cat > $out/bin/personalive-download << 'WRAPPER'
    #!/usr/bin/env bash
    set -e

    CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/personalive"
    WEIGHTS_DIR="$CACHE_DIR/pretrained_weights"
    WORK_DIR="$CACHE_DIR/runtime"
    mkdir -p "$WEIGHTS_DIR" "$WORK_DIR"

    # Ensure runtime is set up
    if [ ! -f "$WORK_DIR/tools/download_weights.py" ]; then
      mkdir -p "$WORK_DIR"
      cp -r @out@/lib/personalive/* "$WORK_DIR/"
      chmod -R u+w "$WORK_DIR"
      echo "@version@" > "$WORK_DIR/.version"
    fi

    # Symlink weights directory
    ln -sfn "$WEIGHTS_DIR" "$WORK_DIR/pretrained_weights"

    cd "$WORK_DIR"
    echo "Downloading PersonaLive weights to $WEIGHTS_DIR..."
    exec @pythonEnv@/bin/python tools/download_weights.py "$@"
    WRAPPER

        substituteInPlace $out/bin/personalive-download \
          --replace "@out@" "$out" \
          --replace "@pythonEnv@" "${pythonEnv}" \
          --replace "@version@" "${version}"
        chmod +x $out/bin/personalive-download

        # Wrap all binaries with environment setup
        # CUDA runtime libs are added via LD_LIBRARY_PATH for GPU acceleration
        for bin in personalive personalive-online personalive-download; do
          wrapProgram $out/bin/$bin \
            --prefix PATH : ${
              lib.makeBinPath [
                pkgs.ffmpeg
                pkgs.nodejs_22
              ]
            } \
            ${lib.optionalString stdenv.isLinux "--prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.libv4l ]}"} \
            --prefix LD_LIBRARY_PATH : ${
              lib.makeLibraryPath [
                pkgs.cudaPackages.cudatoolkit
                pkgs.cudaPackages.cudnn
              ]
            }:/run/opengl-driver/lib
        done

        runHook postInstall
  '';

  meta = with lib; {
    description = "Real-time streamable diffusion framework for portrait animation";
    homepage = "https://github.com/GVCLab/PersonaLive";
    license = licenses.unfree; # Academic research only
    platforms = platforms.linux;
    maintainers = [ ];
    mainProgram = "personalive";
  };
}
