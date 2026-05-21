#!/bin/bash
###############################################################################
# BATCH MANAGER - Orchestrates workflow for batch processing
#
# Modes:
#   Batch mode:       ./batch_manager.sh <batch_number> [--retry]
#   Accessions mode:  ./batch_manager.sh --accessions <file_or_list>
#
# Examples:
#   ./batch_manager.sh 1                         # Run batch 1 (samples 1-200)
#   ./batch_manager.sh 1 --retry                 # Retry failed samples from batch 1
#   ./batch_manager.sh --accessions my_list.txt  # Run specific accessions from file
#   ./batch_manager.sh --accessions ERZ001,ERZ002 # Run specific accessions inline
#
# Submits 1.0-metagenome_pipeline.sh as a single SLURM array job, which runs
# all steps (download → preprocess → assemble+map → cleanup) sequentially
# per sample.
###############################################################################

###############################################################################
# 1. Set environment``
###############################################################################


set -euo pipefail

source /home/epereira/workspace/dev/ocean-metagenomes/conf.sh

throttle=10  # Max concurrent tasks for SLURM array jobs (adjust based on cluster limits and resource requirements)

###############################################################################
# 2. Define the BATCH_START and BATCH_END associative arrays to specify line number ranges for each batch.
###############################################################################

# Define batch ranges (200 samples per batch)
declare -A BATCH_START=(
    [1]=1      [2]=201   [3]=401   [4]=601   [5]=801
    [6]=1001   [7]=1201 ["test"]=1
)

declare -A BATCH_END=(
    [1]=200    [2]=400   [3]=600   [4]=800   [5]=1000
    [6]=1200   [7]=1379 ["test"]=4
)

###############################################################################
# 3. Define functions for batch management, accession resolution, and SLURM job submission
###############################################################################

