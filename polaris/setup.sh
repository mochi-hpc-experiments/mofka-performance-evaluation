#!/bin/bash
set -e

HERE=`dirname $0`
HERE=`realpath $HERE`
source $HERE/util.sh

# CI genenerally runs from a temporary directory
# Here we move to a directory in the user's home
WORK_DIR="$HOME/mofka-polaris-pipelines/$(uuidgen | cut -c1-8)"
echo $WORK_DIR > work_dir.txt
mkdir -p $WORK_DIR

module swap PrgEnv-nvhpc PrgEnv-gnu || true

EXP_ENV=exp-env
COV_ENV=cov-env

# prevent spack from messing with user's configs
export SPACK_DISABLE_LOCAL_CONFIG=true
export SPACK_USER_CACHE_PATH=/tmp/spack

echo "==> Creating sandbox folder"
SANDBOX=$WORK_DIR/sandbox
mkdir -p $SANDBOX/bin
ORIGIN=$(dirname "$0")

echo "==> Downloading spack"
git clone -q https://github.com/spack/spack.git

echo "==> Finding latest release"
pushd spack
SPACK_LATEST=$(git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -t . -k 1,1n -k 2,2n -k 3,3n | tail -n 1)
echo "==> Checking out latest release ${SPACK_LATEST}"
git checkout -q $SPACK_LATEST
popd

echo "==> Cloning mochi-spack-packages repository"
git clone -q --depth 1 https://github.com/mochi-hpc/mochi-spack-packages.git
pushd mochi-spack-packages
MOCHI_SPACK_PACKAGES_HASH=$(git rev-parse HEAD)
popd

echo "==> Cloning platform configurations"
git clone -q --depth 1 https://github.com/mochi-hpc-experiments/platform-configurations.git
echo "==> Copying spack.yaml file"
cp platform-configurations/ANL/Polaris/spack.yaml .

echo "==> Cloning mofka repository"
pushd $SANDBOX
git clone -q --depth 1 https://github.com/mochi-hpc/mofka.git
if [[ -n "$MOFKA_GITHUB_SHA" ]]; then
    echo "==> Found MOFKA_GITHUB_SHA=$MOFKA_GITHUB_SHA, checking out commit"
    pushd mofka
    git checkout $MOFKA_GITHUB_SHA
    popd
else
    pushd mofka
    MOFKA_GITHUB_SHA=$(git rev-parse HEAD)
    popd
    echo "==> MOFKA_GITHUB_SHA not set, found $MOFKA_GITHUB_SHA"
fi
popd # $SANDBOX

echo "==> Sourcing setup-env.sh"
source spack/share/spack/setup-env.sh
spack config add config:environments_root:$SANDBOX/environments

BUILD_CACHE_PATH=/eagle/radix-io/polaris-spack-build-cache

echo "==> Updating cache index"

echo "==> Creating $EXP_ENV environment"
spack env create $EXP_ENV spack.yaml
spack -e $EXP_ENV config add config:install_tree:root:$SANDBOX/
spack -e $EXP_ENV repo add mochi-spack-packages
spack -e $EXP_ENV mirror rm mochi-buildcache
spack -e $EXP_ENV spack mirror add --autopush polaris-buildcache ${BUILD_CACHE_PATH}
spack -e $EXP_ENV buildcache update-index ${BUILD_CACHE_PATH}

echo "==> Creating $COV_ENV environment"
spack env create $COV_ENV spack.yaml
spack -e $COV_ENV config add config:install_tree:root:$SANDBOX/
spack -e $COV_ENV repo add mochi-spack-packages
spack -e $COV_ENV mirror rm mochi-buildcache
spack -e $COV_ENV spack mirror add --autopush polaris-buildcache ${BUILD_CACHE_PATH}
spack -e $COV_ENV buildcache update-index ${BUILD_CACHE_PATH}

echo "==> Adding specs to $EXP_ENV environment"
spack -e $EXP_ENV develop -p $SANDBOX/mofka -b $SANDBOX/mofka-build-release --no-clone \
    "mofka+python@main"
spack -e $EXP_ENV add \
    "mofka+python@main"

echo "==> Adding specs to $COV_ENV environment"
spack -e $COV_ENV develop -p $SANDBOX/mofka -b $SANDBOX/mofka-build-coverage --no-clone \
    "mofka+python@main cflags='--coverage -O0 -g' cxxflags='--coverage -O0 -g' ldflags='--coverage'"
spack -e $COV_ENV add \
    "mofka+python@main cflags='--coverage -O0 -g' cxxflags='--coverage -O0 -g' ldflags='--coverage'"
spack -e $COV_ENV add "py-gcovr@7.2"

echo "==> Installing $COV_ENV environment"
spack -e $COV_ENV install
spack -e $COV_ENV buildcache update-index ${BUILD_CACHE_PATH}

echo "==> Installing $EXP_ENV environment"
spack -e $EXP_ENV install
spack -e $EXP_ENV buildcache update-index ${BUILD_CACHE_PATH}

#if [[ -n "$MOCHI_BUILDCACHE_TOKEN" ]]; then
#    echo "==> Pushing packages to build cache"
#    spack -e $EXP_ENV mirror set --push \
#         --oci-username mdorier \
#         --oci-password $MOCHI_BUILDCACHE_TOKEN mochi-buildcache
#    spack -e $EXP_ENV buildcache push --base-image ubuntu:22.04 \
#          --unsigned --update-index --only dependencies mochi-buildcache
#    spack -e $COV_ENV mirror set --push \
#         --oci-username mdorier \
#         --oci-password $MOCHI_BUILDCACHE_TOKEN mochi-buildcache
#    spack -e $COV_ENV buildcache push --base-image ubuntu:22.04 \
#          --unsigned --update-index --only dependencies mochi-buildcache
#fi

echo "==> Creating activate scripts"
spack env activate --sh $EXP_ENV > $SANDBOX/bin/activate-exp-env.sh
spack env activate --sh $COV_ENV > $SANDBOX/bin/activate-cov-env.sh

echo "==> Writing info file"
cat << EOF > $SANDBOX/info.json
{
    "mochi-spack-package": "${MOCHI_SPACK_PACKAGES_HASH}",
    "spack": "${SPACK_LATEST}",
    "mofka": "${MOFKA_GITHUB_SHA}"
}
EOF

# The cleanup hereafter is not really necessary since we aren't
# using artifacts, it's just to make space in the user's home.

echo "==> Cleaning up release build"
rm -rf $SANDBOX/mofka-build-release

echo "==> Cleaning up coverage build (keep .gcno files)"
find $SANDBOX/mofka-build-coverage -type f ! -name "*.gcno" -delete
find $SANDBOX/mofka-build-coverage -type d -empty -delete

echo "==> Cleaning up the environments"
spack -e $EXP_ENV gc -y
spack -e $COV_ENV gc -y
find "$SANDBOX/environments" -type d -name "include" -exec rm -rf {} +
find "$SANDBOX/environments" -type d -name ".spack" -exec rm -rf {} +
find "$SANDBOX/environments" -type d -name ".spack-db" -exec rm -rf {} +
find "$SANDBOX/environments" -type d -name "share" -exec rm -rf {} +
find "$SANDBOX/environments" -type d -name "__pycache__" -exec rm -rf {} +

echo "==> Cleaning up spack and mochi-spack-packages"
rm -rf spack
rm -rf mochi-spack-packages

echo "==> Setup completed!"
