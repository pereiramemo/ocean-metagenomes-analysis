#!/bin/bash
# List compute-* nodes with all CPUs idle (Allocated=0, Other=0)
# Output format: NODENAME CPUS(A/I/O/T) MEMORY_MB

sinfo -o "%n %C %m" --noheader | awk '
/^compute-/ {
    node = $1
    cpus = $2   # A/I/O/T
    mem  = $3
    split(cpus, c, "/")
    allocated = c[1] + 0
    other     = c[3] + 0
    if (allocated == 0 && other == 0)
        printf "%-20s  %-14s  %s MB\n", node, cpus, mem
}
'
