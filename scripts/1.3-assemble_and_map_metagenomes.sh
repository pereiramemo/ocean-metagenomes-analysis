#!/bin/bash
###############################################################################
# ENVIRONMENT AND INITIAL SETUP
###############################################################################

# Load configuration
source /home/epereira/workspace/dev/ocean-metagenomes/conf.sh
set -o pipefail

# Create mapped dir if it does not exists
if [[ ! -d "${DATA}/mapped" ]]; then
    echo "Creating mapped data directory: ${DATA}/mapped"
    mkdir -p "${DATA}/mapped"
fi

# Ensure accession file exists
if [[ ! -f "${RESOURCES}/acc_map.tsv" ]]; then
    echo "ERROR: Accession list not found: ${RESOURCES}/acc_map.tsv"
    exit 1
fi

###############################################################################
# SELECT ACCESSION FOR THIS ARRAY TASK
# When called from the orchestrator (1.0-metagenome_pipeline.sh), $1 is the
# SRR accession and $2 is the ERZ accession. When submitted as a standalone
# SLURM array job, both are looked up from acc_map.tsv using SLURM_ARRAY_TASK_ID.
###############################################################################

if [[ -n "${1:-}" ]]; then
    SRR_ACC="$1"
    ERZ_ACC="${2:-}"
    if [[ -z "${ERZ_ACC}" ]]; then
        echo "ERROR: ERZ accession must be provided as \$2 when calling with arguments"
        exit 1
    fi
    echo "Accessions provided as arguments: SRR=${SRR_ACC} ERZ=${ERZ_ACC}"
else
    LINE_NUM="${SLURM_ARRAY_TASK_ID}"
    SRR_ACC=$(sed -n "${LINE_NUM}p" "${RESOURCES}/acc_map.tsv" | cut -f2)
    ERZ_ACC=$(sed -n "${LINE_NUM}p" "${RESOURCES}/acc_map.tsv" | cut -f1)
    echo "Task ${SLURM_ARRAY_TASK_ID}: Processing accession ${SRR_ACC} (ERZ: ${ERZ_ACC})"
fi

if [[ -z "${SRR_ACC}" ]]; then
    echo "ERROR: No SRR accession found (provide as \$1 or via SLURM_ARRAY_TASK_ID)"
    exit 1
fi

if [[ -z "${ERZ_ACC}" ]]; then
    echo "ERROR: No ERZ accession found (provide as \$2 or via SLURM_ARRAY_TASK_ID)"
    exit 1
fi

###############################################################################
# ASSEMBLY AND MAPPING FUNCTION
###############################################################################

assemble_and_map_metagenomes() {
    local SRR_ACC="$1"
    local ERZ_ACC="$2"
    local PREPROC_DIR="${DATA}/preprocessed/${SRR_ACC}"
    local OUTPUT_DIR="${DATA}/mapped/${SRR_ACC}"
    local LOG_FILE="${DATA}/mapped/${SRR_ACC}.log"
    local ASSEMBLY_FILE="${CONTIGS}/${ERZ_ACC}.fasta.gz"
   
    # Skip only if SUCCESS tag is found in the log
    if [[ -f "${LOG_FILE}" ]] && grep -q "^SUCCESS:" "${LOG_FILE}"; then
        echo "SKIPPED: ${SRR_ACC} already assembled and mapped (SUCCESS tag found in log)"
        return 0
    fi

    # No SUCCESS tag — remove any partial output and re-process
    [[ -d "${OUTPUT_DIR}" ]] && rm -rf "${OUTPUT_DIR}"

    # Write header log
    {
        echo "=== Assembly and mapping log for ${SRR_ACC} ==="
        echo "Started: $(date)"
        echo "Job ID: ${SLURM_JOB_ID}"
        echo "Array Task: ${SLURM_ARRAY_TASK_ID}"
        echo "Node: $(hostname)"
        echo "Preprocessed data directory: ${PREPROC_DIR}"
        echo "Output directory: ${OUTPUT_DIR}"
        echo "-----------------------------------"
    } > "${LOG_FILE}"

    # Check if preprocessed data exists
    if [[ ! -d "${PREPROC_DIR}" ]]; then
        echo "ERROR: Preprocessed data not found for ${SRR_ACC} at ${PREPROC_DIR}" | tee -a "${LOG_FILE}"
        return 1
    fi

    # Find R1 and R2 reads in preprocessed directory
    R1=$(find "${PREPROC_DIR}" \( -name "*_1.fastq.gz" -o -name "*_R1*.fastq.gz" -o -name "*_1.fq.gz" \) | head -1)
    R2=$(find "${PREPROC_DIR}" \( -name "*_2.fastq.gz" -o -name "*_R2*.fastq.gz" -o -name "*_2.fq.gz" \) | head -1)

    if [[ -z "${R1}" || -z "${R2}" ]]; then
        echo "ERROR: Could not find paired-end reads for ${SRR_ACC}" | tee -a "${LOG_FILE}"
        return 1
    fi

    echo "Found R1: ${R1}" | tee -a "${LOG_FILE}"
    echo "Found R2: ${R2}" | tee -a "${LOG_FILE}"

    # Run assembly and mapping pipeline
    echo "Running assembly and mapping pipeline for ${SRR_ACC}..." | tee -a "${LOG_FILE}"

    "${SCRIPTS}/toolbox/metagenomic_pipelines/modules/3-assembly_and_map_pipeline.sh" \
        --reads1 "${R1}" \
        --reads2 "${R2}" \
        --contigs "${ASSEMBLY_FILE}" \
        --sample_name "${SRR_ACC}" \
        --output_dir "${OUTPUT_DIR}" \
        --nslots "${SLURM_CPUS_PER_TASK}" \
        --overwrite f \
        2>&1 | tee -a "${LOG_FILE}"

    STATUS=${PIPESTATUS[0]} 

    if [[ ${STATUS} -eq 0 ]]; then
        echo "SUCCESS: ${SRR_ACC} (${ERZ_ACC}) assembled and mapped at $(date)" | tee -a "${LOG_FILE}"
        return 0
    else
        echo "ERROR: Assembly and mapping failed for ${SRR_ACC} (${ERZ_ACC}) at $(date)" | tee -a "${LOG_FILE}"
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

assemble_and_map_metagenomes "${SRR_ACC}" "${ERZ_ACC}"
RESULT=$?

# Deactivate environment
conda deactivate 2>/dev/null

exit ${RESULT}
