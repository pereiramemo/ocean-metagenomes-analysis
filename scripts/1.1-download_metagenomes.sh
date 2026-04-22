#!/bin/bash
###############################################################################
# ENVIRONMENT AND INITIAL SETUP
###############################################################################

# Load configuration
source /home/epereira/workspace/dev/ocean-metagenomes/conf.sh
set -o pipefail

# Create raw dir if it does not exists
if [[ ! -d "${DATA}/raw" ]]; then
    echo "Creating raw data directory: ${DATA}/raw"
    mkdir -p "${DATA}/raw"
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
# VALIDATION FUNCTIONS
###############################################################################

validate_download() {
    local OUT_DIR="$1"
    local SRR_ACC="$2"

    # Check if directory exists
    if [[ ! -d "${OUT_DIR}" ]]; then
        echo "VALIDATION FAILED: Directory ${OUT_DIR} does not exist"
        return 1
    fi

    # Check if directory is not empty
    if [[ -z "$(ls -A "${OUT_DIR}" 2>/dev/null)" ]]; then
        echo "VALIDATION FAILED: Directory ${OUT_DIR} is empty"
        return 1
    fi

    # Check for FASTQ files (compressed or uncompressed)
    local fastq_files=$(find "${OUT_DIR}" -type f \( -name "*.fastq.gz" -o -name "*.fastq" -o -name "*.fq.gz" -o -name "*.fq" \) 2>/dev/null)
    if [[ -z "${fastq_files}" ]]; then
        echo "VALIDATION FAILED: No FASTQ files found in ${OUT_DIR}"
        return 1
    fi

    # Count FASTQ files
    local fastq_count=$(echo "${fastq_files}" | wc -l)
    echo "Found ${fastq_count} FASTQ file(s)"

    # Validate each FASTQ file
    local all_valid=true
    while IFS= read -r fastq_file; do
        # Check file is not empty
        if [[ ! -s "${fastq_file}" ]]; then
            echo "VALIDATION FAILED: ${fastq_file} is empty"
            all_valid=false
            continue
        fi

        # Check file size (at least 1KB)
        local file_size=$(stat -c%s "${fastq_file}" 2>/dev/null || echo 0)
        if [[ ${file_size} -lt 1024 ]]; then
            echo "VALIDATION FAILED: ${fastq_file} is too small (${file_size} bytes)"
            all_valid=false
            continue
        fi

        echo "VALIDATED: ${fastq_file} (${file_size} bytes)"
    done <<< "${fastq_files}"

    if [[ "${all_valid}" == "true" ]]; then
        echo "VALIDATION SUCCESS: All files for ${SRR_ACC} are valid"
        return 0
    else
        echo "VALIDATION FAILED: Some files for ${SRR_ACC} are invalid"
        return 1
    fi
}

###############################################################################
# DOWNLOAD FUNCTION WITH RETRY LOGIC
###############################################################################

download_metagenomes() {
    local SRR_ACC="$1"
    local OUTPUT_DIR="$2"
    local OUT_DIR="${OUTPUT_DIR}/${SRR_ACC}"
    local OUT_LOG="${OUTPUT_DIR}/${SRR_ACC}.log"

    # Ensure kingfisher exists
    command -v kingfisher >/dev/null 2>&1 || {
    echo "ERROR: kingfisher not found in PATH"; exit 1;
    }

    # Remove any partial output and re-download
    [[ -d "${OUT_DIR}" ]] && rm -rf "${OUT_DIR}"

    # Write header log
    {
        echo "=== Download log for ${SRR_ACC} ==="
        echo "Started: $(date)"
        echo "Job ID: ${SLURM_JOB_ID}"
        echo "Array Task: ${SLURM_ARRAY_TASK_ID}"
        echo "Node: $(hostname)"
        echo "-----------------------------------"
    } > "${OUT_LOG}"

    # Retry loop (10 attempts)
    for attempt in {1..10}; do
        echo "Attempt ${attempt}/10 for ${SRR_ACC}..." | tee -a "${OUT_LOG}"

        kingfisher get \
            --run-identifiers "${SRR_ACC}" \
            --download-methods aws-http ena-ascp ena-ftp aws-cp prefetch \
            --output-directory "${OUT_DIR}" \
            --download-threads 2 \
            --check-md5sums \
            --extraction-threads 2 \
            --output-format-possibilities fastq.gz \
            2>&1 | tee -a "${OUT_LOG}"

        STATUS=${PIPESTATUS[0]}

        if [[ $STATUS -eq 0 ]]; then
            echo "SUCCESS: ${SRR_ACC} downloaded at $(date)" | tee -a "${OUT_LOG}"

            # Validate the downloaded data
            echo "Validating downloaded files..." | tee -a "${OUT_LOG}"
            if validate_download "${OUT_DIR}" "${SRR_ACC}" >> "${OUT_LOG}" 2>&1; then
                echo "VALIDATION SUCCESS: ${SRR_ACC} verified" | tee -a "${OUT_LOG}"
                return 0
            else
                echo "WARNING: Download succeeded but validation failed. Removing and retrying..." | tee -a "${OUT_LOG}"
                rm -rf "${OUT_DIR}"
                sleep 60  # Brief pause before retry
                continue  # Skip to next attempt
            fi
        else
            echo "Failed attempt ${attempt} for ${SRR_ACC}." | tee -a "${OUT_LOG}"
            sleep 360 # Wait before retrying
        fi
    done

    echo "ERROR: All 10 attempts failed for ${SRR_ACC}" | tee -a "${OUT_LOG}"
    return 1
}

###############################################################################
# RUN
###############################################################################

# Activate metagenomic_pipeline environment before running
echo "Activating metagenomic_pipeline environment..."
conda activate ocean-metagenomes-env
    
if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to activate metagenomic_pipeline environment"
    exit 1
fi

download_metagenomes "${SRR_ACC}" "${DATA}/raw"
RESULT=$?

# Deactivate environment
conda deactivate 2>/dev/null

exit ${RESULT}
