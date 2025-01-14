#!/bin/bash
set -Eeuo pipefail

# TODO: move all mkdir -p ?
mkdir -p /mnt/data/config/auto/scripts/
# mount scripts individually

echo $ROOT
ls -lha $ROOT

find "${ROOT}/scripts/" -maxdepth 1 -type l -delete
cp -vrfTs /mnt/data/config/auto/scripts/ "${ROOT}/scripts/"

# Set up config file
python /docker/config.py /mnt/data/config/auto/config.json

if [ ! -f /mnt/data/config/auto/ui-config.json ]; then
  echo '{}' >/mnt/data/config/auto/ui-config.json
fi

if [ ! -f /mnt/data/config/auto/styles.csv ]; then
  touch /mnt/data/config/auto/styles.csv
fi

# copy models from original models folder
mkdir -p /mnt/data/models/VAE-approx/ /mnt/data/models/karlo/

rsync -a --info=NAME ${ROOT}/models/VAE-approx/ /mnt/data/models/VAE-approx/
rsync -a --info=NAME ${ROOT}/models/karlo/ /mnt/data/models/karlo/

declare -A MOUNTS

MOUNTS["/root/.cache"]="/mnt/data/.cache"
MOUNTS["${ROOT}/models"]="/mnt/data/models"

MOUNTS["${ROOT}/embeddings"]="/mnt/data/embeddings"
MOUNTS["${ROOT}/config.json"]="/mnt/data/config/auto/config.json"
MOUNTS["${ROOT}/ui-config.json"]="/mnt/data/config/auto/ui-config.json"
MOUNTS["${ROOT}/styles.csv"]="/mnt/data/config/auto/styles.csv"
MOUNTS["${ROOT}/extensions"]="/mnt/data/config/auto/extensions"
MOUNTS["${ROOT}/config_states"]="/mnt/data/config/auto/config_states"

# extra hacks
MOUNTS["${ROOT}/repositories/CodeFormer/weights/facelib"]="/mnt/data/data/.cache"

for to_path in "${!MOUNTS[@]}"; do
  set -Eeuo pipefail
  from_path="${MOUNTS[${to_path}]}"
  rm -rf "${to_path}"
  if [ ! -f "$from_path" ]; then
    mkdir -vp "$from_path"
  fi
  mkdir -vp "$(dirname "${to_path}")"
  ln -sT "${from_path}" "${to_path}"
  echo Mounted $(basename "${from_path}")
done

echo "Installing extension dependencies (if any)"

# because we build our container as root:
chown -R root ~/.cache/
chmod 766 ~/.cache/

shopt -s nullglob
# For install.py, please refer to https://github.com/AUTOMATIC1111/stable-diffusion-webui/wiki/Developing-extensions#installpy
list=(./extensions/*/install.py)
for installscript in "${list[@]}"; do
  EXTNAME=$(echo $installscript | cut -d '/' -f 3)
  # Skip installing dependencies if extension is disabled in config
  if $(jq -e ".disabled_extensions|any(. == \"$EXTNAME\")" config.json); then
    echo "Skipping disabled extension ($EXTNAME)"
    continue
  fi
  PYTHONPATH=${ROOT} python "$installscript"
done

if [ -f "/mnt/data/config/auto/startup.sh" ]; then
  pushd ${ROOT}
  echo "Running startup script"
  . /mnt/data/config/auto/startup.sh
  popd
fi

exec "$@"
