#!/bin/bash

SANDBOX=$CI_PROJECT_DIR/sandbox
source $SANDBOX/bin/util.sh

if [[ -z "$MOCHI_GH_POLARIS" ]]; then
    echo "==> ERROR: MOCHI_GH_POLARIS not defined"
    exit -1
fi

RESULTS_DIR=$CI_PROJECT_DIR/results
if [ -z "$(ls -A $RESULTS_DIR)" ]; then
    echo "==> No results to commit"
    exit -1
fi

echo "==> Cloning mofka-performance-evaluation"
git clone https://github.com/mochi-hpc-experiments/mofka-performance-evaluation.git
pushd mofka-performance-evaluation

echo "==> Changing branch"
git checkout results/polaris

mkdir -p polaris/results
pushd polaris/results

num_files=0
for DIR in $RESULTS_DIR/*; do
    if [ -d "$DIR" ]; then
        ARCHIVE="$(basename $DIR).tar.gz"
        echo "Processing directory: $DIR => $ARCHIVE"
        mv $DIR .
        DIR=$(basename $DIR)
        tar czf $ARCHIVE $DIR
        git add $ARCHIVE
        num_files=$((num_files+1))
    fi
done

popd # polaris/results

echo "==> Creating commit"
git commit -m "Added new ${num_files} new files on $(date)"

echo "==> Changing repository URL"
git remote set-url origin "https://$MOCHI_GH_POLARIS@github.com/mochi-hpc-experiments/mofka-performance-evaluation.git"

echo "==> Pushing into repository"
git push
