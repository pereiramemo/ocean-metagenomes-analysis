#!/bin/bash
###############################################################################
# METAGENOME PROCESSING PIPELINE ORCHESTRATOR
#
# Runs steps 1.1 → 1.2 → 1.3 → 1.4 sequentially for each SLURM array task.
# Each step script also works standalone; it accepts the accession as $1 and
# falls back to SLURM_ARRAY_TASK_ID lookup when called without arguments.
#
# Usage (SLURM):  sbatch 1.0-metagenome_pipeline.sh
# Usage (local):  bash  1.0-metagenome_pipeline.sh   # needs SLURM env vars
###############################################################################
#SBATCH --job-name=metagenome_pipeline
#SBATCH --output=/home/epereira/workspace/dev/ocean-metagenomes/logs/slurm_logs/%x_%A_%a.out
#SBATCH --error=/home/epereira/workspace/dev/ocean-metagenomes/logs/slurm_logs/%x_%A_%a.err
#SBATCH --time=120:00:00            # budget: 48h download + 48h preprocess + 24h assemble
#SBATCH --ntasks=1
#SBATCH --distribution=block
#SBATCH --cpus-per-task=4           # max across all steps
#SBATCH --mem=24G                   # max across all steps (step 1.3)
#SBATCH --array=1-10                # change to match number of lines in acc_map.tsv
                                    # use 1-N%K to throttle concurrent tasks (e.g. 1-50%10)

###############################################################################
# ENVIRONMENT AND INITIAL SETUP
###############################################################################

source /home/epereira/workspace/dev/ocean-metagenomes/conf.sh
set -o pipefail

# Ensure log directory exists
mkdir -p "$(dirname "${WORKSPACE}/logs/slurm_logs/placeholder")"

###############################################################################
# SELECT ACCESSION FOR THIS ARRAY TASK
###############################################################################

LINE_NUM="${SLURM_ARRAY_TASK_ID}"

ERZ_ACC=$(sed -n "${LINE_NUM}p" "${RESOURCES}/acc_map.tsv" | cut -f1)
SRR_ACC=$(sed -n "${LINE_NUM}p" "${RESOURCES}/acc_map.tsv" | cut -f2)

if [[ -z "${SRR_ACC}" ]]; then
    echo "ERROR: No SRR accession found for line ${LINE_NUM} (task ${SLURM_ARRAY_TASK_ID})"
    exit 1
fi

if [[ -z "${ERZ_ACC}" ]]; then
    echo "ERROR: No ERZ accession found for line ${LINE_NUM} (task ${SLURM_ARRAY_TASK_ID})"
    exit 1
fi

export SRR_ACC ERZ_ACC

echo "============================================================"
echo "Pipeline started for ${SRR_ACC} (ERZ: ${ERZ_ACC})"
echo "Array task : ${SLURM_ARRAY_TASK_ID} | Job: ${SLURM_JOB_ID}"
echo "Node       : $(hostname)"
echo "Started    : $(date)"
echo "============================================================"

###############################################################################
# SKIP CHECK — all three steps must have succeeded to skip
###############################################################################

d1_log="${DATA}/raw/${SRR_ACC}.log"
d2_log="${DATA}/preprocessed/${SRR_ACC}.log"
d3_log="${DATA}/mapped/${SRR_ACC}.log"

if [[ -f "${d1_log}" ]] && grep -q "^VALIDATION SUCCESS:" "${d1_log}" && grep -q "^SUCCESS:" "${d1_log}" && \
   [[ -f "${d2_log}" ]] && grep -q "^SUCCESS:" "${d2_log}" && \
   [[ -f "${d3_log}" ]] && grep -q "^SUCCESS:" "${d3_log}"; then
    echo "SKIPPED: ${SRR_ACC} all pipeline steps completed successfully"
    exit 0
fi

###############################################################################
# PIPELINE STEPS (sequential)
###############################################################################

bash "${SCRIPTS}/1.1-download_metagenomes.sh" "${SRR_ACC}"         || { echo "ERROR: Step 1.1 failed for ${SRR_ACC}"; exit 1; }
bash "${SCRIPTS}/1.2-preprocess_metagenomes.sh" "${SRR_ACC}"       || { echo "ERROR: Step 1.2 failed for ${SRR_ACC}"; exit 1; }
bash "${SCRIPTS}/1.3-assemble_and_map_metagenomes.sh" "${SRR_ACC}" "${ERZ_ACC}" || { echo "ERROR: Step 1.3 failed for ${SRR_ACC}"; exit 1; }
bash "${SCRIPTS}/1.4-cleanup_fastq.sh" "${SRR_ACC}"                || { echo "ERROR: Step 1.4 failed for ${SRR_ACC}"; exit 1; }

###############################################################################
# DONE
###############################################################################

echo ""
echo "============================================================"
echo "Pipeline COMPLETE for ${SRR_ACC} (ERZ: ${ERZ_ACC})"
echo "Finished: $(date)"
echo "============================================================"
