{
  lib,
  pkgs,
  python312Packages,
  fetchFromGitHub,
  fetchurl,
  ffmpeg,
  makeWrapper,
  stdenv,
}:

let
  version = "0.0.4";

  # Pre-fetch ML models as fixed-output derivations
  yoloModel = fetchurl {
    url = "https://github.com/linkedlist771/SoraWatermarkCleaner/releases/download/V0.0.1/best.pt";
    hash = "sha256-ebRBcBEb0gbUlklms7Na3vGzsV56z2QnqV01oscV+Yc=";
  };

  lamaModel = fetchurl {
    url = "https://github.com/Sanster/models/releases/download/add_big_lama/big-lama.pt";
    hash = "sha256-NEx3u8sVjxfdFDBw0eeJ84pmwEICMRrjoljvZmZ6nqk=";
  };

  # Ruptures is missing from nixpkgs, so we package it here
  ruptures = python312Packages.buildPythonPackage rec {
    pname = "ruptures";
    version = "1.1.9";
    pyproject = true;

    src = python312Packages.fetchPypi {
      inherit pname version;
      hash = "sha256-qpQPPAIjXauUdT/xVon466yhDIPaccspy7f5gd+jYtw=";
    };

    build-system = [
      python312Packages.setuptools
      python312Packages.setuptools-scm
      python312Packages.cython
      python312Packages.oldest-supported-numpy
    ];
    dependencies = with python312Packages; [
      numpy
      scipy
    ];

    # Fix version detection failure in setup.cfg
    postPatch = ''
      substituteInPlace setup.cfg \
        --replace "attr: ruptures.__version__" "${version}" || true
    '';

    doCheck = false; # Skip tests to save time/dependencies
  };

  pythonEnv = python312Packages.python.withPackages (
    ps: with ps; [
      # Core ML
      torch
      torchvision
      ultralytics
      diffusers
      transformers
      einops
      huggingface-hub
      ruptures
      mmcv

      # Image/Video processing
      opencv4
      ffmpeg-python
      pillow

      # CLI and utilities
      fire
      rich
      tqdm
      loguru
      omegaconf
      pyyaml

      # Data processing
      numpy
      pandas
      scipy
      scikit-learn

      # Web (optional, for streamlit/fastapi modes)
      aiofiles
      httpx
      requests
      pydantic
    ]
  );

