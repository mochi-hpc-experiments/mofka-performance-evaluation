#!/bin/bash
set -e

echo "This is the setup phase"

mkdir sandbox
SANDBOX=$(realpath sandbox)
ORIGIN=$(dirname "$0")

module swap PrgEnv-nvhpc PrgEnv-gnu || true

mkdir $SANDBOX/bin

cp run.qsub $SANDBOX/bin
