#!/bin/bash
###############################################################################
# SLURM SETTINGS
###############################################################################
#SBATCH --job-name=check_md5_sequences
#SBATCH --output=/home/epereira/workspace/dev/ocean-metagenomes/logs/slurm_logs/%x_%A_%a.out
#SBATCH --error=/home/epereira/workspace/dev/ocean-metagenomes/logs/slurm_logs/%x_%A_%a.err
#SBATCH --time=01:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --array=1-225%20  # Replace 225 with: ls data/inbox/*.fasta.gz | wc -l

###############################################################################
# ENVIRONMENT AND INITIAL SETUP
###############################################################################

source /home/epereira/workspace/dev/ocean-metagenomes/conf.sh
set -euo pipefail

# Number of sequences to check (set before submitting)
N_SEQS=10

###############################################################################
# SELECT FILE FOR THIS ARRAY TASK
###############################################################################

mapfile -t FILES < <(ls "${DATA}/inbox"/*.fasta.gz)
TOTAL=${#FILES[@]}

if [[ ${SLURM_ARRAY_TASK_ID} -gt ${TOTAL} ]]; then
    echo "[ERROR] Array task ID ${SLURM_ARRAY_TASK_ID} exceeds number of files (${TOTAL})"
    exit 1
fi

INBOX_FILE="${FILES[$((SLURM_ARRAY_TASK_ID - 1))]}"

###############################################################################
# FIND MATCHING ASSEMBLY FILE
###############################################################################

# Extract ERZ accession from inbox filename (e.g. ERZ11848501.fasta.gz -> ERZ11848501)
BASENAME=$(basename "${INBOX_FILE}")
ERZ="${BASENAME%%.*}"

LOG="${DATA}/inbox/${ERZ}_md5check.log"

echo "[INFO] Checking ${ERZ} — first ${N_SEQS} sequences" | tee "${LOG}"

# Find the corresponding file in assemblies (matches ERZ accession prefix)
ASSEMBLY_FILE=$(ls "${CONTIGS}/${ERZ}"*.fasta.gz 2>/dev/null | head -1)

if [[ -z "${ASSEMBLY_FILE}" ]]; then
    echo "[ERROR] No matching assembly file found for ${ERZ} in ${CONTIGS}" | tee -a "${LOG}"
    exit 1
fi

echo "[INFO] Inbox:    ${INBOX_FILE}" | tee -a "${LOG}"
echo "[INFO] Assembly: ${ASSEMBLY_FILE}" | tee -a "${LOG}"

###############################################################################
# COMPUTE MD5SUM OF FIRST N SEQUENCES (sequences only, no headers)
###############################################################################

# Extract first N sequences content (no headers, no whitespace) and compute md5sum
# pipefail disabled here: awk early exit causes zcat SIGPIPE (exit 141), which
# would trigger set -e. Safe to disable as we check md5 values explicitly below.
set +o pipefail

md5_inbox=$(zcat "${INBOX_FILE}" \
    | awk -v n="${N_SEQS}" '
        /^>/ { count++; if (count > n) exit; next }
        count > 0 { gsub(/[[:space:]]/, ""); printf "%s", $0 }
    ' | md5sum | awk '{print $1}')

md5_assembly=$(zcat "${ASSEMBLY_FILE}" \
    | awk -v n="${N_SEQS}" '
        /^>/ { count++; if (count > n) exit; next }
        count > 0 { gsub(/[[:space:]]/, ""); printf "%s", $0 }
    ' | md5sum | awk '{print $1}')

set -o pipefail

echo "[INFO] MD5 inbox:    ${md5_inbox}" | tee -a "${LOG}"
echo "[INFO] MD5 assembly: ${md5_assembly}" | tee -a "${LOG}"

###############################################################################
# COMPARE
###############################################################################

if [[ "${md5_inbox}" == "${md5_assembly}" ]]; then
    echo "[OK] ${ERZ}: MD5 match for first ${N_SEQS} sequences" | tee -a "${LOG}"
else
    echo "[MISMATCH] ${ERZ}: MD5 differs for first ${N_SEQS} sequences" | tee -a "${LOG}"
    exit 1
fi
