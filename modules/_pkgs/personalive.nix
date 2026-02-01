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
#   torch-bin includes CUDA binaries. Runtime CUDA libs are added via LD_LIBRARY_PATH
#   in the wrapper scripts. No separate cudaPkgs import needed (avoids torch conflicts).
{
  lib,
  pkgs,
  fetchFromGitHub,
  makeWrapper,
  stdenv,
}:

let
  version = "2025-01-29"; # Based on commit date

  # Override python to fix upstream test failures and add custom packages
  # Using Python 3.12 for numpy 2.x compatibility with torch-bin
  # NOTE: torch-bin already includes CUDA support - no need for separate cudaPkgs
  python = pkgs.python312.override {
    packageOverrides = self: super: {
      # scikit-image tests pull heavy deps - skip them
      scikit-image = super.scikit-image.overridePythonAttrs (old: {
        doCheck = false;
      });

      # =========================================================================
      # Custom Python packages not in nixpkgs
      # =========================================================================

      # Mediapipe - Google's ML framework for face mesh detection (468 landmarks)
      # Pre-built wheel for Linux x86_64 - needs autoPatchelfHook for bundled libs
      mediapipe = self.buildPythonPackage {
        pname = "mediapipe";
        version = "0.10.21";
        format = "wheel";

        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/9f/99/5da7ae7f7e25847383bc2fe5a9adc7ce150dd371682f486c0666b407cad7/mediapipe-0.10.21-cp312-cp312-manylinux_2_28_x86_64.whl";
          hash = "sha256-lW6x68J1xinmGwhbLKuJw6W56TutG7EHNI2Y2vtaS7U=";
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
          url = "https://files.pythonhosted.org/packages/b8/06/2697b5043c3ecb720ce0d243fc7cf5024c0b5b1e450506e9b21939019963/markdown2-2.5.4-py3-none-any.whl";
          hash = "sha256-PEspNOZ3vn/sDm8t5EEOEWaB9K1Q7I5bp1V75QbT9Dk=";
        };

        doCheck = false;
      };
    };
  };

  # Python environment with all dependencies from requirements_base.txt
  # NOTE: Use source-built torch/torchvision (not -bin) to ensure consistent
  # CUDA configuration with the flake's nixpkgs.config.cudaSupport setting.
  # The -bin packages caused conflicts due to different torch derivations.
  pythonEnv = python.withPackages (
    ps: with ps; [
      # Core ML frameworks - source-built for CUDA consistency
      torch
      torchvision
      accelerate
      xformers # Memory-efficient attention

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

    cd "$WORK_DIR"

    # Default to xformers acceleration if not specified
    if [[ ! " $* " =~ " --acceleration " ]]; then
      exec @pythonEnv@/bin/python inference_online.py --acceleration xformers "$@"
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
