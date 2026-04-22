#!/bin/bash
###############################################################################
# BATCH DASHBOARD - View status of all batches
# Usage: ./batch_dashboard.sh [--watch]
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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

get_accession() {
    local line=$1
    sed -n "${line}p" "${RESOURCES}/acc_map.tsv" 2>/dev/null | cut -f2 || echo ""
}

check_sample_stages() {
    local SRR_ACC=$1

    local d1_ok=0 d2_ok=0 d3_ok=0

    local d1_log="${DATA}/raw/${SRR_ACC}.log"
    [[ -f "${d1_log}" ]] && grep -q "^SUCCESS:" "${d1_log}" && grep -q "^VALIDATION SUCCESS:" "${d1_log}" && d1_ok=1

    local d2_log="${DATA}/preprocessed/${SRR_ACC}.log"
    [[ -f "${d2_log}" ]] && grep -q "^SUCCESS:" "${d2_log}" && d2_ok=1

    local d3_log="${DATA}/mapped/${SRR_ACC}.log"
    [[ -f "${d3_log}" ]] && grep -q "^SUCCESS:" "${d3_log}" && d3_ok=1

    echo "${d1_ok} ${d2_ok} ${d3_ok}"
}

get_batch_status() {
    local batch=$1
    local start=${BATCH_START[$batch]}
    local end=${BATCH_END[$batch]}
    local total=$((end - start + 1))

    local completed=0 failed=0 in_progress=0

    for line in $(seq ${start} ${end}); do
        local acc=$(get_accession "${line}")
        [[ -z "${acc}" ]] && continue

        local stages=$(check_sample_stages "${acc}")
        read d1 d2 d3 <<< "${stages}"

        if [[ $d1 -eq 1 && $d2 -eq 1 && $d3 -eq 1 ]]; then
            ((completed++))
        elif [[ $d1 -eq 1 || $d2 -eq 1 || $d3 -eq 1 ]]; then
            ((in_progress++))
        else
            ((failed++))
        fi
    done

    echo "${completed} ${in_progress} ${failed}"
}

print_progress_bar() {
    local completed=$1
    local total=$2
    local width=20

    local pct=$((completed * 100 / total))
    local filled=$((pct * width / 100))
    local empty=$((width - filled))

    # Color based on percentage
    if [[ ${pct} -eq 100 ]]; then
        printf "${GREEN}"
    elif [[ ${pct} -ge 75 ]]; then
        printf "${BLUE}"
    elif [[ ${pct} -ge 50 ]]; then
        printf "${YELLOW}"
    else
        printf "${RED}"
    fi

    printf "["
    printf '%*s' "${filled}" | tr ' ' '='
    printf '%*s' "${empty}" | tr ' ' '-'
    printf "] %3d%%${NC}" "${pct}"
}

display_dashboard() {
    clear
    echo "╔════════════════════════════════════════════════════════════════════════════════╗"
    echo "║                           BATCH PROCESSING DASHBOARD                           ║"
    echo "║                             Updated: $(date '+%Y-%m-%d %H:%M:%S')                             ║"
    echo "╚════════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    local total_completed=0
    local total_in_progress=0
    local total_failed=0
    local grand_total=0

    for batch in {1..7}; do
        local start=${BATCH_START[$batch]}
        local end=${BATCH_END[$batch]}
        local batch_total=$((end - start + 1))
        ((grand_total += batch_total))

        local batch_status=$(get_batch_status "${batch}")
        read completed in_progress failed <<< "${batch_status}"

        ((total_completed += completed))
        ((total_in_progress += in_progress))
        ((total_failed += failed))

        # Format batch line
        printf "  Batch %2d [%4d..%4d] %5d samples  " "${batch}" "${start}" "${end}" "${batch_total}"
        print_progress_bar "${completed}" "${batch_total}"
        printf "  ${GREEN}%3d${NC}/${YELLOW}%3d${NC}/${RED}%3d${NC}\n" "${completed}" "${in_progress}" "${failed}"
    done

    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════════╗"
    printf "║  TOTAL: %d samples  " "${grand_total}"
    print_progress_bar "${total_completed}" "${grand_total}"
    printf "  ${GREEN}%4d${NC}/${YELLOW}%4d${NC}/${RED}%4d${NC}  ║\n" "${total_completed}" "${total_in_progress}" "${total_failed}"
    echo "╚════════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Legend: ${GREEN}✓${NC} = Completed  •  ${YELLOW}→${NC} = In Progress  •  ${RED}✗${NC} = Failed"
    echo ""
    echo "To run a batch:         ./batch_manager.sh <batch_number>"
    echo "To retry failed:        ./batch_manager.sh <batch_number> --retry"
    echo "To check batch status:  ./check_batch_status.sh <batch_number>"
    echo ""
}

main() {
    local watch=${1:-}

    if [[ "${watch}" == "--watch" ]]; then
        while true; do
            display_dashboard
            echo "Updating in 60 seconds... (Press Ctrl+C to stop)"
            sleep 60
        done
    else
        display_dashboard
    fi
}

main "$@"
