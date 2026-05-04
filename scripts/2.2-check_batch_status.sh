#!/bin/bash
###############################################################################
# CHECK BATCH STATUS - Analyzes logs to identify failed samples
# Usage: ./check_batch_status.sh <batch_number>
###############################################################################

set -euo pipefail

source /home/epereira/workspace/dev/ocean-metagenomes/conf.sh

# Define batch ranges
declare -A BATCH_START=(
    [1]=1      [2]=201   [3]=401   [4]=601   [5]=801
    [6]=1001   [7]=1201 ["test"]=1
)

declare -A BATCH_END=(
    [1]=200    [2]=400   [3]=600   [4]=800   [5]=1000
    [6]=1200   [7]=1379 ["test"]=4
)

usage() {
    echo "Usage: $(basename "$0") <batch_number>"
    echo ""
    echo "Analyzes SLURM logs to check batch completion status."
    exit 1
}

# Get accession from line number
get_accession() {
    local line=$1
    sed -n "${line}p" "${RESOURCES}/acc_map.tsv" | cut -f2
}

# Check if sample completed each stage
check_sample_stages() {
    local SRR_ACC=$1

    local d1_ok=0 d2_ok=0 d3_ok=0

    local d1_log="${DATA}/raw/${SRR_ACC}.log"
    local d1_del_log="${DATA}/raw/${SRR_ACC}/${SRR_ACC}_deleted.log"
    [[ -f "${d1_log}" ]] && grep -q "^SUCCESS:" "${d1_log}" && grep -q "^VALIDATION SUCCESS:" "${d1_log}" && \
    [[ -f "${d1_del_log}" ]] && grep -q "^SUCCESS:" "${d1_del_log}" && d1_ok=1

    local d2_log="${DATA}/preprocessed/${SRR_ACC}.log"
    local d2_del_log="${DATA}/preprocessed/${SRR_ACC}/${SRR_ACC}_deleted.log"
    [[ -f "${d2_log}" ]] && grep -q "^SUCCESS:" "${d2_log}" && \
    [[ -f "${d2_del_log}" ]] && grep -q "^SUCCESS:" "${d2_del_log}" && d2_ok=1

    local d3_log="${DATA}/mapped/${SRR_ACC}.log"
    [[ -f "${d3_log}" ]] && grep -q "^SUCCESS:" "${d3_log}" && d3_ok=1

    echo "${d1_ok} ${d2_ok} ${d3_ok}"
}

# Main
main() {
    [[ $# -lt 1 ]] && usage

    local batch=$1

    # Validate batch
    if [[ ! -v BATCH_START[$batch] ]]; then
        echo "ERROR: Invalid batch number '$batch'. Must be 1-7 or 'test'."
        exit 1
    fi

    local start=${BATCH_START[$batch]}
    local end=${BATCH_END[$batch]}
    local total=$((end - start + 1))

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "BATCH ${batch} STATUS REPORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Samples: ${start} - ${end} (Total: ${total})"
    echo "Generated: $(date)"
    echo ""

    # Create status file
    local status_file="${WORKSPACE}/logs/batch_${batch}/status.txt"
    local details_file="${WORKSPACE}/logs/batch_${batch}/details.csv"

    # Clear previous status  files
    > "${status_file}"
    > "${details_file}"

    # Write CSV header
    echo "Line,Accession,Stage1_Download,Stage2_Preprocess,Stage3_Assembly,Status" >> "${details_file}"

    local completed=0 failed=0
    local failed_samples=()

    for line in $(seq ${start} ${end}); do
        local acc=$(get_accession "${line}")
        
        if [[ -z "${acc}" ]]; then
            echo "WARN Line ${line}: No accession found"
            echo "FAILED ${line} no_accession_found" >> "${status_file}"
            continue
        fi

        local stages=$(check_sample_stages "${acc}")
        read d1 d2 d3 <<< "${stages}"

        if [[ $d1 -eq 1 && $d2 -eq 1 && $d3 -eq 1 ]]; then
            echo "OK ${line} ${acc}" >> "${status_file}"
            echo "${line},${acc},✓,✓,✓,OK" >> "${details_file}"
            completed=$((completed + 1))
        else
            echo "FAILED ${line} ${acc}" >> "${status_file}"
            d1_mark=$([ $d1 -eq 1 ] && echo "✓" || echo "✗")
            d2_mark=$([ $d2 -eq 1 ] && echo "✓" || echo "✗")
            d3_mark=$([ $d3 -eq 1 ] && echo "✓" || echo "✗")
            echo "${line},${acc},${d1_mark},${d2_mark},${d3_mark},FAILED" >> "${details_file}"
            failed=$((failed + 1))
            failed_samples+=("${line}")
        fi
    done

    # Print summary
    echo "┌─ SUMMARY ──────────────────────────────────────────────────────────┐"
    echo "│ Total samples:   ${total}"
    echo "│ Completed:       ${completed} ($(( (completed * 100) / total ))%)"
    echo "│ Failed:          ${failed} ($(( (failed * 100) / total ))%)"
    echo "└────────────────────────────────────────────────────────────────────┘"
    echo ""

    if [[ ${failed} -gt 0 ]]; then
        echo "Failed samples (line numbers):"
        printf '  %s\n' "${failed_samples[@]}"
        echo ""
        echo "To retry failed samples, run:"
        echo "  ./batch_manager.sh ${batch} --retry"
        echo ""

        # Write failed samples to a file for easy CSV import
        local failed_file="${WORKSPACE}/logs/batch_${batch}_failed.txt"
        printf '%s\n' "${failed_samples[@]}" > "${failed_file}"
        echo "Failed samples list saved to: ${failed_file}"
    else
        echo "✓ All samples completed successfully!"
    fi

    echo ""
    echo "Detailed report:"
    echo "  CSV: ${details_file}"
    echo "  Status: ${status_file}"
    echo ""

}

main "$@"
