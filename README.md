# Ocean Metagenomes

A bioinformatics pipeline for processing, assembling, and analyzing ocean metagenomic sequences at scale on a SLURM HPC cluster.

## Overview

This project implements a multi-stage workflow for metagenomic analysis: download → quality control & preprocessing → de novo assembly → read mapping → cleanup. The pipeline processes 1,379 ocean metagenome samples from ENA/SRA, organized into 7 batches of 200 samples (except the last), and runs as SLURM array jobs with full retry and status monitoring capabilities.

## Quick Start

### Prerequisites
- Conda/Mamba installation
- SLURM job scheduling system
- Access to the `principal` partition (account: `inali`)

### Installation

```bash
conda env create -f scripts/toolbox/metagenomic_pipelines/environment.yml
conda activate ocean-metagenomes-env
```

### Running the Pipeline

```bash
# Run a batch (e.g. batch 1 = samples 1–200)
bash scripts/2.1-batch_manager.sh 1

# Retry only failed samples from a previous run
bash scripts/2.1-batch_manager.sh 1 --retry

# Monitor all batches
bash scripts/2.3-batch_dashboard.sh
bash scripts/2.3-batch_dashboard.sh --watch   # auto-refresh every 60s

# Check status of a specific batch
bash scripts/2.2-check_batch_status.sh 1
```

## Workflow Stages

### Stage 0: Pre-processing Utilities (0.*)
One-time utilities run before the main pipeline to prepare and validate assembly files.

| Script | Purpose |
|--------|---------|
| `0.1-check_contigs_gz.sh` | Validates gzip integrity of all assembly FASTA files (SLURM array) |
| `0.2-download_assemblies.sh` | Re-downloads incomplete/corrupt assemblies from ENA via FTP (SLURM array) |
| `0.3-check_md5_sequences.sh` | Compares first N sequences between inbox and assembly files via MD5 |

### Stage 1: Main Pipeline (1.*)

Orchestrated by `1.0-metagenome_pipeline.sh` as a single SLURM array job. Each array task runs all four steps sequentially for one sample.

| Script | Purpose |
|--------|---------|
| `1.0-metagenome_pipeline.sh` | **Orchestrator** — owns all SLURM directives, runs 1.1→1.2→1.3→1.4 |
| `1.1-download_metagenomes.sh` | Downloads raw FASTQ from ENA/SRA via kingfisher (10 retries, MD5 validation) |
| `1.2-preprocess_metagenomes.sh` | QC, adapter trimming, paired-end merging, quality filtering |
| `1.3-assemble_and_map_metagenomes.sh` | MEGAHIT assembly + BWA-MEM mapping → sorted/indexed BAM |
| `1.4-cleanup_fastq.sh` | Removes raw and preprocessed FASTQ files after successful assembly |

Steps 1.1–1.4 also work standalone: they accept the SRR accession as `$1`, or fall back to `SLURM_ARRAY_TASK_ID` for lookup from `resources/acc_map.tsv`.

### Stage 2: Batch Management (2.*)

| Script | Purpose |
|--------|---------|
| `2.1-batch_manager.sh` | Submits 1.0 as a SLURM array job, waits for completion, runs status check |
| `2.2-check_batch_status.sh` | Inspects logs and output directories; writes `status.txt` and `details.csv` |
| `2.3-batch_dashboard.sh` | Color-coded dashboard showing progress across all 7 batches |

## Directory Structure

```
ocean-metagenomes/
├── conf.sh                           # Environment variables (WORKSPACE, DATA, SCRIPTS, RESOURCES, CONTIGS)
├── scripts/
│   ├── 0.1-check_contigs_gz.sh       # Validate assembly gzip integrity
│   ├── 0.2-download_assemblies.sh    # Re-download incomplete assemblies
│   ├── 0.3-check_md5_sequences.sh    # MD5 validation of re-downloaded assemblies
│   ├── 1.0-metagenome_pipeline.sh    # SLURM orchestrator (download→preprocess→assemble→cleanup)
│   ├── 1.1-download_metagenomes.sh   # Download raw FASTQ
│   ├── 1.2-preprocess_metagenomes.sh # QC and preprocessing
│   ├── 1.3-assemble_and_map_metagenomes.sh  # Assembly + mapping
│   ├── 1.4-cleanup_fastq.sh          # Delete intermediate FASTQ files
│   ├── 2.1-batch_manager.sh          # Batch orchestration and retry logic
│   ├── 2.2-check_batch_status.sh     # Batch status report
│   ├── 2.3-batch_dashboard.sh        # Multi-batch progress dashboard
│   └── toolbox/metagenomic_pipelines/   # Core processing modules
│       └── modules/
│           ├── 1.1-quality_check_fastp.sh
│           ├── 2-preprocess_pipeline.sh
│           └── environment.yml
├── data/
│   ├── raw/                          # Downloaded FASTQ files (per-sample subdirectories)
│   ├── preprocessed/                 # QC'd reads (deleted after assembly)
│   ├── mapped/                       # Sorted BAM files + indices
│   └── assemblies/                   # Pre-existing assembly FASTA files
├── resources/
│   ├── acc_map.tsv                   # Accession map: ERZ_ACC<TAB>SRR_ACC (one per line)
│   └── Notes.md                      # Processing history and data notes
└── logs/
    ├── slurm_logs/                   # Per-task SLURM stdout/stderr
    └── batch_<N>/                    # Per-batch status.txt, details.csv, manager log
```

