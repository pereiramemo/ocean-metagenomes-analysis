#!/bin/bash
###############################################################################
# ENVIRONMENT AND INITIAL SETUP
###############################################################################

# Load configuration
source /home/epereira/workspace/dev/ocean-metagenomes/conf.sh
set -o pipefail

# Ensure accession file exists
if [[ ! -f "${RESOURCES}/acc_map.tsv" ]]; then
    echo "ERROR: Accession list not found: ${RESOURCES}/acc_map.tsv"
    exit 1
fi

###############################################################################
# SELECT ACCESSION FOR THIS ARRAY TASK
# When called from the orchestrator (1.0-metagenome_pipeline.sh), $1 is the
# SRR accession. When submitted as a standalone SLURM array job, the accession
# is looked up from acc_map.tsv using SLURM_ARRAY_TASK_ID.
###############################################################################

if [[ -n "${1:-}" ]]; then
    SRR_ACC="$1"
    echo "Accession provided as argument: ${SRR_ACC}"
else
    LINE_NUM="${SLURM_ARRAY_TASK_ID}"
    SRR_ACC=$(sed -n "${LINE_NUM}p" "${RESOURCES}/acc_map.tsv" | cut -f2)
    echo "Task ${SLURM_ARRAY_TASK_ID}: Cleaning up FASTQ files for ${SRR_ACC}"
fi

if [[ -z "${SRR_ACC}" ]]; then
    echo "ERROR: No accession found (provide as \$1 or via SLURM_ARRAY_TASK_ID)"
    exit 1
fi

###############################################################################
# CLEANUP FUNCTION
###############################################################################

cleanup_fastq() {
    local SRR_ACC="$1"
    local RAW_DIR="${DATA}/raw/${SRR_ACC}"
    local PREPROC_DIR="${DATA}/preprocessed/${SRR_ACC}"
    local RAW_DELETED_LOG="${RAW_DIR}/${SRR_ACC}_deleted.log"
    local PREPROC_DELETED_LOG="${PREPROC_DIR}/${SRR_ACC}_deleted.log"

    # Skip if both logs have SUCCESS tag
    if [[ -f "${RAW_DELETED_LOG}" ]] && grep -q "^SUCCESS:" "${RAW_DELETED_LOG}" && \
       [[ -f "${PREPROC_DELETED_LOG}" ]] && grep -q "^SUCCESS:" "${PREPROC_DELETED_LOG}"; then
        echo "SKIPPED: ${SRR_ACC} already cleaned (SUCCESS tag found in both logs)"
        return 0
    fi

    # Remove FASTQ files from raw directory
    if [[ -d "${RAW_DIR}" ]]; then
        echo "Cleaning raw FASTQ files for ${SRR_ACC}..."
        > "${RAW_DELETED_LOG}"
        while IFS= read -r -d '' f; do
            { [[ "${f}" == *.gz ]] && zcat "${f}" || cat "${f}"; } \
                | md5sum | awk -v f="${f}" '{print $1"  "f}' | tee -a "${RAW_DELETED_LOG}"
            rm "${f}"
            echo "DELETED: ${f}" | tee -a "${RAW_DELETED_LOG}"
        done < <(find "${RAW_DIR}" -type f \( -name "*.fastq.gz" -o -name "*.fastq" -o -name "*.fq.gz" -o -name "*.fq" \) -print0)
        echo "SUCCESS: ${SRR_ACC} raw FASTQ files removed at $(date)" | tee -a "${RAW_DELETED_LOG}"
    else
        echo "WARNING: Raw directory not found: ${RAW_DIR}"
    fi

    # Remove FASTQ files from preprocessed directory (keep *.log and stats.tsv)
    if [[ -d "${PREPROC_DIR}" ]]; then
        echo "Cleaning preprocessed FASTQ files for ${SRR_ACC}..."
        > "${PREPROC_DELETED_LOG}"
        while IFS= read -r -d '' f; do
            { [[ "${f}" == *.gz ]] && zcat "${f}" || cat "${f}"; } \
                | md5sum | awk -v f="${f}" '{print $1"  "f}' | tee -a "${PREPROC_DELETED_LOG}"
            rm "${f}"
            echo "DELETED: ${f}" | tee -a "${PREPROC_DELETED_LOG}"
        done < <(find "${PREPROC_DIR}" -type f \( -name "*.fastq.gz" -o -name "*.fastq" -o -name "*.fq.gz" -o -name "*.fq" \) -print0)
        echo "SUCCESS: ${SRR_ACC} preprocessed FASTQ files removed at $(date)" | tee -a "${PREPROC_DELETED_LOG}"
    else
        echo "WARNING: Preprocessed directory not found: ${PREPROC_DIR}"
    fi

    return 0
}

###############################################################################
# RUN
###############################################################################

cleanup_fastq "${SRR_ACC}"
exit $?
