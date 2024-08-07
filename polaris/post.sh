#!/bin/bash

SANDBOX=$CI_PROJECT_DIR/sandbox

exit 0

if [[ -z "$MOCHI_GH_POLARIS" ]]; then
    echo "==> ERROR: MOCHI_GH_POLARIS not defined"
    exit -1
fi

RESULT_FILE=$(find $CI_PROJECT_DIR/results -type f -name "*.json")
if [[ -z "$RESULT_FILE" ]]; then
    echo "==> ERROR: Could not locate any result file"
    exit -1
fi
RESULT_FILE_NAME=$(basename $RESULT_FILE)

echo "==> Cloning mofka-performance-evaluation"
git clone https://github.com/mochi-hpc-experiments/mofka-performance-evaluation.git
cd mofka-performance-evaluation
mkdir -p polaris/results

echo "==> Changing branch"
git checkout results/polaris

echo "==> Copying result file $RESULT_FILE_NAME"
cp $RESULT_FILE polaris/results

echo "==> Creating commit"
git add polaris/results/$RESULT_FILE_NAME
git commit -m "Added file $RESULT_FILE_NAME"

echo "==> Changing repository URL"
git remote set-url origin "https://$MOCHI_GH_POLARIS@github.com/mochi-hpc-experiments/mofka-performance-evaluation.git"

echo "==> Pushing into repository"
git push
