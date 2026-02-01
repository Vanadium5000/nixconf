# Deep-Live-Cam - Real-time face swap and video deepfake
# https://github.com/hacksider/Deep-Live-Cam
#
# Models are downloaded at runtime to ~/.cache/deep-live-cam/models/
# Required models: GFPGANv1.4.pth, inswapper_128_fp16.onnx
#
# Note: opennsfw2 intentionally excluded - optional NSFW filter adds ~2GB tensorflow dep
# The --nsfw-filter flag is unsupported in this build
{
  lib,
  pkgs,
  fetchFromGitHub,
  makeWrapper,
  stdenv,
  cudaSupport ? true, # Default true - this is a GPU-accelerated ML tool
}:

let
  version = "2.4";

  # Create a pkgs instance with cudaSupport enabled for torch-bin
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

  # Build custom Python packages not in nixpkgs
  # Override python to fix upstream test failures and avoid heavy transitive deps
  python = cudaPkgs.python312.override {
    packageOverrides = self: super: {
      # imageio pulls astropy as optional dep - astropy uses 30GB RAM to build
      # Override to remove astropy from the dependency chain entirely
      imageio = super.imageio.overridePythonAttrs (old: {
        # Remove optional deps that pull in astropy
        propagatedBuildInputs = builtins.filter (
          p:
          !(builtins.elem (p.pname or "") [
            "astropy"
            "pyav"
          ])
        ) (old.propagatedBuildInputs or [ ]);
        # Skip tests that require astropy
        doCheck = false;
      });

      # scikit-image tests pull heavy deps - skip them
      scikit-image = super.scikit-image.overridePythonAttrs (old: {
        doCheck = false;
      });

      # albumentations tests are slow and unnecessary
      albumentations = super.albumentations.overridePythonAttrs (old: {
        doCheck = false;
      });
    };
  };

  # Darkdetect - dependency of customtkinter
  darkdetect = python.pkgs.buildPythonPackage {
    pname = "darkdetect";
    version = "0.8.0";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/py3/d/darkdetect/darkdetect-0.8.0-py3-none-any.whl";
      hash = "sha256-p1Ccz1F+qtkrMcIU9ZPbzxOOqKQ7KTVAa71WXhVSeoU=";
    };

    doCheck = false;
  };

  # CustomTkinter - modern tkinter widgets (wheel format)
  customtkinter = python.pkgs.buildPythonPackage rec {
    pname = "customtkinter";
    version = "5.2.2";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/py3/c/customtkinter/customtkinter-${version}-py3-none-any.whl";
      hash = "sha256-FK0+fNPLO562QrnU6HEa6A0/efuCVFrRElju/7Lms3w=";
    };

    propagatedBuildInputs = [
      darkdetect
      python.pkgs.packaging
      python.pkgs.typing-extensions
    ];

    # Tkinter is provided via python withPackages
    doCheck = false;
  };

  # Easydict - dependency of insightface (wheel format)
  easydict = python.pkgs.buildPythonPackage rec {
    pname = "easydict";
    version = "1.13";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/py3/e/easydict/easydict-${version}-py3-none-any.whl";
      hash = "sha256-a3h9r03K9jd7StlAOlzuWoatvAyppbz1QQ6ZAgAq6sI=";
    };

    doCheck = false;
  };

  # Prettytable - dependency of insightface (wheel format)
  prettytable = python.pkgs.buildPythonPackage rec {
    pname = "prettytable";
    version = "3.10.0";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/py3/p/prettytable/prettytable-${version}-py3-none-any.whl";
      hash = "sha256-ZTbvrwdX/ap9IueLOqw7aeobcgBTjCxpldZJNlvdq5I=";
    };

    propagatedBuildInputs = [ python.pkgs.wcwidth ];

    doCheck = false;
  };

  # Insightface - face analysis library (built from source for numpy 2.x compatibility)
  # Pre-built wheels are compiled against numpy 1.x which causes ABI incompatibility:
  # "numpy.dtype size changed, may indicate binary incompatibility. Expected 96, got 88"
  insightface = python.pkgs.buildPythonPackage rec {
    pname = "insightface";
    version = "0.7.3";
    format = "setuptools";

    src = pkgs.fetchPypi {
      inherit pname version;
      hash = "sha256-8ZH3GWEuuzcBj0GTaBRQBUTND4bm/NZ2wCPzVMZo3fc=";
    };

    nativeBuildInputs = [
      python.pkgs.cython
    ];

    buildInputs = [
      # Required for Cython compilation of mesh_core_cython
      python.pkgs.numpy
    ];

    propagatedBuildInputs = with python.pkgs; [
      numpy
      onnx
      onnxruntime
      pillow
      requests
      scipy
      scikit-learn
      scikit-image
      matplotlib
      easydict
      albumentations
      prettytable
      tqdm
      cython
    ];

    # Build requires numpy headers
    preBuild = ''
      export CFLAGS="-I${python.pkgs.numpy}/${python.sitePackages}/numpy/_core/include"
    '';

    doCheck = false;

    pythonImportsCheck = [ "insightface" ];
  };

  # CV2 Enumerate Cameras (wheel format - pure python)
  cv2-enumerate-cameras = python.pkgs.buildPythonPackage rec {
    pname = "cv2_enumerate_cameras";
    version = "1.1.15";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/py3/c/cv2_enumerate_cameras/cv2_enumerate_cameras-${version}-py3-none-any.whl";
      hash = "sha256-4Zys6daMy+pAyJngM/MJlJJpsvjvpOxApzr36DCare4=";
    };

    propagatedBuildInputs = [ python.pkgs.opencv4 ];

    doCheck = false;
  };

  # Select onnxruntime based on CUDA support
  onnxruntimePkg =
    if cudaSupport then
      python.pkgs.onnxruntime # GPU version handled via LD_LIBRARY_PATH
    else
      python.pkgs.onnxruntime;

  # Python environment with all dependencies
  pythonEnv = python.withPackages (
    ps: with ps; [
      # Core dependencies from requirements.txt
      numpy
      opencv4
      pillow
      psutil
      tqdm
      requests
      typing-extensions
      protobuf

      # ML/AI frameworks
      onnx
      onnxruntimePkg
      torch-bin # Pre-built binaries for faster install
      torchvision-bin

      # Custom packages
      insightface
      cv2-enumerate-cameras
      customtkinter

      # GUI
      tkinter
    ]
  );