in
stdenv.mkDerivation {
  pname = "sora-watermark-cleaner";
  inherit version;

  src = fetchFromGitHub {
    owner = "linkedlist771";
    repo = "SoraWatermarkCleaner";
    rev = "V${version}";
    hash = "sha256-xvzZT6Mi/HAEZ2inOWLdxQ5P4fvsq6ujP8918uh9CE8=";
  };

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [
    pythonEnv
    ffmpeg
  ];

  # No build phase needed - it's a Python application
  dontBuild = true;

  postPatch = ''
        # Fix deprecated torch.cuda.amp.autocast which fails in newer torch versions
        substituteInPlace sorawm/iopaint/model/ldm.py \
          --replace-fail "@torch.cuda.amp.autocast()" "@torch.amp.autocast('cuda')"

        # Patch flow_comp.py to handle missing mmcv.runner (MMCV 2.x compatibility)
        cat > sorawm/models/model/modules/flow_comp_patch.py << 'EOF'
    import numpy as np
    import torch
    import torch.nn as nn
    import torch.nn.functional as F

    try:
        from mmcv.cnn import ConvModule
        from mmcv.runner import load_checkpoint
    except ImportError:
        # Fallback implementation for MMCV 1.x components missing in 2.x or absent
        class ConvModule(nn.Module):
            def __init__(self, in_channels, out_channels, kernel_size, stride=1, padding=0, dilation=1, groups=1, bias=True, norm_cfg=None, act_cfg=dict(type='ReLU')):
                super().__init__()
                self.conv = nn.Conv2d(in_channels, out_channels, kernel_size, stride=stride, padding=padding, dilation=dilation, groups=groups, bias=bias)
                self.act = nn.ReLU(inplace=True) if act_cfg and act_cfg.get('type') == 'ReLU' else nn.Identity()
            def forward(self, x):
                return self.act(self.conv(x))

        def load_checkpoint(model, filename, map_location=None, strict=False, logger=None):
            checkpoint = torch.load(filename, map_location=map_location)
            # Handle state_dict or raw checkpoint
            if isinstance(checkpoint, dict) and 'state_dict' in checkpoint:
                state_dict = checkpoint['state_dict']
            else:
                state_dict = checkpoint
            # Strip 'module.' prefix if present (DataParallel)
            if list(state_dict.keys())[0].startswith('module.'):
                state_dict = {k[7:]: v for k, v in state_dict.items()}
            model.load_state_dict(state_dict, strict=strict)
            return checkpoint

    from sorawm.configs import PHY_NET_CHECKPOINT_PATH, PHY_NET_CHECKPOINT_REMOTE_URL
    from sorawm.utils.download_utils import ensure_model_downloaded
    EOF
          
        # Append the original file content (skipping imports) to the patch
        tail -n +9 sorawm/models/model/modules/flow_comp.py >> sorawm/models/model/modules/flow_comp_patch.py
        mv sorawm/models/model/modules/flow_comp_patch.py sorawm/models/model/modules/flow_comp.py

    # Patch devices_utils.py to support env var override
    cat > sorawm/utils/devices_utils.py << 'EOF'
from functools import lru_cache
import torch
import os
from loguru import logger

@lru_cache()
def get_device():
    if os.environ.get("SORA_DEVICE"):
        device = os.environ["SORA_DEVICE"]
        logger.info(f"Forcing device from env: {device}")
        return torch.device(device)

    device = "cpu"
    if torch.cuda.is_available():
        device = "cuda"
    if torch.backends.mps.is_available():
        device = "mps"
    logger.debug(f"Using device: {device}")
    return torch.device(device)
EOF

    # Add --device argument to cli.py
    substituteInPlace cli.py \
      --replace-fail 'help="🔧 Model to use for watermark removal (default: lama). Options: lama (fast, may flicker), e2fgvi_hq (time consistent, slower)",' \
                     'help="🔧 Model to use for watermark removal (default: lama). Options: lama (fast, may flicker), e2fgvi_hq (time consistent, slower)",
    )
    parser.add_argument(
        "-d",
        "--device",
        type=str,
        help="🖥️ Device to use (e.g., cuda, cpu). Overrides auto-detection.",'

    # Inject env var setting in cli.py
    substituteInPlace cli.py \
      --replace-fail 'args = parser.parse_args()' \
                     'args = parser.parse_args()
    if args.device:
        import os
        os.environ["SORA_DEVICE"] = args.device'
  '';

  installPhase = ''
        runHook preInstall

        # Install the Python package
        mkdir -p $out/lib/sora-watermark-cleaner
        cp -r . $out/lib/sora-watermark-cleaner/

        # Create model directory with pre-fetched models
        mkdir -p $out/share/models
        ln -s ${yoloModel} $out/share/models/best.pt
        ln -s ${lamaModel} $out/share/models/big-lama.pt

        # Rewrite configs.py to use Nix store for models and XDG cache for runtime dirs
        cat > $out/lib/sora-watermark-cleaner/sorawm/configs.py << 'NIXEOF'
    import os
    from pathlib import Path

    # Nix store paths for pre-fetched models (read-only)
    NIX_MODELS_DIR = Path(os.environ.get("SORAWM_MODELS_DIR", "${builtins.placeholder "out"}/share/models"))

    # Runtime cache directory (writable)
    CACHE_DIR = Path(os.environ.get("SORAWM_CACHE_DIR", Path.home() / ".cache" / "sora-watermark-cleaner"))
    CACHE_DIR.mkdir(exist_ok=True, parents=True)

    # Resources - models from Nix store
    RESOURCES_DIR = NIX_MODELS_DIR
    WATER_MARK_TEMPLATE_IMAGE_PATH = RESOURCES_DIR / "watermark_template.png"
    WATER_MARK_DETECT_YOLO_WEIGHTS = RESOURCES_DIR / "best.pt"
    WATER_MARK_DETECT_YOLO_WEIGHTS_HASH_JSON = CACHE_DIR / "model_version.json"

    # Checkpoints in cache (may be downloaded at runtime for e2fgvi_hq)
    CHECKPOINT_DIR = CACHE_DIR / "checkpoint"
    CHECKPOINT_DIR.mkdir(exist_ok=True, parents=True)
    SPYNET_CHECKPOINT_PATH = CHECKPOINT_DIR / "spynet_20210409-c6c1bd09.pth"
    E2FGVI_HQ_CHECKPOINT_PATH = CHECKPOINT_DIR / "E2FGVI-HQ-CVPR22.pth"
    E2FGVI_HQ_CHECKPOINT_REMOTE_URL = "https://github.com/linkedlist771/SoraWatermarkCleaner/releases/download/V0.0.1/E2FGVI-HQ-CVPR22.pth"
    PHY_NET_CHECKPOINT_REMOTE_URL = "https://download.openmmlab.com/mmediting/restorers/basicvsr/spynet_20210409-c6c1bd09.pth"
    PHY_NET_CHECKPOINT_PATH = CHECKPOINT_DIR / "spynet_20210409-c6c1bd09.pth"

    # Output and working directories in cache
    OUTPUT_DIR = CACHE_DIR / "output"
    OUTPUT_DIR.mkdir(exist_ok=True, parents=True)

    DEFAULT_WATERMARK_REMOVE_MODEL = "lama"

    WORKING_DIR = CACHE_DIR / "working_dir"
    WORKING_DIR.mkdir(exist_ok=True, parents=True)

    LOGS_PATH = CACHE_DIR / "logs"
    LOGS_PATH.mkdir(exist_ok=True, parents=True)

    DATA_PATH = CACHE_DIR / "data"
    DATA_PATH.mkdir(exist_ok=True, parents=True)

    SQLITE_PATH = DATA_PATH / "db.sqlite3"

    # Frontend paths (not used in CLI mode)
    FRONTUI_DIR = CACHE_DIR / "frontend"
    FRONTUI_DIR.mkdir(exist_ok=True, parents=True)
    FRONTUI_DIST_DIR = FRONTUI_DIR / "dist"
    FRONTUI_DIST_DIR.mkdir(exist_ok=True, parents=True)
    FRONTUI_DIST_DIR_ASSETS = FRONTUI_DIST_DIR / "assets"
    FRONTUI_DIST_DIR_ASSETS.mkdir(exist_ok=True, parents=True)
    FRONTUI_DIST_DIR_INDEX_HTML = FRONTUI_DIST_DIR / "index.html"

    # Torch compile settings
    ENABLE_E2FGVI_HQ_TORCH_COMPILE = True

    TORCH_COMPILE_DIR = Path.home() / ".cache" / "torch_compile"
    TORCH_COMPILE_DIR.mkdir(exist_ok=True, parents=True)

    E2FGVI_HQ_TORCH_COMPILE_DIR = TORCH_COMPILE_DIR / "e2fgvi_hq"
    E2FGVI_HQ_TORCH_COMPILE_DIR.mkdir(exist_ok=True, parents=True)

    E2FGVI_HQ_TORCH_COMPILE_ARTIFACTS = E2FGVI_HQ_TORCH_COMPILE_DIR / "artifacts.bin"
    E2FGVI_HQ_TORCH_COMPILE_ARTIFACTS_BF16 = E2FGVI_HQ_TORCH_COMPILE_DIR / "artifacts_bf16.bin"

    # YOLO batch size
    DEFAULT_DETECT_BATCH_SIZE = 4
    NIXEOF

        # Disable model download attempts in download_utils.py
        # by making the download function a no-op (models are pre-fetched)
        substituteInPlace $out/lib/sora-watermark-cleaner/sorawm/utils/download_utils.py \
          --replace-fail 'def download_detector_weights(force_download: bool = False):' \
                         'def download_detector_weights(force_download: bool = False):
        # Models are pre-fetched in Nix, skip download
        return'

        # Create the CLI wrapper
        mkdir -p $out/bin
        makeWrapper ${pythonEnv}/bin/python $out/bin/sora-watermark-cleaner \
          --add-flags "$out/lib/sora-watermark-cleaner/cli.py" \
          --prefix PATH : ${lib.makeBinPath [ ffmpeg ]} \
          --prefix LD_LIBRARY_PATH : ${
            lib.makeLibraryPath [
              pkgs.linuxPackages.nvidia_x11
              pkgs.cudaPackages.cudatoolkit
              pkgs.cudaPackages.cudnn
            ]
          }:/run/opengl-driver/lib \
          --set SORAWM_MODELS_DIR "$out/share/models"

        runHook postInstall
  '';

  meta = with lib; {
    description = "Deep learning powered Sora2 watermark cleaner";
    homepage = "https://github.com/linkedlist771/SoraWatermarkCleaner";
    license = licenses.asl20;
    platforms = platforms.linux;
    maintainers = [ ];
    mainProgram = "sora-watermark-cleaner";
  };
}
