# Deep-Live-Cam - Real-time face swap and video deepfake
# https://github.com/hacksider/Deep-Live-Cam
#
# Models are downloaded at runtime to ~/.cache/deep-live-cam/models/
# Required models: GFPGANv1.4.pth, inswapper_128_fp16.onnx
{
  lib,
  pkgs,
  fetchFromGitHub,
  makeWrapper,
  stdenv,
  cudaSupport ? false,
}:

let
  version = "2.4";

  # Build custom Python packages not in nixpkgs
  python = pkgs.python311;

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

  # Insightface - face analysis library
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
      python.pkgs.setuptools
    ];

    propagatedBuildInputs = with python.pkgs; [
      numpy
      onnx
      pillow
      requests
      scipy
      scikit-learn
      matplotlib
      easydict
      albumentations
      prettytable
      tqdm
    ];

    # Skip tests - require model downloads
    doCheck = false;

    # Disable Cython compilation issues
    preBuild = ''
      export INSIGHTFACE_USE_CYTHON=0
    '';
  };

  # OpenNSFW2 - content safety filter (uses pyproject.toml)
  opennsfw2 = python.pkgs.buildPythonPackage rec {
    pname = "opennsfw2";
    version = "0.10.2";
    format = "pyproject";

    src = pkgs.fetchPypi {
      inherit pname version;
      hash = "sha256-xs6gcy3A8Y52YWXAg0JXechMpqAfEWm/pdDUqgUxHk8=";
    };

    nativeBuildInputs = [ python.pkgs.setuptools ];

    # All runtime deps required by opennsfw2's pyproject.toml
    propagatedBuildInputs = with python.pkgs; [
      numpy
      pillow
      gdown
      matplotlib
      opencv4
      scikit-image
      tensorflow
      tqdm
    ];

    doCheck = false;
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
      tensorflow # For opennsfw2

      # Custom packages
      insightface
      opennsfw2
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

    # Symlink models directory into working dir
    if [ ! -L "$WORK_DIR/models" ]; then
      ln -sf "$MODELS_DIR" "$WORK_DIR/models"
    fi

    # Copy app files if not present (for locales, etc.)
    if [ ! -f "$WORK_DIR/run.py" ]; then
      cp -r @out@/lib/deep-live-cam/* "$WORK_DIR/"
      # Make models a symlink again (cp overwrites it)
      rm -rf "$WORK_DIR/models"
      ln -sf "$MODELS_DIR" "$WORK_DIR/models"
    fi

    cd "$WORK_DIR"
    exec @pythonEnv@/bin/python run.py "$@"
    WRAPPER

    substituteInPlace $out/bin/deep-live-cam \
      --replace "@out@" "$out" \
      --replace "@pythonEnv@" "${pythonEnv}"

    chmod +x $out/bin/deep-live-cam

    # Wrap with environment setup
    wrapProgram $out/bin/deep-live-cam \
      --prefix PATH : ${lib.makeBinPath [ pkgs.ffmpeg ]} \
      ${lib.optionalString cudaSupport ''
        --prefix LD_LIBRARY_PATH : ${
          lib.makeLibraryPath [
            pkgs.linuxPackages.nvidia_x11
            pkgs.cudaPackages.cudatoolkit
            pkgs.cudaPackages.cudnn
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
