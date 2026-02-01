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
# Version Pinning Strategy:
#   We use buildEnv to layer pinned wheel packages ON TOP of the base Python env.
#   This preserves binary cache for all standard packages (h5py, astropy, opencv, etc.)
#   while overriding only the specific packages PersonaLive needs.
#
# Required version pins from requirements_base.txt:
#   - diffusers==0.27.0: Newer versions have breaking API changes in embeddings.py
#   - protobuf<4.0: mediapipe uses deprecated MessageFactory.GetPrototype() removed in protobuf 5.x
#   - transformers==4.36.2: Tested configuration matching diffusers 0.27.0
#   - tokenizers<0.19: Required by transformers 4.36.2
#   - huggingface-hub<0.26: diffusers 0.27.0 uses cached_download() removed in 0.26+
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

  # Force cudaSupport on UNSTABLE nixpkgs to fix tests AND get CUDA
  # We use pkgs.unstable.path to re-import unstable with forced config
  cudaPkgs =
    if cudaSupport then
      import pkgs.unstable.path {
        system = pkgs.stdenv.hostPlatform.system;
        config = pkgs.config // {
          cudaSupport = true;
        };
      }
    else
      pkgs.unstable;

  # Use Python 3.11 from the configured unstable set
  python = cudaPkgs.python311;
  pythonPkgs = python.pkgs;

  # ==========================================================================
  # Pinned packages as standalone derivations (wheels from PyPI)
  # These are layered on top of the base env, overriding nixpkgs versions
  # ==========================================================================

  # Protobuf 3.20.3 - mediapipe uses MessageFactory.GetPrototype() removed in 5.x
  pinnedProtobuf = pythonPkgs.buildPythonPackage {
    pname = "protobuf";
    version = "3.20.3";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/8d/14/619e24a4c70df2901e1f4dbc50a6291eb63a759172558df326347dce1f0d/protobuf-3.20.3-py2.py3-none-any.whl";
      hash = "sha256-p8ptSIqo/38ynUxUWy262KwxRk8dixyHrRNGcXcx5Ns=";
    };

    doCheck = false;
  };

  # huggingface-hub 0.25.2 - last version with cached_download()
  pinnedHuggingfaceHub = pythonPkgs.buildPythonPackage {
    pname = "huggingface-hub";
    version = "0.25.2";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/64/09/a535946bf2dc88e61341f39dc507530411bb3ea4eac493e5ec833e8f35bd/huggingface_hub-0.25.2-py3-none-any.whl";
      hash = "sha256-GJfK+Izn+X/gEQYD2PZqwmTjumrM3zDNZswP7VKCrSU=";
    };

    propagatedBuildInputs = with pythonPkgs; [
      filelock
      fsspec
      packaging
      pyyaml
      requests
      tqdm
      typing-extensions
    ];

    doCheck = false;
  };

  # tokenizers 0.15.2 - required by transformers 4.36.2 (needs >=0.14,<0.19)
  pinnedTokenizers = pythonPkgs.buildPythonPackage {
    pname = "tokenizers";
    version = "0.15.2";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/15/0b/c09b2c0dc688c82adadaa0d5080983de3ce920f4a5cbadb7eaa5302ad251/tokenizers-0.15.2-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
      hash = "sha256-zNc6gnUcUjs/wx/4GUcC5K9Nsh3CDlWzDswgecXUPLc=";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];

    propagatedBuildInputs = [ pinnedHuggingfaceHub ];

    doCheck = false;
  };

  # Transformers 4.36.2 - tested configuration matching diffusers 0.27.0
  pinnedTransformers = pythonPkgs.buildPythonPackage {
    pname = "transformers";
    version = "4.36.2";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/20/0a/739426a81f7635b422fbe6cb8d1d99d1235579a6ac8024c13d743efa6847/transformers-4.36.2-py3-none-any.whl";
      hash = "sha256-RiBmxPdO5SUW8SiQ3MnscdGl6XmY22IWaEVRF6VDMPY=";
    };

    propagatedBuildInputs = with pythonPkgs; [
      filelock
      pinnedHuggingfaceHub
      numpy
      packaging
      pyyaml
      regex
      requests
      safetensors
      pinnedTokenizers
      tqdm
    ];

    doCheck = false;
  };

  # Diffusers 0.27.0 - newer versions have breaking API changes
  pinnedDiffusers = pythonPkgs.buildPythonPackage {
    pname = "diffusers";
    version = "0.27.0";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/54/ea/3848667fc018341916a3677f9cc376154a381ba43e1dd08105b0777bc81c/diffusers-0.27.0-py3-none-any.whl";
      hash = "sha256-8mop7Eir7noJ/vPCB/9kjrOHE4+vjKE6YF85dgNsxww=";
    };

    propagatedBuildInputs = with pythonPkgs; [
      importlib-metadata
      filelock
      pinnedHuggingfaceHub
      numpy
      regex
      requests
      safetensors
      pillow
    ];

    doCheck = false;
  };

  # ==========================================================================
  # Custom packages not in nixpkgs
  # ==========================================================================

  # Mediapipe - Google's ML framework for face mesh detection (468 landmarks)
  pinnedMediapipe = pythonPkgs.buildPythonPackage {
    pname = "mediapipe";
    version = "0.10.14";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/2f/ee/2e9e730dc4d98c8a9541b57bad173bebddf0e4c78f179acc100248c58066/mediapipe-0.10.14-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
      hash = "sha256-qAcygznnNW/aC7FN8S/tvx0zvfgWScX4ZmsAJrHMMLQ=";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];

    propagatedBuildInputs = with pythonPkgs; [
      absl-py
      attrs
      flatbuffers
      matplotlib
      numpy
      opencv4
      pinnedProtobuf
      sounddevice
    ];

    doCheck = false;
  };

  # Decord - efficient video reader for ML
  pinnedDecord = pythonPkgs.buildPythonPackage {
    pname = "decord";
    version = "0.6.0";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/11/79/936af42edf90a7bd4e41a6cac89c913d4b47fa48a26b042d5129a9242ee3/decord-0.6.0-py3-none-manylinux2010_x86_64.whl";
      hash = "sha256-UZl/IL6JWOI7fEBhukXQ782Gv/1f6BxpXQvv7g1EKXY=";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [
      pkgs.stdenv.cc.cc.lib
      pkgs.bzip2
      pkgs.zlib
    ];

    propagatedBuildInputs = [ pythonPkgs.numpy ];

    doCheck = false;
    dontCheckRuntimeDeps = true;
    autoPatchelfIgnoreMissingDeps = [ "*" ];
  };

  # Markdown2 - fast Markdown to HTML converter
  pinnedMarkdown2 = pythonPkgs.buildPythonPackage {
    pname = "markdown2";
    version = "2.5.4";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/b8/06/2697b5043c3ecb720ce0d21943f7cf5024c0b5b1e450506e9b21939019963/markdown2-2.5.4-py3-none-any.whl";
      hash = "sha256-PEspNOZ3vn/sDm8t5EEOEWaB9K1Q7I5bp1V75QbT9Dk=";
    };

    doCheck = false;
  };

  # ==========================================================================
  # Python environment - uses cached binaries from nixpkgs where possible
  # Pinned packages are added explicitly to override nixpkgs versions
  # ==========================================================================
  pythonEnv = python.withPackages (
    ps: with ps; [
      # Core ML frameworks - use pre-built binaries
      torch-bin
      torchvision-bin
      accelerate
      # xformers removed: requires specific PyTorch version

      # Diffusion models - PINNED versions
      pinnedDiffusers
      pinnedTransformers
      peft
      einops
      safetensors

      # Computer vision - from binary cache
      opencv4
      pillow
      scikit-image
      pinnedMediapipe

      # Video processing
      av
      pinnedDecord

      # Web server (for online mode)
      fastapi
      uvicorn
      starlette
      pydantic
      python-multipart

      # Configuration & utilities
      omegaconf
      pinnedHuggingfaceHub
      tqdm
      numpy
      pinnedMarkdown2

      # Huggingface model downloading
      requests

      # Explicit pinned packages to ensure they're used
      pinnedProtobuf
      pinnedTokenizers
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
