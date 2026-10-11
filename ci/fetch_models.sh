#!/bin/bash
# Fetch all embedded AI models into the app bundle resource folder.
# Models are MERGED into the software (final IPA contains everything);
# they are fetched at build time only because of their large size.
# Pure curl — no pip / huggingface_hub dependency.
set -e

MODELS_DIR="HJDCamera/Resources/Models"
mkdir -p "$MODELS_DIR"

HF="https://huggingface.co"

# Download a .mlmodel.zip from TheMurusTeam and unzip it
download_mlmodel() {
  local repo="$1" file="$2"
  echo "::group::Download $file"
  curl -L --retry 3 --fail -o "/tmp/$file" "$HF/$repo/resolve/main/$file"
  unzip -o "/tmp/$file" -d "$MODELS_DIR"
  rm -f "/tmp/$file"
  rm -rf "$MODELS_DIR/__MACOSX"
  echo "::endgroup::"
}

# Download a .mlpackage directory (explicit file tree, no pip)
download_package() {
  local repo="$1" pkg="$2"
  shift 2
  echo "::group::Download $pkg"
  for full in "$@"; do
    local rel="${full#$pkg/}"
    mkdir -p "$MODELS_DIR/$pkg/$(dirname "$rel")"
    curl -L --retry 3 --fail -o "$MODELS_DIR/$pkg/$rel" "$HF/$repo/resolve/main/$full"
  done
  echo "::endgroup::"
}

# 1) TheMurusTeam CoreML models
download_mlmodel "TheMurusTeam/coreml-upscaler-realesrgan512" "realesrgan512.mlmodel.zip"
download_mlmodel "TheMurusTeam/coreml-upscaler-realesrganAnime512" "realesrganAnime512.mlmodel.zip"
download_mlmodel "TheMurusTeam/coreml-upscaler-MPRNetDenoising" "MPRNetDenoising.mlmodel.zip"
download_mlmodel "TheMurusTeam/coreml-upscaler-gfpgan" "gfpgan.mlmodel.zip"

# 2) DepthPro (1.9GB) — explicit file tree
download_package "coreml-projects/DepthPro-coreml" "DepthPro.mlpackage" \
  "DepthPro.mlpackage/Manifest.json" \
  "DepthPro.mlpackage/Data/com.apple.CoreML/model.mlmodel" \
  "DepthPro.mlpackage/Data/com.apple.CoreML/weights/weight.bin"

# 3) GFPGAN (mlboydaisuke)
download_package "mlboydaisuke/GFPGAN-CoreML" "GFPGAN.mlpackage" \
  "GFPGAN.mlpackage/Manifest.json" \
  "GFPGAN.mlpackage/Data/com.apple.CoreML/model.mlmodel"

echo "=== Models ready ==="
du -sh "$MODELS_DIR"/*
