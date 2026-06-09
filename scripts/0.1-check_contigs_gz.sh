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
#SBATCH --array=1-1379%100   # This is: wc -l resources/acc_map.tsv

###############################################################################
# ENVIRONMENT AND INITIAL SETUP
###############################################################################

source /home/epereira/workspace/dev/ocean-metagenomes/conf.sh
set -euo pipefail

###############################################################################
# SELECT ACCESSION FOR THIS ARRAY TASK
###############################################################################

ACC_MAP="${RESOURCES}/acc_map.tsv"
TOTAL=$(wc -l < "${ACC_MAP}")

if [[ ${SLURM_ARRAY_TASK_ID} -gt ${TOTAL} ]]; then
    echo "ERROR: Array task ID ${SLURM_ARRAY_TASK_ID} exceeds number of accessions (${TOTAL})"
    exit 1
fi

ACC=$(awk -v line="${SLURM_ARRAY_TASK_ID}" 'NR==line {print $1}' "${ACC_MAP}")

###############################################################################
# CHECK GZIP INTEGRITY
###############################################################################

LOG="${WORKSPACE}/data/inbox/${ACC}_file_check.txt"

FILE=$(ls "${CONTIGS}/${ACC}"*FASTA.fasta.gz 2>/dev/null || true)

if [[ -z "${FILE}" ]]; then
    echo "MISSING: ${ACC} — no *FASTA.fasta.gz found in ${CONTIGS}" | tee -a "${LOG}"
    exit 0
fi

gzip -tv "${FILE}" 2>&1 | tee -a "${LOG}"