## SLURM Configuration

The orchestrator (`1.0-metagenome_pipeline.sh`) owns all SLURM directives:

```bash
#SBATCH --account=inali
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=120:00:00
#SBATCH --array=1-200%20    # set in 2.1-batch_manager.sh at submission time
```

- `--nodes=1`: ensures each task runs on a single node (SLURM bin-packs naturally)
- `%20` throttle: limits concurrent tasks; adjust to control node usage
- Subscripts 1.1–1.4 have **no SLURM headers** — they are called by the orchestrator

## Fault Tolerance and Retry Strategy

### Per-sample log files and SUCCESS tags

Each processing step writes a log file named `<SRR_ACC>.log` inside the step's output directory:

| Step | Log location |
|------|-------------|
| 1.1 Download | `data/raw/<SRR>.log` |
| 1.2 Preprocess | `data/preprocessed/<SRR>.log` |
| 1.3 Assemble & Map | `data/mapped/<SRR>.log` |

If the step completes without errors, the log ends with a `SUCCESS:` tag. On re-submission, each step checks for this tag first — if found, the step is skipped, making every step idempotent.

### Detecting and retrying failed samples

After a batch finishes, `2.2-check_batch_status.sh` scans the log files for each sample in the batch, looking for the `SUCCESS:` tag in each step's log. Samples missing any tag are marked `FAILED` and their line numbers are saved to `logs/batch_<N>/status.txt`.

To re-run only the failed samples:

```bash
bash scripts/2.1-batch_manager.sh <batch> --retry
```

This reads the `FAILED` line numbers from `status.txt` and re-submits them as a new SLURM array job. Completed samples are untouched because each step skips on `SUCCESS:`.

### FASTQ cleanup audit trail

After assembly (`1.3`) completes successfully, `1.4-cleanup_fastq.sh` deletes all raw and preprocessed FASTQ files to free disk space. Before deleting each file, it computes the **MD5 checksum of the uncompressed content** and writes it to a deletion log inside the sample directory:

- `data/raw/<SRR>/<SRR>_deleted.log` — MD5s and paths of removed raw FASTQ files
- `data/preprocessed/<SRR>/<SRR>_deleted.log` — MD5s and paths of removed preprocessed FASTQ files

These logs serve as a permanent audit trail: if data integrity ever needs to be verified, the original file content can be reconstructed and its MD5 compared against the recorded value. The cleanup step is also idempotent — it checks for a `SUCCESS:` tag in both logs before running.

## Batch Definitions

| Batch | Samples | Count |
|-------|---------|-------|
| 1 | 1–200 | 200 |
| 2 | 201–400 | 200 |
| 3 | 401–600 | 200 |
| 4 | 601–800 | 200 |
| 5 | 801–1000 | 200 |
| 6 | 1001–1200 | 200 |
| 7 | 1201–1379 | 179 |
| test | 1–4 | 4 |

## Skip / Retry Logic

Each step checks for a `SUCCESS:` tag in its log file before re-running:
- **Step 1.1**: skips if `SUCCESS:` and `VALIDATION SUCCESS:` found in `data/raw/<SRR>.log`
- **Step 1.3**: skips if `SUCCESS:` found in `data/mapped/<SRR>.log`
- **Step 1.4**: skips if `SUCCESS:` found in both deleted-file logs
- **Retry mode**: `2.1-batch_manager.sh <batch> --retry` re-submits only line numbers marked `FAILED` in `logs/batch_<N>/status.txt`

## Core Tools

| Stage | Tools |
|-------|-------|
| Download | kingfisher, aws-http, ena-ascp, ena-ftp |
| QC & Preprocessing | fastp, BBTools (BBDuk), PEAR/BBMerge, seqtk |
| Assembly | MEGAHIT |
| Mapping | BWA-MEM, SAMtools |
| Utilities | Picard, pigz, conda |

## License

GNU General Public License v3.0 — See LICENSE file for details.

Copyright (C) 2025 Emiliano Pereira