in
stdenv.mkDerivation {
  pname = "deep-live-cam";
  inherit version;

  src = fetchFromGitHub {
    owner = "hacksider";
    repo = "Deep-Live-Cam";
    rev = version;
    hash = "sha256-Z+qeXYzgTr0l0d2YSzjMr4X8DGkkpcqE36vXkkThehE=";
  };

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [
    pythonEnv
    pkgs.ffmpeg
  ]
  ++ lib.optionals stdenv.isLinux [
    pkgs.xorg.libX11
    pkgs.xorg.libXcursor
    pkgs.xorg.libXrandr
    pkgs.xorg.libXi
  ];

  dontBuild = true;

  postPatch = ''
    # Patch model paths to use XDG cache directory
    # The app looks for models in ./models/ relative to run.py
    # We'll handle this via wrapper by changing to a writable directory

    # Ensure the app can find ffmpeg
    substituteInPlace modules/processors/frame/core.py \
      --replace-quiet "ffmpeg" "${pkgs.ffmpeg}/bin/ffmpeg" || true

    # Remove TensorFlow dependency - it's only used for GPU memory management
    # which is optional (PyTorch/ONNX handle their own memory)
    # This saves ~2GB of dependencies
    substituteInPlace modules/core.py \
      --replace-fail "import tensorflow" "tensorflow = None  # Patched out - not needed for ONNX/PyTorch" \
      --replace-fail "gpus = tensorflow.config.experimental.list_physical_devices('GPU')" "gpus = []  # TensorFlow patched out" \
      --replace-fail "tensorflow.config.experimental.set_memory_growth(gpu, True)" "pass  # TensorFlow patched out"
  '';

  installPhase = ''
    runHook preInstall

    # Install the application
    mkdir -p $out/lib/deep-live-cam
    cp -r . $out/lib/deep-live-cam/

    # Create wrapper script
    mkdir -p $out/bin

    # The wrapper:
    # 1. Sets up the cache directory for models
    # 2. Creates symlink to models dir if needed
    # 3. Adds CUDA libraries if enabled
    # 4. Runs the app
    cat > $out/bin/deep-live-cam << 'WRAPPER'
    #!/usr/bin/env bash
    set -e

    # Setup cache directory for models
    CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/deep-live-cam"
    MODELS_DIR="$CACHE_DIR/models"
    mkdir -p "$MODELS_DIR"

    # Create working directory with symlinked models
    WORK_DIR="$CACHE_DIR/runtime"
    mkdir -p "$WORK_DIR"

    # Copy app files if not present or version changed
    INSTALLED_VERSION=""
    [ -f "$WORK_DIR/.version" ] && INSTALLED_VERSION=$(cat "$WORK_DIR/.version")
    
    if [ ! -f "$WORK_DIR/run.py" ] || [ "$INSTALLED_VERSION" != "@version@" ]; then
      # Remove old runtime to ensure clean state
      # Files from Nix store are read-only, need to fix permissions first
      [ -d "$WORK_DIR" ] && chmod -R u+w "$WORK_DIR" 2>/dev/null || true
      rm -rf "$WORK_DIR"
      mkdir -p "$WORK_DIR"
      
      # Copy app files and make writable (Nix store files are read-only)
      cp -r @out@/lib/deep-live-cam/* "$WORK_DIR/"
      chmod -R u+w "$WORK_DIR"
      rm -rf "$WORK_DIR/models"
      
      # Track installed version
      echo "@version@" > "$WORK_DIR/.version"
    fi

    # Ensure models symlink exists and points to user cache
    # Remove if it's a directory or broken symlink, then recreate
    if [ -e "$WORK_DIR/models" ] || [ -L "$WORK_DIR/models" ]; then
      if [ ! -L "$WORK_DIR/models" ] || [ "$(readlink "$WORK_DIR/models")" != "$MODELS_DIR" ]; then
        rm -rf "$WORK_DIR/models"
        ln -sf "$MODELS_DIR" "$WORK_DIR/models"
      fi
    else
      ln -sf "$MODELS_DIR" "$WORK_DIR/models"
    fi

    cd "$WORK_DIR"
    exec @pythonEnv@/bin/python run.py "$@"
    WRAPPER

    substituteInPlace $out/bin/deep-live-cam \
      --replace "@out@" "$out" \
      --replace "@pythonEnv@" "${pythonEnv}" \
      --replace "@version@" "${version}"

    chmod +x $out/bin/deep-live-cam

    # Wrap with environment setup
    wrapProgram $out/bin/deep-live-cam \
      --prefix PATH : ${lib.makeBinPath [ pkgs.ffmpeg ]} \
      ${lib.optionalString cudaSupport ''
        --prefix LD_LIBRARY_PATH : ${
          lib.makeLibraryPath [
            cudaPkgs.cudaPackages.cudatoolkit
            cudaPkgs.cudaPackages.cudnn
          ]
        }:/run/opengl-driver/lib \
        --add-flags "--execution-provider cuda"
      ''}

    runHook postInstall
  '';

  meta = with lib; {
    description = "Real-time face swap and one-click video deepfake with only a single image";
    homepage = "https://github.com/hacksider/Deep-Live-Cam";
    license = licenses.agpl3Only;
    platforms = platforms.linux;
    maintainers = [ ];
    mainProgram = "deep-live-cam";
  };
}
