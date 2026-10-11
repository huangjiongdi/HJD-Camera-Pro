#!/bin/bash
# Fetch all embedded AI models into the app bundle resource folder.
# Models are MERGED into the software (final IPA contains everything);
# they are fetched at build time only because of their large size.
set -e

MODELS_DIR="HJDCamera/Resources/Models"
mkdir -p "$MODELS_DIR"
cd "$MODELS_DIR"

HF="https://huggingface.co"

# 1) TheMurusTeam CoreML models (stored as .mlmodel.zip)
declare -a MLMODELS=(
  "TheMurusTeam/coreml-upscaler-realesrgan512/realesrgan512.mlmodel.zip"
  "TheMurusTeam/coreml-upscaler-realesrganAnime512/realesrganAnime512.mlmodel.zip"
  "TheMurusTeam/coreml-upscaler-MPRNetDenoising/MPRNetDenoising.mlmodel.zip"
  "TheMurusTeam/coreml-upscaler-gfpgan/gfpgan.mlmodel.zip"
)

for path in "${MLMODELS[@]}"; do
  fname=$(basename "$path")
  echo "::group::Download $fname"
  curl -L --retry 3 -o "$fname" "$HF/$path/resolve/main/$fname"
  unzip -o "$fname"
  rm -f "$fname"
  echo "::endgroup::"
done

# 2) DepthPro .mlpackage (1.9GB)
cd - > /dev/null
echo "::group::Download DepthPro.mlpackage"
python3 -m pip install -q huggingface_hub
python3 - <<'PY'
from huggingface_hub import snapshot_download
snapshot_download(
    "coreml-projects/DepthPro-coreml",
    allow_patterns=["DepthPro.mlpackage/*"],
    local_dir="models_dl",
)
PY
cp -R "models_dl/DepthPro.mlpackage" "$MODELS_DIR/"
rm -rf models_dl
echo "::endgroup::"

# 3) GFPGAN .mlpackage (mlboydaisuke)
echo "::group::Download GFPGAN.mlpackage"
python3 - <<'PY'
from huggingface_hub import snapshot_download
snapshot_download(
    "mlboydaisuke/GFPGAN-CoreML",
    allow_patterns=["GFPGAN.mlpackage/*"],
    local_dir="models_dl",
)
PY
cp -R "models_dl/GFPGAN.mlpackage" "$MODELS_DIR/"
rm -rf models_dl
echo "::endgroup::"

echo "=== Models ready ==="
du -sh "$MODELS_DIR"/*
