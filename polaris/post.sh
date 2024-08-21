#!/bin/bash

HERE=`dirname $0`
HERE=`realpath $HERE`
source $HERE/util.sh

WORK_DIR=$(car work_dir.txt)

if [ -z "${WORK_DIR}" ]; then
    echo "==> ERROR: Could not find WORK_DIR"
    exit -1
fi
echo "== WORK_DIR is $WORK_DIR"

if [[ -z "$MOCHI_GH_POLARIS" ]]; then
    echo "==> ERROR: MOCHI_GH_POLARIS not defined"
    exit -1
fi

RESULTS_DIR=$WORK_DIR/results
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

popd # mofka-performance-evaluation

#rm -rf $WORK_DIR
