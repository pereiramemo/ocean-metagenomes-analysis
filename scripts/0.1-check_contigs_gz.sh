#!/bin/bash
###############################################################################
# SLURM SETTINGS
###############################################################################
#SBATCH --job-name=check_contigs_gz
#SBATCH --output=/home/epereira/workspace/dev/ocean-metagenomes/logs/slurm_logs/%x_%A_%a.out
#SBATCH --error=/home/epereira/workspace/dev/ocean-metagenomes/logs/slurm_logs/%x_%A_%a.err
#SBATCH --time=01:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --array=1-2114%25   # This is: ls $CONTIGS/*.fasta.gz | wc -l

###############################################################################
# ENVIRONMENT AND INITIAL SETUP
###############################################################################

source /home/epereira/workspace/dev/ocean-metagenomes/conf.sh
set -euo pipefail

###############################################################################
# SELECT FILE FOR THIS ARRAY TASK
###############################################################################

mapfile -t FILES < <(ls "${CONTIGS}"/*.fasta.gz)
TOTAL=${#FILES[@]}

if [[ ${SLURM_ARRAY_TASK_ID} -gt ${TOTAL} ]]; then
    echo "ERROR: Array task ID ${SLURM_ARRAY_TASK_ID} exceeds number of files (${TOTAL})" | tee -a "${LOG}"
    exit 1
fi

FILE="${FILES[$((SLURM_ARRAY_TASK_ID - 1))]}"

###############################################################################
# CHECK GZIP INTEGRITY
###############################################################################

FILE_NAME=$(basename "${FILE}")

LOG="${DATA}/assemblies/${FILE_NAME}_file_check.log"

gzip -tv "${FILE}" 2>&1 | tee -a "${LOG}"
