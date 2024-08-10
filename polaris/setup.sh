#!/bin/bash
set -e

module swap PrgEnv-nvhpc PrgEnv-gnu || true

EXP_ENV=exp-env

# prevent spack from messing with user's configs
export SPACK_DISABLE_LOCAL_CONFIG=true
export SPACK_USER_CACHE_PATH=/tmp/spack

echo "==> Creating sandbox folder"
mkdir sandbox
SANDBOX=$(realpath sandbox)
ORIGIN=$(dirname "$0")

echo "==> Copying qsub script in sandbox folder"
mkdir $SANDBOX/bin
cp $ORIGIN/run.qsub $SANDBOX/bin
cp $ORIGIN/post.sh $SANDBOX/bin

echo "==> Downloading spack"
git clone -q https://github.com/spack/spack.git

echo "==> Finding latest release"
pushd spack
SPACK_LATEST=$(git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -t . -k 1,1n -k 2,2n -k 3,3n | tail -n 1)

echo "==> Checking out latest release ${SPACK_LATEST}"
git checkout -q $SPACK_LATEST
popd

echo "==> Downloading mochi-spack-packages"
git clone -q --depth 1 https://github.com/mochi-hpc/mochi-spack-packages.git
pushd mochi-spack-packages
MOCHI_SPACK_PACKAGES_HASH=$(git rev-parse HEAD)
popd

echo "==> Sourcing setup-env.sh"
. spack/share/spack/setup-env.sh
spack config add config:environments_root:$SANDBOX/environments

echo "==> Creating $EXP_ENV environment"
spack env create $EXP_ENV $ORIGIN/spack.yaml
spack -e $EXP_ENV config add config:install_tree:root:$SANDBOX/
spack -e $EXP_ENV repo add mochi-spack-packages

echo "==> Adding mofka to $EXP_ENV"
spack -e $EXP_ENV add "mofka+python+mpi+benchmark@main"
echo "==> Adding gcovr to $EXP_ENV"
spack -e $EXP_ENV add "py-gcovr@7.2"
echo "==> Adding cmake to $EXP_ENV"
spack -e $EXP_ENV add cmake

echo "==> Installing $EXP_ENV environment"
spack -e $EXP_ENV install --only dependencies
spack -e $EXP_ENV install py-gcovr
spack -e $EXP_ENV install cmake

if [[ -n "$MOCHI_BUILDCACHE_TOKEN" ]]; then
    echo "==> Pushing packages to build cache"
    spack -e $EXP_ENV mirror set --push \
         --oci-username mdorier \
         --oci-password $MOCHI_BUILDCACHE_TOKEN mochi-buildcache
    spack -e $EXP_ENV buildcache push --base-image ubuntu:22.04 \
          --unsigned --update-index --only dependencies mochi-buildcache
fi

echo "==> Creating activate.sh script"
spack env activate --sh $EXP_ENV > $SANDBOX/bin/activate.sh

echo "==> Cloning Mofka repository"
cd $SANDBOX
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

echo "==> Activating environment"
source $SANDBOX/bin/activate.sh

echo "==> Building Mofka for performance"
cmake -S mofka -B mofka-build-release \
    -DCMAKE_BUILD_TYPE=Release -DENABLE_BENCHMARK=ON -DENABLE_PYTHON=ON \
    -DCMAKE_C_COMPILER=cc -DCMAKE_CXX_COMPILER=CC \
    -DCMAKE_INSTALL_PREFIX=$SANDBOX/mofka-release
cmake --build mofka-build-release
cmake --install mofka-build-release

echo "==> Building Mofka for coverage"
cmake -S mofka -B mofka-build-coverage \
    -DCMAKE_BUILD_TYPE=Debug -DENABLE_BENCHMARK=ON -DENABLE_PYTHON=ON -DENABLE_COVERAGE=ON \
    -DCMAKE_C_COMPILER=cc -DCMAKE_CXX_COMPILER=CC \
    -DCMAKE_INSTALL_PREFIX=$SANDBOX/mofka-coverage
cmake --build mofka-build-coverage
cmake --install mofka-build-coverage

echo "==> Cleaning up release build"
rm -rf mofka-build-release

echo "==> Cleaning up coverage build (keep .gcno files)"
find mofka-build-coverage -type f ! -name "*.gcno" -delete
find mofka-build-coverage -type d -empty -delete

echo "==> Cleaning up the environments"
#spack -e $EXP_ENV gc -y
#find "$SANDBOX" -type d -name "include" -exec rm -rf {} +
find "$SANDBOX" -type d -name ".spack" -exec rm -rf {} +
find "$SANDBOX" -type d -name ".spack-db" -exec rm -rf {} +
find "$SANDBOX" -type d -name "share" -exec rm -rf {} +
find "$SANDBOX" -type d -name "__pycache__" -exec rm -rf {} +

echo "==> Writing info file"
cat << EOF > $SANDBOX/info.json
{
    "mochi-spack-package": "${MOCHI_SPACK_PACKAGES_HASH}",
    "spack": "${SPACK_LATEST}",
    "mofka": "${MOFKA_GITHUB_SHA}"
}
EOF

echo "==> Setup completed!"
