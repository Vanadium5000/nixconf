# Plan: Sora Watermark Cleaner CUDA Fix

## Context

### Original Request
User reported `sora-watermark-cleaner` falling back to CPU ("Using device: cpu") and showing deprecated `torch.cuda.amp.autocast` warnings, despite global CUDA support working for other apps (Ollama).

### Analysis Summary
1.  **Device Detection**: `devices_utils.py` checks `torch.cuda.is_available()`. If this returns false, it falls back to CPU.
2.  **Cause**: On NixOS, Python packages often cannot find CUDA libraries (`libcuda.so`, `libcudart.so`) unless `LD_LIBRARY_PATH` is explicitly set in the wrapper, even if `cudaSupport` is enabled.
3.  **Deprecation**: `ldm.py` uses `@torch.cuda.amp.autocast()`, which is deprecated in newer Torch versions. Needs replacement with `@torch.amp.autocast('cuda')`.

### Strategy
1.  **Wrapper Update**: Inject `LD_LIBRARY_PATH` into the program wrapper to expose NVIDIA driver and CUDA toolkit libraries.
2.  **Code Patch**: Use `sed` in `postPatch` to update the deprecated autocast call.

---

## Work Objectives

### Core Objective
Enable GPU acceleration for `sora-watermark-cleaner` and resolve deprecation warnings.

### Concrete Deliverables
- Modified `modules/_pkgs/sora-watermark-cleaner.nix` with:
  - `LD_LIBRARY_PATH` prefix in `makeWrapper`.
  - `postPatch` fix for `ldm.py`.

### Definition of Done
- [ ] Build succeeds: `nix build .#sora-watermark-cleaner`
- [ ] Wrapper contains `LD_LIBRARY_PATH` pointing to nvidia/cuda libs.
- [ ] Source code in store contains `torch.amp.autocast('cuda')`.

---

## Verification Strategy

### Test Decision
- **Infrastructure**: Nix build system.
- **Manual Verification**: Since we cannot run the GUI/GPU in this environment, we verify the *inputs* (wrapper args) and *build success*. User will verify runtime.

### Verification Commands
1.  **Build Verification**:
    ```bash
    nix build .#packages.x86_64-linux.sora-watermark-cleaner
    ```
2.  **Wrapper Verification**:
    ```bash
    grep "LD_LIBRARY_PATH" result/bin/sora-watermark-cleaner
    # Expected: Includes nvidia_x11 and cudatoolkit/cudnn
    ```
3.  **Patch Verification**:
    ```bash
    grep "torch.amp.autocast('cuda')" result/lib/sora-watermark-cleaner/sorawm/iopaint/model/ldm.py
    # Expected: Match found
    ```

---

## TODOs

- [ ] 1. Modify `modules/_pkgs/sora-watermark-cleaner.nix`

  **What to do**:
  - Add `cudatoolkit`, `cudaPackages.cudnn`, and `linuxPackages.nvidia_x11` to `buildInputs` (or just available for lib path).
  - In `postPatch`, add `sed` command to replace deprecated autocast.
  - In `installPhase` `makeWrapper`, add `--prefix LD_LIBRARY_PATH` containing the CUDA libraries.

  **Code Changes**:
  ```nix
  # In postPatch
  substituteInPlace sorawm/iopaint/model/ldm.py \
    --replace "@torch.cuda.amp.autocast()" "@torch.amp.autocast('cuda')"

  # In installPhase makeWrapper
  --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [
    pkgs.linuxPackages.nvidia_x11
    pkgs.cudaPackages.cudatoolkit
    pkgs.cudaPackages.cudnn
  ]}
  ```

  **Reference**:
  - `AGENTS.md` (CUDA & Environment Variables section): Shows `LD_LIBRARY_PATH` pattern.
  - Current file: `modules/_pkgs/sora-watermark-cleaner.nix`.

  **Acceptance Criteria**:
  - [ ] `nix build .#sora-watermark-cleaner` succeeds.
  - [ ] `grep "torch.amp.autocast('cuda')" sorawm/iopaint/model/ldm.py` (checked during build or on result).
  - [ ] Wrapper script exports correct `LD_LIBRARY_PATH`.

  **Commit**: YES
  - Message: `fix(sora-watermark-cleaner): enable cuda support and fix deprecation warnings`

---

## Success Criteria

### Final Checklist
- [ ] `LD_LIBRARY_PATH` set in wrapper
- [ ] Deprecation warning patched out
- [ ] Build completes successfully
