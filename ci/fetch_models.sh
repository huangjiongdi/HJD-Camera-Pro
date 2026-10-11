#!/bin/bash
# fetch_models.sh - Download ALL CoreML models for HJD Camera Pro
#
# Models are MERGED into the app bundle: the final IPA contains every model
# (no runtime download). They are fetched at build time purely because of size.
#
# All paths below have been verified against the HF repo trees. A failed
# download aborts the build so we never ship a "complete" IPA missing a model.
set -euo pipefail

MODELS_DIR="HJDCamera/Resources/Models"
mkdir -p "$MODELS_DIR"

HF="https://huggingface.co"

CURL_OPTS=(--retry 3 --retry-delay 5 --connect-timeout 30 --max-time 1800 -fsSL)

cleanup() { rm -rf "$MODELS_DIR/__MACOSX" "$MODELS_DIR"/*.zip; }
trap cleanup EXIT

# Download a zip from a repo and unzip it into the models dir (zip -> mlmodel/mlpackage).
dl_zip() {
  local repo="$1" file="$2" name="$3"
  local tmp; tmp="$(mktemp)"
  echo "  [DL] $name"
  curl "${CURL_OPTS[@]}" -o "$tmp" "$HF/$repo/resolve/main/$file"
  unzip -q -o "$tmp" -d "$MODELS_DIR"
  rm -f "$tmp"
  echo "  [OK] $name"
}

# Download a single file (e.g. a bare .mlmodel) from a repo.
dl_file() {
  local repo="$1" file="$2" name="$3"
  echo "  [DL] $name"
  curl "${CURL_OPTS[@]}" -o "$MODELS_DIR/$file" "$HF/$repo/resolve/main/$file"
  echo "  [OK] $name"
}

# Download a .mlpackage by its standard file tree:
#   <pkg>/Manifest.json
#   <pkg>/Data/com.apple.CoreML/model.mlmodel
#   <pkg>/Data/com.apple.CoreML/weights/weight.bin   (optional; "no" to skip)
dl_pkg() {
  local repo="$1" pkg="$2" weights="$3"
  local pkgdir="$MODELS_DIR/$pkg"
  local base="$pkgdir/Data/com.apple.CoreML"
  local url="$HF/$repo/resolve/main/$pkg"
  echo "  [DL] $pkg"
  mkdir -p "$pkgdir" "$base/weights"
  curl "${CURL_OPTS[@]}" -o "$pkgdir/Manifest.json" "$url/Manifest.json"
  curl "${CURL_OPTS[@]}" -o "$base/model.mlmodel" "$url/Data/com.apple.CoreML/model.mlmodel"
  if [ "$weights" = "yes" ]; then
    curl "${CURL_OPTS[@]}" -o "$base/weights/weight.bin" \
      "$url/Data/com.apple.CoreML/weights/weight.bin"
  fi
  echo "  [OK] $pkg"
}

echo ""
echo "=== 1. Real-ESRGAN Super Resolution (core models) ==="
dl_zip "TheMurusTeam/coreml-upscaler-realesrgan512" "realesrgan512.mlmodel.zip" "Real-ESRGAN 512"
dl_zip "TheMurusTeam/coreml-upscaler-realesrganAnime512" "realesrganAnime512.mlmodel.zip" "Real-ESRGAN Anime 512"
dl_pkg "mlboydaisuke/Real-ESRGAN-x4-CoreML" "RealESRGAN_x4.mlpackage" "no"

echo ""
echo "=== 2. Real-ESRGAN variants (x4plus / x4v3 / UltraSharp / Manga) ==="
dl_zip "VincentGOURBIN/RealESRGAN-CoreML" "RealESRGAN-UltraSharp.mlpackage.zip" "RealESRGAN UltraSharp"
dl_zip "VincentGOURBIN/RealESRGAN-CoreML" "RealESRGAN-x4plus.mlpackage.zip" "RealESRGAN x4plus"
dl_zip "VincentGOURBIN/RealESRGAN-CoreML" "RealESRGAN-x4v3.mlpackage.zip" "RealESRGAN x4v3"
dl_zip "VincentGOURBIN/RealESRGAN-CoreML" "RealESRGAN-x4v3-denoise.mlpackage.zip" "RealESRGAN x4v3 denoise"
dl_zip "VincentGOURBIN/RealESRGAN-CoreML" "ESRGAN-MangaJPEGLQ.mlpackage.zip" "ESRGAN Manga JPEG LQ"

echo ""
echo "=== 3. GAN upscalers (AESRGAN / BSRGAN) ==="
dl_zip "TheMurusTeam/coreml-upscaler-aesrgan" "aesrgan.mlmodel.zip" "AESRGAN"
dl_zip "TheMurusTeam/coreml-upscaler-bsrgan" "bsrgan.mlmodel.zip" "BSRGAN"

echo ""
echo "=== 4. Denoising (MPRNet) ==="
dl_zip "TheMurusTeam/coreml-upscaler-MPRNetDenoising" "MPRNetDenoising.mlmodel.zip" "MPRNet Denoising"

echo ""
echo "=== 5. Face Restoration (GFPGAN, single copy) ==="
dl_zip "TheMurusTeam/coreml-upscaler-gfpgan" "gfpgan.mlmodel.zip" "GFPGAN"

echo ""
echo "=== 6. Depth Estimation ==="
dl_pkg "coreml-projects/DepthPro-coreml" "DepthPro.mlpackage" "yes"
dl_pkg "mlboydaisuke/Depth-Anything-3-Small-CoreML" "DepthAnythingV3_small_504.mlpackage" "yes"
dl_pkg "mlboydaisuke/Depth-Anything-3-Base-CoreML" "DepthAnythingV3_base_504.mlpackage" "yes"
dl_pkg "apple/coreml-depth-anything-v2-small" "DepthAnythingV2SmallF16.mlpackage" "yes"
dl_pkg "apple/coreml-depth-anything-small" "DepthAnythingSmallF16.mlpackage" "yes"

echo ""
echo "=== 7. Semantic Segmentation ==="
dl_pkg "apple/coreml-detr-semantic-segmentation" "DETRResnet50SemanticSegmentationF16.mlpackage" "yes"
dl_pkg "apple/deeplabv3-mobilevit-small" "MobileViT_DeepLabV3.mlpackage" "yes"

echo ""
echo "=== 8. Segment Anything Model 2 (SAM2 tiny) ==="
dl_pkg "apple/coreml-sam2.1-tiny" "SAM2_1TinyImageEncoderFLOAT16.mlpackage" "yes"
dl_pkg "apple/coreml-sam2.1-tiny" "SAM2_1TinyMaskDecoderFLOAT16.mlpackage" "yes"
dl_pkg "apple/coreml-sam2.1-tiny" "SAM2_1TinyPromptEncoderFLOAT16.mlpackage" "yes"

echo ""
echo "=== 9. Detection / Classification ==="
dl_file "apple/coreml-YOLOv3" "YOLOv3FP16.mlmodel" "YOLOv3 FP16"
dl_file "apple/coreml-resnet-50" "Resnet50FP16.mlmodel" "ResNet50 FP16"

echo ""
echo "============================================"
echo "  Model Download Summary"
echo "============================================"
cleanup
TOTAL="$(du -sh "$MODELS_DIR" | cut -f1)"
MLMODEL_COUNT="$(find "$MODELS_DIR" -name "*.mlmodel" | wc -l | tr -d ' ')"
PKG_COUNT="$(find "$MODELS_DIR" -maxdepth 1 -name "*.mlpackage" | wc -l | tr -d ' ')"
echo "Total models dir size: $TOTAL"
echo "Bare mlmodel: $MLMODEL_COUNT, mlpackage: $PKG_COUNT"
find "$MODELS_DIR" -maxdepth 1 | sort
echo "=== Done ==="
