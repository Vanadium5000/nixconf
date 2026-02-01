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
#   Uses torch-bin (pre-built CUDA binaries) via package override pattern.
#   This ensures ALL packages that depend on torch use torch-bin, not source-built torch.
#   Runtime CUDA libs are added via LD_LIBRARY_PATH in wrapper scripts.
#
# Build Optimization Strategy:
#   We use python.pkgs.override to replace torch/torchvision with pre-built binaries.
#   This prevents transitive dependencies (accelerate, peft, etc.) from pulling in
#   source-built torch which takes 4+ hours to compile.
#
#   Heavy packages (opencv, scikit-image) are fetched as pre-built wheels from PyPI
#   to avoid lengthy C++ compilation (~30-60 mins each).
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

  # Create a pkgs instance with cudaSupport enabled for torch-bin
  # This ensures torch-bin pulls CUDA variant regardless of global config
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

  # ==========================================================================
  # Python with package overrides (CRITICAL for build performance)
  # ==========================================================================
  # Override packages at the package-set level to ensure ALL transitive
  # dependencies use our preferred versions instead of pulling in nixpkgs
  # versions that trigger expensive source builds.
  #
  # Key optimizations:
  # 1. torch/torchvision → pre-built binaries (saves 4+ hours)
  # 2. Pinned versions for API compatibility (diffusers, transformers, etc.)
  # 3. Wheel packages for heavy C++ deps (opencv, imageio without pillow-heif)
  #
  # Without these overrides, packages like accelerate, peft, einops would pull
  # in their own dependencies from nixpkgs, causing duplicate builds and
  # incompatible version conflicts.
  cudaPython = cudaPkgs.python311Packages.override {
    overrides = pyFinal: pyPrev: {
      # Pre-built ML frameworks (saves 4+ hours of compilation)
      torch = pyPrev.torch-bin;
      torchvision = pyPrev.torchvision-bin;

      # Pinned packages - defined below, referenced here to override nixpkgs versions
      # This ensures accelerate, peft, einops, etc. use OUR versions
      diffusers = pinnedDiffusers pyFinal;
      transformers = pinnedTransformers pyFinal;
      huggingface-hub = pinnedHuggingfaceHub pyFinal;
      tokenizers = pinnedTokenizers pyFinal;
      protobuf = pinnedProtobuf pyFinal;

      # imageio wheel without pillow-heif dep (pillow-heif pulls opencv-4.12.0)
      imageio = pinnedImageio pyFinal;

      # accelerate wheel - nixpkgs version fails tests in sandbox (torch.inductor error)
      accelerate = pinnedAccelerate pyFinal;

      # peft 0.8.2 - compatible with transformers 4.36.2 (newer versions need EncoderDecoderCache from 4.39+)
      peft = pinnedPeft pyFinal;

      # pydevd - debugger that fails tests in sandbox (subprocess issues)
      # Pulled in via omegaconf, not needed at runtime
      pydevd = pyPrev.pydevd.overridePythonAttrs { doCheck = false; };
    };
  };

  # Use the overridden package set for all Python packages
  python = cudaPython.python;
  pythonPkgs = cudaPython;

  # ==========================================================================
  # Pinned packages as functions (for use in override)
  # These are defined as functions taking pyPkgs to allow referencing in the
  # cudaPython override above. This ensures transitive deps use our versions.
  # ==========================================================================

  # Protobuf 3.20.3 - mediapipe uses MessageFactory.GetPrototype() removed in 5.x
  pinnedProtobuf = pyPkgs: pyPkgs.buildPythonPackage {
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
  pinnedHuggingfaceHub = pyPkgs: pyPkgs.buildPythonPackage {
    pname = "huggingface-hub";
    version = "0.25.2";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/64/09/a535946bf2dc88e61341f39dc507530411bb3ea4eac493e5ec833e8f35bd/huggingface_hub-0.25.2-py3-none-any.whl";
      hash = "sha256-GJfK+Izn+X/gEQYD2PZqwmTjumrM3zDNZswP7VKCrSU=";
    };

    propagatedBuildInputs = with pyPkgs; [
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
  pinnedTokenizers = pyPkgs: pyPkgs.buildPythonPackage {
    pname = "tokenizers";
    version = "0.15.2";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/15/0b/c09b2c0dc688c82adadaa0d5080983de3ce920f4a5cbadb7eaa5302ad251/tokenizers-0.15.2-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
      hash = "sha256-zNc6gnUcUjs/wx/4GUcC5K9Nsh3CDlWzDswgecXUPLc=";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];

    propagatedBuildInputs = [ pyPkgs.huggingface-hub ]; # Uses override version

    doCheck = false;
  };

  # Transformers 4.36.2 - tested configuration matching diffusers 0.27.0
  pinnedTransformers = pyPkgs: pyPkgs.buildPythonPackage {
    pname = "transformers";
    version = "4.36.2";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/20/0a/739426a81f7635b422fbe6cb8d1d99d1235579a6ac8024c13d743efa6847/transformers-4.36.2-py3-none-any.whl";
      hash = "sha256-RiBmxPdO5SUW8SiQ3MnscdGl6XmY22IWaEVRF6VDMPY=";
    };

    propagatedBuildInputs = with pyPkgs; [
      filelock
      huggingface-hub # Uses override version
      numpy
      packaging
      pyyaml
      regex
      requests
      safetensors
      tokenizers # Uses override version
      tqdm
    ];

    doCheck = false;
  };

  # Diffusers 0.27.0 - newer versions have breaking API changes
  pinnedDiffusers = pyPkgs: pyPkgs.buildPythonPackage {
    pname = "diffusers";
    version = "0.27.0";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/54/ea/3848667fc018341916a3677f9cc376154a381ba43e1dd08105b0777bc81c/diffusers-0.27.0-py3-none-any.whl";
      hash = "sha256-8mop7Eir7noJ/vPCB/9kjrOHE4+vjKE6YF85dgNsxww=";
    };

    propagatedBuildInputs = with pyPkgs; [
      importlib-metadata
      filelock
      huggingface-hub # Uses override version
      numpy
      regex
      requests
      safetensors
      pillow
    ];

    doCheck = false;
  };

  # imageio 2.36.1 wheel - avoids nixpkgs version that pulls pillow-heif → opencv
  pinnedImageio = pyPkgs: pyPkgs.buildPythonPackage {
    pname = "imageio";
    version = "2.36.1";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/5c/f9/f78e7f5ac8077c481bf6b43b8bc736605363034b3d5eb3ce8eb79f53f5f1/imageio-2.36.1-py3-none-any.whl";
      hash = "sha256-IKvSyuWOVcoa+Kjc9DKTM2pZrfA5HxkXv4UYYzz8LN8=";
    };

    propagatedBuildInputs = with pyPkgs; [
      numpy
      pillow
    ];

    doCheck = false;
  };

  # accelerate 1.11.0 wheel - nixpkgs version fails tests in sandbox (torch.inductor error)
  pinnedAccelerate = pyPkgs: pyPkgs.buildPythonPackage {
    pname = "accelerate";
    version = "1.11.0";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/77/85/85951bc0f9843e2c10baaa1b6657227056095de08f4d1eea7d8b423a6832/accelerate-1.11.0-py3-none-any.whl";
      hash = "sha256-pij6a+sGm45UlGD8RJE11b2Nc+ehH9CfC8n8Ss5/BvE=";
    };

    propagatedBuildInputs = with pyPkgs; [
      numpy
      packaging
      psutil
      pyyaml
      torch # Uses override version (torch-bin)
      huggingface-hub # Uses override version
      safetensors
    ];

    doCheck = false;
  };

  # peft 0.8.2 - compatible with transformers 4.36.2
  # Newer versions (0.14+) require EncoderDecoderCache which was added in transformers 4.39+
  pinnedPeft = pyPkgs: pyPkgs.buildPythonPackage {
    pname = "peft";
    version = "0.8.2";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/07/63/168af5aa8dbda9c23ad774a4c1d311cfe220c634e0d05a3a82a7cae01bd8/peft-0.8.2-py3-none-any.whl";
      hash = "sha256-SpyBw45on9QEOydXzQ4rUmqbi4/QT4RC3yxIJLMsJQU=";
    };

    propagatedBuildInputs = with pyPkgs; [
      numpy
      packaging
      psutil
      pyyaml
      torch # Uses override version (torch-bin)
      transformers # Uses override version (pinnedTransformers)
      huggingface-hub # Uses override version
      safetensors
      accelerate # Uses override version (pinnedAccelerate)
    ];

    doCheck = false;
  };

  # ==========================================================================
  # Custom packages not in nixpkgs (use pythonPkgs after override is applied)
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
      pinnedOpencv # Use wheel instead of opencv4 to avoid source build
      protobuf # Uses override version (pinnedProtobuf)
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
  # Heavy packages as wheels (avoids 30-60 min source builds each)
  # ==========================================================================

  # OpenCV-Python-Headless - pre-built wheel avoids 30-60 min C++ compilation
  # Using headless variant since PersonaLive doesn't need GUI windows
  # Version 4.13.0.90+ required for NumPy 2.x support
  pinnedOpencv = pythonPkgs.buildPythonPackage {
    pname = "opencv-python-headless";
    version = "4.13.0.90";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/fc/13/af150685be342dc09bfb0824e2a280020ccf1c7fc64e15a31d9209016aa9/opencv_python_headless-4.13.0.90-cp37-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64.whl";
      hash = "sha256-28H0Yl5a86gOvb2EOAInwPRFIoWI8lIbEa9HcQysobo=";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [
      pkgs.stdenv.cc.cc.lib
      pkgs.libGL
      pkgs.glib
      pkgs.xorg.libX11
      pkgs.xorg.libXext
    ];

    propagatedBuildInputs = with pythonPkgs; [ numpy ];

    doCheck = false;
    dontCheckRuntimeDeps = true;
  };

  # Scikit-image - pre-built wheel avoids source build and broken pytest-doctestplus
  # The nixpkgs version pulls in astropy → pytest-doctestplus which has numpy compat issues
  pinnedSkimage = pythonPkgs.buildPythonPackage {
    pname = "scikit-image";
    version = "0.24.0";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/ad/96/138484302b8ec9a69cdf65e8d4ab47a640a3b1a8ea3c437e1da3e1a5a6b8/scikit_image-0.24.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
      hash = "sha256-+iezoNutgHuWa42y142nNMuBLKR4f3+7FDdkgAzi+pw=";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];

    propagatedBuildInputs = with pythonPkgs; [
      numpy
      scipy
      networkx
      pillow
      imageio # Uses override version (pinnedImageio) - no pillow-heif dep
      tifffile
      packaging
      lazy-loader
    ];

    doCheck = false;
    dontCheckRuntimeDeps = true;
  };

  # ==========================================================================
  # Python environment - uses overridden package set
  # ==========================================================================
  # Key optimization: We use pythonPkgs (cudaPython with overrides) directly
  # instead of `ps` from withPackages. This ensures ALL packages that depend
  # on torch, transformers, diffusers, etc. automatically use our overridden
  # versions, eliminating duplicate builds and version conflicts.
  #
  # Packages like accelerate, peft, einops now get:
  # - torch-bin instead of source-built torch
  # - pinnedTransformers instead of nixpkgs transformers
  # - pinnedDiffusers instead of nixpkgs diffusers
  # - pinnedImageio instead of nixpkgs imageio (which pulls pillow-heif → opencv)
  pythonEnv = python.withPackages (
    _: with pythonPkgs; [
      # Core ML frameworks - resolved to torch-bin via override
      torch # Resolves to torch-bin via cudaPython override
      torchvision # Resolves to torchvision-bin via cudaPython override
      accelerate # Now uses torch-bin and pinnedTransformers via override chain
      # xformers removed: requires specific PyTorch version

      # Diffusion models - use override versions automatically
      diffusers # Resolves to pinnedDiffusers via override
      transformers # Resolves to pinnedTransformers via override
      peft # Now uses torch-bin and pinnedTransformers via override chain
      einops
      safetensors

      # Computer vision - wheels to avoid source builds
      pinnedOpencv # Replaces opencv4 - avoids 30-60 min C++ build
      pillow
      pinnedSkimage # Replaces scikit-image - uses pinnedImageio, avoids opencv dep
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
      huggingface-hub # Resolves to pinnedHuggingfaceHub via override
      tqdm
      numpy
      pinnedMarkdown2

      # Huggingface model downloading
      requests

      # Explicit pinned packages to ensure they're used
      protobuf # Resolves to pinnedProtobuf via override
      tokenizers # Resolves to pinnedTokenizers via override
      imageio # Resolves to pinnedImageio via override
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

    # Generate self-signed SSL certificate for Secure Context (required for webcam access)
    # Browsers block navigator.mediaDevices (webcam) on insecure contexts (http://)
    if [ ! -f "$WORK_DIR/cert.pem" ] || [ ! -f "$WORK_DIR/key.pem" ]; then
      echo "Generating self-signed SSL certificate for Secure Context..."
      openssl req -x509 -newkey rsa:4096 -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" \
        -days 365 -nodes -subj "/CN=localhost" 2>/dev/null
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

    # SSL args for Secure Context
    SSL_ARGS="--ssl-certfile $WORK_DIR/cert.pem --ssl-keyfile $WORK_DIR/key.pem"

    echo "Starting PersonaLive with SSL (required for webcam)..."
    echo "URL: https://0.0.0.0:7860 (Accept the self-signed certificate warning)"

    # Default to no acceleration (xformers incompatible with torch-bin 2.9.x)
    # User can override with --acceleration xformers if they have compatible setup
    if [[ ! " $* " =~ " --acceleration " ]]; then
      exec @pythonEnv@/bin/python inference_online.py $SSL_ARGS --acceleration none "$@"
    else
      exec @pythonEnv@/bin/python inference_online.py $SSL_ARGS "$@"
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
                pkgs.openssl
              ]
            } \
            ${lib.optionalString stdenv.isLinux "--prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.libv4l ]}"} \
            ${lib.optionalString cudaSupport ''
              --prefix LD_LIBRARY_PATH : ${
                lib.makeLibraryPath [
                  cudaPkgs.cudaPackages.cudatoolkit
                  cudaPkgs.cudaPackages.cudnn
                ]
              }:/run/opengl-driver/lib \
            ''}
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
