#!/bin/bash
set -e

echo "This is the setup phase"

mkdir sandbox
SANDBOX=$(realpath sandbox)
ORIGIN=$(dirname "$0")

module swap PrgEnv-nvhpc PrgEnv-gnu || true

mkdir $SANDBOX/bin

cp $ORIGIN/run.qsub $SANDBOX/bin
