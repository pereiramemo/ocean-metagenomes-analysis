#!/bin/bash
###############################################################################
# BATCH MANAGER - Orchestrates workflow for batch processing
# Usage: ./batch_manager.sh <batch_number> [--retry]
# Example: ./batch_manager.sh 1          # Run batch 1 (samples 1-200)
#          ./batch_manager.sh 1 --retry  # Retry only failed samples from batch 1
#
# Submits 1.0-metagenome_pipeline.sh as a single SLURM array job, which runs
# all steps (download → preprocess → assemble+map → cleanup) sequentially
# per sample.
###############################################################################

set -euo pipefail

source /home/epereira/workspace/dev/ocean-metagenomes/conf.sh

# Define batch ranges (200 samples per batch)
declare -A BATCH_START=(
    [1]=1      [2]=201   [3]=401   [4]=601   [5]=801
    [6]=1001   [7]=1201 ["test"]=1
)

declare -A BATCH_END=(
    [1]=200    [2]=400   [3]=600   [4]=800   [5]=1000
    [6]=1200   [7]=1379 ["test"]=4
)

# Helper: Print usage
usage() {
    cat << EOF
Usage: $(basename "$0") <batch_number> [--retry]

Submits 1.0-metagenome_pipeline.sh as a SLURM array job that runs all steps
(download → preprocess → assemble+map → cleanup) sequentially per sample.

Arguments:
  batch_number     Batch number (1-7) or "test" (samples 1-4)
  --retry         (Optional) Retry only failed samples from this batch

Examples:
  $(basename "$0") 1              # Run batch 1 (samples 1-200)
  $(basename "$0") 1 --retry      # Retry failed samples from batch 1

Batch definitions:
  Batch 1:  samples 1-200
  Batch 2:  samples 201-400
  Batch 3:  samples 401-600
  Batch 4:  samples 601-800
  Batch 5:  samples 801-1000
  Batch 6:  samples 1001-1200
  Batch 7:  samples 1201-1379

EOF
    exit 1
}

# Helper: Validate batch number
validate_batch() {
    if [[ ! -v BATCH_START[$1] ]]; then
        echo "ERROR: Invalid batch number '$1'. Must be 1-7 or 'test'."
        exit 1
    fi
}

# Helper: Get failed samples from previous run
get_failed_samples() {
    local batch=$1
    local status_file="${WORKSPACE}/logs/batch_${batch}/status.txt"

    if [[ ! -f "${status_file}" ]]; then
        echo "ERROR: Status file not found: ${status_file}"
        echo "Please run the batch first without --retry"
        return 1
    fi

    grep "FAILED" "${status_file}" | awk '{print $2}' | sort -u
}

# Helper: Submit SLURM job and wait for completion
submit_and_wait() {
    local script=$1
    local array_spec=$2
    local throttle=${3:-}
    local task_name=${4:-}

    [[ -n "${throttle}" ]] && array_spec="${array_spec}%${throttle}"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Submitting: ${task_name}"
    echo "Array spec: ${array_spec}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Create temp script with modified array spec
    local temp_script=$(mktemp)
    sed "s/#SBATCH --array=.*/#SBATCH --array=${array_spec}/" "${script}" > "${temp_script}"

    # Submit job
    local job_id=$(sbatch "${temp_script}" | awk '{print $NF}')
    rm -f "${temp_script}"

    echo "Job ID: ${job_id}"

    # Wait for job completion
    echo "Waiting for completion..."
    while true; do
        # Check if job still exists
        if ! squeue -j "${job_id}" &>/dev/null; then
            # Job completed, check exit status
            local status=$(sacct -j "${job_id}" --format=State --noheader | head -1 | xargs)
            if [[ "${status}" == "COMPLETED" ]]; then
                echo "✓ ${task_name} completed successfully"
                break
            else
                echo "✗ ${task_name} failed with status: ${status}"
                return 1
            fi
        fi
        sleep 60
    done

    return 0
}

# Main workflow
main() {
    # Validate inputs
    [[ $# -lt 1 ]] && usage

    local batch=$1
    local retry=${2:-}
    validate_batch "${batch}"

    local start=${BATCH_START[$batch]}
    local end=${BATCH_END[$batch]}
    local array_spec="${start}-${end}"

    # Create logs directory
    mkdir -p "${WORKSPACE}/logs/batch_${batch}"
    mkdir -p "${WORKSPACE}/logs/slurm_logs"

    local batch_log="${WORKSPACE}/logs/batch_${batch}/2.1-batch_manager_$(date +%Y%m%d_%H%M%S).log"

    {
        echo "═══════════════════════════════════════════════════════════════════════════════"
        echo "BATCH MANAGER - Batch ${batch}"
        echo "═══════════════════════════════════════════════════════════════════════════════"
        echo "Started: $(date)"
        echo "Samples: ${start} - ${end}"
        echo "Total samples: $((end - start + 1))"
        echo ""

        # If retry mode, get failed samples
        if [[ -n "${retry}" && "${retry}" == "--retry" ]]; then
            echo "RETRY MODE: Extracting failed samples from previous run..."
            local failed_samples=$(get_failed_samples "${batch}")
            if [[ -z "${failed_samples}" ]]; then
                echo "No failed samples found. Batch completed successfully!"
                return 0
            fi

            # Convert to SLURM array format (array of line numbers)
            array_spec="$(echo "${failed_samples}" | tr '\n' ',' | sed 's/,$//')"
            echo "Failed samples (line numbers): ${array_spec}"
            echo ""
        fi

        # Full pipeline: download → preprocess → assemble+map → cleanup
        echo "PIPELINE: download → preprocess → assemble+map → cleanup"
        echo "────────────────────────────────────────────────────────────────────────────────"
        if ! submit_and_wait "${SCRIPTS}/1.0-metagenome_pipeline.sh" "${array_spec}" "20" "Full pipeline (1.0)"; then
            echo "Pipeline failed for one or more samples."
        fi
        echo ""

        # Status check
        echo "Running status check..."
        "${SCRIPTS}/2.2-check_batch_status.sh" "${batch}" 2>&1
        echo ""

        echo "═══════════════════════════════════════════════════════════════════════════════"
        echo "Completed: $(date)"
        echo "═══════════════════════════════════════════════════════════════════════════════"

    } | tee "${batch_log}"
}

main "$@"
