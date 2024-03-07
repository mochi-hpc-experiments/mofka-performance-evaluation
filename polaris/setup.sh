#!/bin/bash
set -e

module swap PrgEnv-nvhpc PrgEnv-gnu || true

echo "==> Creating sandbox folder"
mkdir sandbox
SANDBOX=$(realpath sandbox)
ORIGIN=$(dirname "$0")

echo "==> Copying qsub script in sandbox folder"
mkdir $SANDBOX/bin
cp $ORIGIN/run.qsub $SANDBOX/bin

echo "==> Downloading spack"
git clone -q https://github.com/spack/spack.git

echo "==> Finding latest release"
SPACK_LATEST=$(git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -t . -k 1,1n -k 2,2n -k 3,3n | tail -n 1)

echo "==> Checking out latest release ${SPACK_LATEST}"
cd spack
git checkout -q $SPACK_LATEST
cd ..

echo "==> Downloading mochi-spack-packages"
git clone -q https://github.com/mochi-hpc/mochi-spack-packages.git

echo "==> Downloading platform configurations"
git clone -q https://github.com/mochi-hpc-experiments/platform-configurations.git

echo "==> Sourcing setup-env.sh"
. spack/share/spack/setup-env.sh
spack config add config:environments_root:$SANDBOX/environments

echo "==> Creating experiment environment"
spack env create experiment platform-configurations/ANL/Polaris/spack.yaml
spack env activate experiment
spack config add config:install_tree:root:$SANDBOX/
spack repo add mochi-spack-packages
spack add mofka+python
spack add py-mochi-ssg~mpi

echo "==> Installing environment"
spack install

echo "==> Creating activate.sh script"
spack env activate --sh experiment > $SANDBOX/bin/activate.sh
source $SANDBOX/bin/activate.sh

echo "==> Setup completed!"
