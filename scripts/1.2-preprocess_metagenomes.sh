#!/bin/bash
###############################################################################
# ENVIRONMENT AND INITIAL SETUP
###############################################################################

# Load configuration
source /home/epereira/workspace/dev/ocean-metagenomes/conf.sh
set -o pipefail

# Create preprocessed dir if it does not exists
if [[ ! -d "${DATA}/preprocessed" ]]; then
    echo "Creating preprocessed data directory: ${DATA}/preprocessed"
    mkdir -p "${DATA}/preprocessed"
fi

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
    echo "Task ${SLURM_ARRAY_TASK_ID}: Processing accession ${SRR_ACC}"
fi

if [[ -z "${SRR_ACC}" ]]; then
    echo "ERROR: No accession found (provide as \$1 or via SLURM_ARRAY_TASK_ID)"
    exit 1
fi

###############################################################################
# PREPROCESS FUNCTION
###############################################################################

preprocess_metagenomes() {
    local SRR_ACC="$1"
    local RAW_DIR="${DATA}/raw/${SRR_ACC}"
    local OUTPUT_DIR="${DATA}/preprocessed/${SRR_ACC}"
    local LOG_FILE="${DATA}/preprocessed/${SRR_ACC}.log"

    # Skip only if SUCCESS tag is found in the log
    if [[ -f "${LOG_FILE}" ]] && grep -q "^SUCCESS:" "${LOG_FILE}"; then
        echo "SKIPPED: ${SRR_ACC} already preprocessed (SUCCESS tag found in log)"
        return 0
    fi

    # No SUCCESS tag — remove any partial output and re-preprocess
    [[ -d "${OUTPUT_DIR}" ]] && rm -rf "${OUTPUT_DIR}"

    # Write header log
    {
        echo "=== Preprocess log for ${SRR_ACC} ==="
        echo "Started: $(date)"
        echo "Job ID: ${SLURM_JOB_ID}"
        echo "Array Task: ${SLURM_ARRAY_TASK_ID}"
        echo "Node: $(hostname)"
        echo "Raw data directory: ${RAW_DIR}"
        echo "Output directory: ${OUTPUT_DIR}"
        echo "-----------------------------------"
    } > "${LOG_FILE}"

    # Check if raw data exists
    if [[ ! -d "${RAW_DIR}" ]]; then
        echo "ERROR: Raw data not found for ${SRR_ACC} at ${RAW_DIR}" | tee -a "${LOG_FILE}"
        return 1
    fi

    # Find R1 and R2 reads
    R1=$(find "${RAW_DIR}" \( -name "*_1.fastq.gz" -o -name "*_R1*.fastq.gz" -o -name "*_1.fq.gz" \) | head -1)
    R2=$(find "${RAW_DIR}" \( -name "*_2.fastq.gz" -o -name "*_R2*.fastq.gz" -o -name "*_2.fq.gz" \) | head -1)

    if [[ -z "${R1}" || -z "${R2}" ]]; then
        echo "ERROR: Could not find paired-end reads for ${SRR_ACC}" | tee -a "${LOG_FILE}"
        return 1
    fi

    echo "Found R1: ${R1}" | tee -a "${LOG_FILE}"
    echo "Found R2: ${R2}" | tee -a "${LOG_FILE}"

    # Run preprocessing pipeline
    echo "Running preprocessing pipeline for ${SRR_ACC}..." | tee -a "${LOG_FILE}"
    
    "${SCRIPTS}/toolbox/metagenomic_pipelines/modules/2-preprocess_pipeline.sh" \
        --reads "${R1}" \
        --reads2 "${R2}" \
        --sample_name "${SRR_ACC}" \
        --output_dir "${OUTPUT_DIR}" \
        --nslots "${SLURM_CPUS_PER_TASK}" \
        --min_length 75 \
        --min_qual 20 \
        --trim_adapters t \
        --output_merged f \
        --output_pe t \
        --clean t \
        --compress t \
        --overwrite f \
        2>&1 | tee -a "${LOG_FILE}"

    STATUS=${PIPESTATUS[0]}

    if [[ ${STATUS} -eq 0 ]]; then
        echo "SUCCESS: ${SRR_ACC} preprocessed at $(date)" | tee -a "${LOG_FILE}"
        return 0
    else
        echo "ERROR: Preprocessing failed for ${SRR_ACC} at $(date)" | tee -a "${LOG_FILE}"
        return 1
    fi
}

###############################################################################
# RUN
###############################################################################

# Activate metagenomic_pipeline environment before running
echo "Activating metagenomic_pipeline environment..."
conda activate metagenomic_pipeline
    
if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to activate metagenomic_pipeline environment"
    exit 1
fi

preprocess_metagenomes "${SRR_ACC}"
RESULT=$?

# Deactivate environment
conda deactivate 2>/dev/null

exit ${RESULT}
