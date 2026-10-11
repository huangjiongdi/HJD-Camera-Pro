#!/bin/bash
# fetch_models.sh - Download all CoreML models for HJD Camera Pro
# Models are MERGED into the app bundle (final IPA contains everything).
# Fetched at build time due to large size.
set -e

MODELS_DIR="HJDCamera/Resources/Models"
mkdir -p "$MODELS_DIR"

HF="https://huggingface.co"

echo "============================================"
echo "  HJD Camera Pro - AI Model Fetcher"
echo "============================================"

# Robust download with retry
dl() {
  local url="$1" dest="$2" name="$3"
  if [ -f "$dest" ]; then
    echo "  [SKIP] $name"
    return 0
  fi
  echo "  [DL] $name"
  if curl -fSL --retry 3 --retry-delay 5 --connect-timeout 30 --max-time 600 -o "$dest" "$url" 2>/dev/null; then
    local sz=$(du -h "$dest" 2>/dev/null | cut -f1 || echo "?")
    echo "  [OK] $name ($sz)"
    return 0
  else
    echo "  [FAIL] $name"
    rm -f "$dest"
    return 1
  fi
}

# Download .mlmodel.zip and unzip
dl_mlmodel_zip() {
  local repo="$1" file="$2" name="$3"
  local tmp="/tmp/hjd_$$_$file"
  echo "  [DL] $name"
  if curl -fSL --retry 3 --retry-delay 5 --connect-timeout 30 --max-time 600 -o "$tmp" "$HF/$repo/resolve/main/$file" 2>/dev/null; then
    unzip -q -o "$tmp" -d "$MODELS_DIR" 2>/dev/null || true
    rm -f "$tmp"
    rm -rf "$MODELS_DIR/__MACOSX"
    local sz=$(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1)
    echo "  [OK] $name (total: $sz)"
    return 0
  else
    echo "  [FAIL] $name"
    rm -f "$tmp"
    return 1
  fi
}

# Download mlpackage file tree
dl_package() {
  local repo="$1" pkg="$2"
  shift 2
  echo "  [DL] $pkg"
  local ok=1
  for full in "$@"; do
    local rel="${full#$pkg/}"
    mkdir -p "$MODELS_DIR/$pkg/$(dirname "$rel")"
    if ! curl -fSL --retry 3 --retry-delay 5 --connect-timeout 30 --max-time 600 \
         -o "$MODELS_DIR/$pkg/$rel" "$HF/$repo/resolve/main/$full" 2>/dev/null; then
      echo "    [FAIL] $rel"
      ok=0
    fi
  done
  if [ $ok -eq 1 ]; then
    echo "  [OK] $pkg"
  else
    echo "  [PARTIAL] $pkg"
  fi
}

echo ""
echo "=== 1. Real-ESRGAN Super Resolution ==="

# TheMurusTeam models (known working CoreML)
dl_mlmodel_zip "TheMurusTeam/coreml-upscaler-realesrgan512" "realesrgan512.mlmodel.zip" "Real-ESRGAN 512" || true
dl_mlmodel_zip "TheMurusTeam/coreml-upscaler-realesrganAnime512" "realesrganAnime512.mlmodel.zip" "Real-ESRGAN Anime 512" || true

# Alternative: direct mlmodel from various repos
dl "$HF/TheMurusTeam/Real-ESRGAN/resolve/main/RealESRGAN_x4plus.mlmodel" \
   "$MODELS_DIR/RealESRGAN_x4plus.mlmodel" "Real-ESRGAN x4plus" || true
dl "$HF/TheMurusTeam/Real-ESRGAN/resolve/main/RealESRNet_x4plus.mlmodel" \
   "$MODELS_DIR/RealESRNet_x4plus.mlmodel" "RealESRNet x4plus" || true
dl "$HF/TheMurusTeam/Real-ESRGAN/resolve/main/RealESRGAN_General_x4v3.mlmodel" \
   "$MODELS_DIR/RealESRGAN_General_x4v3.mlmodel" "Real-ESRGAN General x4v3" || true

echo ""
echo "=== 2. Denoising Models ==="
dl_mlmodel_zip "TheMurusTeam/coreml-upscaler-MPRNetDenoising" "MPRNetDenoising.mlmodel.zip" "MPRNet Denoising" || true
dl "$HF/john-rocklin/coreml-projects/resolve/main/MPRNet/MPRNet.mlmodel" \
   "$MODELS_DIR/MPRNet.mlmodel" "MPRNet (alt)" || true

echo ""
echo "=== 3. Face Restoration (GFPGAN) ==="
dl_mlmodel_zip "TheMurusTeam/coreml-upscaler-gfpgan" "gfpgan.mlmodel.zip" "GFPGAN" || true
dl_package "mlboydaisuke/GFPGAN-CoreML" "GFPGAN.mlpackage" \
  "GFPGAN.mlpackage/Manifest.json" \
  "GFPGAN.mlpackage/Data/com.apple.CoreML/model.mlmodel" || true

echo ""
echo "=== 4. Depth Estimation ==="
dl_package "coreml-projects/DepthPro-coreml" "DepthPro.mlpackage" \
  "DepthPro.mlpackage/Manifest.json" \
  "DepthPro.mlpackage/Data/com.apple.CoreML/model.mlmodel" \
  "DepthPro.mlpackage/Data/com.apple.CoreML/weights/weight.bin" || true

echo ""
echo "=== 5. Additional SR Models (SwinIR, EDSR, etc.) ==="
# Try alternative repos
dl "$HF/john-rocklin/coreml-projects/resolve/main/RealESRGAN/RealESRGAN_x4plus.mlmodel" \
   "$MODELS_DIR/RealESRGAN_x4plus_jr.mlmodel" "Real-ESRGAN x4plus (alt)" || true

echo ""
echo "=== 6. Generate lightweight FSRCNN model ==="
# FSRCNN is small enough that we create a CoreML model descriptor at runtime
# if no pre-trained model is available. The code handles this fallback.
echo "  [INFO] FSRCNN will use runtime fallback if not bundled"

echo ""
echo "=== 7. Cleanup and verify ==="
rm -rf "$MODELS_DIR/__MACOSX"
rm -f "$MODELS_DIR"/*.zip

echo ""
echo "============================================"
echo "  Model Download Summary"
echo "============================================"
echo ""
echo "Models directory:"
find "$MODELS_DIR" -maxdepth 2 -type f -o -type d | head -50
echo ""
TOTAL=$(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1 || echo "0")
COUNT=$(find "$MODELS_DIR" \( -name "*.mlmodel" -o -name "*.mlpackage" \) 2>/dev/null | wc -l)
echo "Total size: $TOTAL"
echo "Model files: $COUNT"
echo ""
echo "=== Done ==="
