#!/bin/bash
###############################################################################
# SLURM SETTINGS
###############################################################################
#SBATCH --job-name=download_assemblies
#SBATCH --output=/home/epereira/workspace/dev/ocean-metagenomes/logs/slurm_logs/%x_%A_%a.out
#SBATCH --error=/home/epereira/workspace/dev/ocean-metagenomes/logs/slurm_logs/%x_%A_%a.err
#SBATCH --time=02:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --array=1-226%5   # Replace NLINES with: grep -c . <erz_accessions_file>

###############################################################################
# ENVIRONMENT AND INITIAL SETUP
###############################################################################

source /home/epereira/workspace/dev/ocean-metagenomes/conf.sh
set -euo pipefail

# Path to file with one ERZ accession per line
ERZ_FILE="/home/epereira/workspace/dev/ocean-metagenomes/resources/incomplete_files.txt"   # <-- set this path before submitting

if [[ -z "$ERZ_FILE" ]]; then
    echo "[ERROR] ERZ_FILE is not set"
    exit 1
fi

if [[ ! -f "$ERZ_FILE" ]]; then
    echo "[ERROR] File not found: $ERZ_FILE"
    exit 1
fi

###############################################################################
# SELECT ACCESSION FOR THIS ARRAY TASK
###############################################################################

mapfile -t ACCESSIONS < <(grep -v '^#' "$ERZ_FILE" | grep -v '^$')
TOTAL=${#ACCESSIONS[@]}

if [[ ${SLURM_ARRAY_TASK_ID} -gt ${TOTAL} ]]; then
    echo "[ERROR] Array task ID ${SLURM_ARRAY_TASK_ID} exceeds number of accessions (${TOTAL})"
    exit 1
fi

ERZ="${ACCESSIONS[$((SLURM_ARRAY_TASK_ID - 1))]}"

###############################################################################
# DOWNLOAD
###############################################################################

OUT_DIR="${DATA}/inbox"
LOG="${OUT_DIR}/${ERZ}_download.log"

mkdir -p "${OUT_DIR}"

echo "[INFO] Processing ${ERZ}" | tee -a "${LOG}"

# query ENA filereport API
FTP_URL=$(curl -s \
    "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${ERZ}&result=analysis&fields=submitted_ftp" \
    | awk -F'\t' 'NR==2 {print $2}')

if [[ -z "$FTP_URL" ]]; then
    echo "[WARN] No FTP URL found for ${ERZ} — skipping." | tee -a "${LOG}"
    exit 0
fi

echo "[INFO] Downloading ${FTP_URL}" | tee -a "${LOG}"

ORIGINAL_NAME=$(basename "$FTP_URL")
EXTENSION="${ORIGINAL_NAME#*.}"   # everything after first dot (e.g. fasta.gz)
OUT_FILE="${OUT_DIR}/${ERZ}.${EXTENSION}"

wget -q --show-progress -O "${OUT_FILE}" "${FTP_URL}" 2>&1 | tee -a "${LOG}"

echo "[INFO] Saved as ${OUT_FILE}" | tee -a "${LOG}"
