#!/bin/bash
# Fetch all embedded AI models into the app bundle resource folder.
# Models are MERGED into the software (final IPA contains everything);
# they are fetched at build time only because of their large size.
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
  echo "::endgroup::"
}

# 1) TheMurusTeam CoreML models
download_mlmodel "TheMurusTeam/coreml-upscaler-realesrgan512" "realesrgan512.mlmodel.zip"
download_mlmodel "TheMurusTeam/coreml-upscaler-realesrganAnime512" "realesrganAnime512.mlmodel.zip"
download_mlmodel "TheMurusTeam/coreml-upscaler-MPRNetDenoising" "MPRNetDenoising.mlmodel.zip"
download_mlmodel "TheMurusTeam/coreml-upscaler-gfpgan" "gfpgan.mlmodel.zip"

# 2) .mlpackage downloads (DepthPro + GFPGAN)
python3 -m pip install -q --upgrade huggingface_hub

download_package() {
  local repo="$1" pkg="$2"
  echo "::group::Download $pkg"
  python3 - "$repo" "$pkg" <<'PY'
import sys
from huggingface_hub import snapshot_download
repo, pkg = sys.argv[1], sys.argv[2]
# whole repo (these repos contain only the package + README)
snapshot_download(repo, local_dir="models_dl")
PY
  rm -rf "$MODELS_DIR/$pkg"
  cp -R "models_dl/$pkg" "$MODELS_DIR/$pkg"
  rm -rf models_dl
  echo "::endgroup::"
}

# DepthPro (1.9GB)
download_package "coreml-projects/DepthPro-coreml" "DepthPro.mlpackage"
# GFPGAN (mlboydaisuke)
download_package "mlboydaisuke/GFPGAN-CoreML" "GFPGAN.mlpackage"

echo "=== Models ready ==="
du -sh "$MODELS_DIR"/*