# Helper: Print usage
usage() {
    cat << EOF
Usage:
  $(basename "$0") <batch_number> [--retry]
  $(basename "$0") --accessions <file_or_list>

Submits 1.0-metagenome_pipeline.sh as a SLURM array job that runs all steps
(download → preprocess → assemble+map → cleanup) sequentially per sample.

Batch mode arguments:
  batch_number     Batch number (1-7) or "test" (samples 1-4)
  --retry          (Optional) Retry only failed samples from this batch

Accessions mode arguments:
  --accessions     File (one accession per line) or comma-separated list of
                   ERZ/SRR/DRR/ERR accessions to process.

Examples:
  $(basename "$0") 1                          # Run batch 1 (samples 1-200)
  $(basename "$0") 1 --retry                  # Retry failed samples from batch 1
  $(basename "$0") --accessions my_list.txt   # Run accessions from file
  $(basename "$0") --accessions ERZ001,ERZ002 # Run two accessions inline

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

# Helper: Resolve accessions to a comma-separated list of acc_map.tsv line numbers
# Input: file path (one accession per line) or comma-separated accession list
# Output (stdout): comma-separated line numbers ready for --array
# Returns 1 if no accessions could be resolved.
accessions_to_array_spec() {
    local source="$1"
    local -a lines=()
    local -a missing=()

    # Normalise input to a newline-separated stream
    local stream
    if [[ -f "${source}" ]]; then
        stream=$(grep -v '^\s*#' "${source}" | grep -v '^\s*$')
    else
        stream=$(echo "${source}" | tr ',' '\n')
    fi

    while IFS= read -r acc; do
        acc="${acc//[[:space:]]/}"
        [[ -z "${acc}" ]] && continue

        local line_num
        case "${acc}" in
            ERZ*) line_num=$(awk -F'\t' -v a="${acc}" '$1==a{print NR; exit}' "${RESOURCES}/acc_map.tsv") ;;
            *)    line_num=$(awk -F'\t' -v a="${acc}" '$2==a{print NR; exit}' "${RESOURCES}/acc_map.tsv") ;;
        esac

        if [[ -z "${line_num}" ]]; then
            missing+=("${acc}")
        else
            lines+=("${line_num}")
        fi
    done <<< "${stream}"

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "WARNING: ${#missing[@]} accession(s) not found in acc_map.tsv: ${missing[*]}" >&2
    fi

    [[ ${#lines[@]} -eq 0 ]] && return 1

    # Sort, deduplicate, and join
    printf '%s\n' "${lines[@]}" | sort -n | uniq | paste -sd ','
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
    [[ $# -lt 1 ]] && usage

    # ── Accessions mode ──────────────────────────────────────────────────────
    if [[ "$1" == "--accessions" ]]; then
        [[ $# -lt 2 ]] && { echo "ERROR: --accessions requires a file or accession list."; usage; }
        local acc_input="$2"

        local run_id="acc_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "${WORKSPACE}/logs/${run_id}"
        mkdir -p "${WORKSPACE}/logs/slurm_logs"
        local batch_log="${WORKSPACE}/logs/${run_id}/2.1-batch_manager_${run_id}.log"

        {
            echo "═══════════════════════════════════════════════════════════════════════════════"
            echo "BATCH MANAGER - Accessions mode"
            echo "═══════════════════════════════════════════════════════════════════════════════"
            echo "Started : $(date)"
            echo "Input   : ${acc_input}"
            echo ""

            echo "Resolving accessions to line numbers in acc_map.tsv..."
            local array_spec
            if ! array_spec=$(accessions_to_array_spec "${acc_input}"); then
                echo "ERROR: No valid accessions could be resolved from '${acc_input}'. Aborting."
                exit 1
            fi

            local n_samples
            n_samples=$(echo "${array_spec}" | tr ',' '\n' | wc -l)
            echo "Resolved : ${n_samples} sample(s)"
            echo "Array    : ${array_spec}"
            echo ""

            echo "PIPELINE: download → preprocess → assemble+map → cleanup"
            echo "────────────────────────────────────────────────────────────────────────────────"
            if ! submit_and_wait "${SCRIPTS}/1.0-metagenome_pipeline.sh" "${array_spec}" "${throttle}" "Full pipeline (1.0)"; then
                echo "Pipeline failed for one or more samples."
            fi
            echo ""

            echo "═══════════════════════════════════════════════════════════════════════════════"
            echo "Completed: $(date)"
            echo "═══════════════════════════════════════════════════════════════════════════════"
        } | tee "${batch_log}"

        return
    fi

    # ── Batch number mode ───────────────────────────────
    local batch=$1
    local retry=${2:-}
    validate_batch "${batch}"

    local start=${BATCH_START[$batch]}
    local end=${BATCH_END[$batch]}
    local array_spec="${start}-${end}"

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

        if [[ -n "${retry}" && "${retry}" == "--retry" ]]; then
            echo "RETRY MODE: Extracting failed samples from previous run..."
            local failed_samples=$(get_failed_samples "${batch}")
            if [[ -z "${failed_samples}" ]]; then
                echo "No failed samples found. Batch completed successfully!"
                return 0
            fi

            array_spec="$(echo "${failed_samples}" | tr '\n' ',' | sed 's/,$//')"
            echo "Failed samples (line numbers): ${array_spec}"
            echo ""
        fi

        echo "PIPELINE: download → preprocess → assemble+map → cleanup"
        echo "────────────────────────────────────────────────────────────────────────────────"
        if ! submit_and_wait "${SCRIPTS}/1.0-metagenome_pipeline.sh" "${array_spec}" "${throttle}" "Full pipeline (1.0)"; then
            echo "Pipeline failed for one or more samples."
        fi
        echo ""

        echo "Running status check..."
        "${SCRIPTS}/2.2-check_batch_status.sh" "${batch}" 2>&1
        echo ""

        echo "═══════════════════════════════════════════════════════════════════════════════"
        echo "Completed: $(date)"
        echo "═══════════════════════════════════════════════════════════════════════════════"

    } | tee "${batch_log}"
}

###############################################################################
# 4. Execute main
###############################################################################

main "$@"
