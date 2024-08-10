#!/bin/bash

qsub -l select=4:system=polaris -l place=scatter -l walltime=0:15:00 -l filesystems=home -q debug-scaling -A radix-io ./run.qsub
