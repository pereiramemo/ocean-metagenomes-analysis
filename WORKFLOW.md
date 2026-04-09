# Ocean Metagenomic Analysis Workflow

## Architectural Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    OCEAN METAGENOMIC ANALYSIS WORKFLOW                      │
│                    1,379 samples · 13 batches · SLURM HPC                   │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│ STAGE 0: PRE-PROCESSING UTILITIES (run once before main pipeline)            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              |
│  0.1-check_contigs_gz.sh          0.2-download_assemblies.sh                 │
│  ├─ SLURM array (1-2114%25)       ├─ SLURM array (1-226%5)                   │
│  ├─ gzip -tv on each .fasta.gz    ├─ Queries ENA filereport API              │
│  └─ Logs integrity per file       ├─ Downloads via FTP to data/inbox/        │
│                                   └─ Names output as ERZ.fasta.gz            │
│                                                                              │
│  0.3-check_md5_sequences.sh                                                  │
│  ├─ SLURM array (1-225%20)                                                   │
│  ├─ Compares first N sequences between data/inbox/ and data/assemblies/      │
│  └─ MD5 match → [OK] · mismatch → exit 1                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────────┐
│ BATCH SUBMISSION: 2.1-batch_manager.sh <batch> [--retry]                     │
├──────────────────────────────────────────────────────────────────────────────┤
│  ├─ Validates batch number (1-13 or "test")                                  │
│  ├─ Patches --array in 1.0 via sed on a temp script                          │
│  ├─ Submits sbatch, waits for completion (squeue + sacct polling)            │
│  ├─ Runs 2.2-check_batch_status.sh automatically after job finishes          │
│  └─ --retry mode: re-submits only FAILED line numbers from status.txt        │
└──────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────────┐
│ STAGE 1: MAIN PIPELINE ORCHESTRATOR                                          │
│ 1.0-metagenome_pipeline.sh  (SLURM array task — one task = one sample)       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  SLURM directives (owned exclusively by 1.0):                                │
│  ├─ --account=inali  --partition=principal                                   │
│  ├─ --ntasks=1  --nodes=1  --cpus-per-task=4  --mem=24G                      │
│  ├─ --time=120:00:00                                                         │
│  └─ --array patched by 2.1-batch_manager.sh (e.g. 1-200%20)                  │
│                                                                              │
│  Per task:                                                                   │
│  ├─ Reads SRR_ACC and ERZ_ACC from resources/acc_map.tsv[SLURM_ARRAY_TASK_ID]│
│  └─ Calls steps sequentially with exit-code guards (|| exit 1)               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
          │              │               │               │
          ↓              ↓               ↓               ↓
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ STEP 1.1     │ │ STEP 1.2     │ │ STEP 1.3     │ │ STEP 1.4     │
│ Download     │→│ Preprocess   │→│ Assemble &   │→│ Cleanup      │
│              │ │              │ │ Map          │ │ FASTQ        │
└──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘
```

---

## Step-by-Step Detail

### Step 1.1 — Download (`1.1-download_metagenomes.sh`)

**Input:** SRR accession (from orchestrator `$1` or `SLURM_ARRAY_TASK_ID` fallback)
**Output:** `data/raw/<SRR>/` with FASTQ.gz files; `data/raw/<SRR>.log`

**Logic:**
- Checks `data/raw/<SRR>.log` for `SUCCESS:` and `VALIDATION SUCCESS:` tags — skips if both present
- Removes partial output directory before retrying
- Calls `kingfisher get` with methods: `aws-http ena-ascp ena-ftp aws-cp prefetch`
- Up to 10 retry attempts (360s sleep between failures, 60s on validation failure)
- Validates: directory exists, FASTQ files present, each file ≥ 1 KB

**Environment:** activates `ocean-metagenomes-env` conda environment

---

### Step 1.2 — Preprocess (`1.2-preprocess_metagenomes.sh`)

**Input:** `data/raw/<SRR>/` FASTQ files
**Output:** `data/preprocessed/<SRR>/` with QC'd reads; `data/preprocessed/<SRR>.log`

**Processing:**
1. Quality assessment (fastp)
2. Adapter trimming (BBDuk)
3. Paired-end merging (PEAR or BBMerge)
4. Quality filtering and length trimming
5. Stats summary (`stats.tsv`)

---

### Step 1.3 — Assemble & Map (`1.3-assemble_and_map_metagenomes.sh`)

**Input:** `data/preprocessed/<SRR>/`, pre-existing assembly from `data/assemblies/<ERZ>*.fasta.gz`
**Output:** `data/mapped/<SRR>/` with sorted BAM + index; `data/mapped/<SRR>.log`

**Logic:**
- Checks `data/mapped/<SRR>.log` for `SUCCESS:` tag — skips if present
- Uses pre-existing ERZ assembly if available; otherwise runs MEGAHIT de novo assembly
- BWA-MEM alignment with quality filter (q ≥ 10, primary alignments only)
- SAM → BAM → sorted BAM → index
- Optional PCR duplicate removal (Picard)
- Cleanup of intermediate SAM files and BWA indices

---

### Step 1.4 — Cleanup (`1.4-cleanup_fastq.sh`)

**Input:** `data/raw/<SRR>/` and `data/preprocessed/<SRR>/`
**Output:** FASTQ files deleted; MD5 checksums written to deleted-file logs

**Logic:**
- Skips if both `<SRR>_deleted.log` files already contain `SUCCESS:` tag
- Computes MD5 of each FASTQ before deleting (audit trail)
- Keeps log files and `stats.tsv`; removes only `*.fastq`, `*.fastq.gz`, `*.fq`, `*.fq.gz`

---

## Skip / Retry Logic

Every step is idempotent — re-running a completed step is safe:

| Step | Skip condition |
|------|---------------|
| 1.1 | `SUCCESS:` AND `VALIDATION SUCCESS:` in `data/raw/<SRR>.log` |
| 1.2 | `SUCCESS:` in `data/preprocessed/<SRR>.log` |
| 1.3 | `SUCCESS:` in `data/mapped/<SRR>.log` |
| 1.4 | `SUCCESS:` in both deleted-file logs |

**Retry workflow:**
```bash
bash scripts/2.2-check_batch_status.sh 1        # generates logs/batch_1/status.txt
bash scripts/2.1-batch_manager.sh 1 --retry     # re-submits only FAILED line numbers
```

---

## Batch Management

### 2.1-batch_manager.sh

Orchestrates a full batch run:
1. Patches `--array` spec into `1.0-metagenome_pipeline.sh` via `sed` on a temp script
2. Submits via `sbatch`; polls `squeue`/`sacct` until completion
3. Automatically runs `2.2-check_batch_status.sh` after job finishes
4. Logs everything to `logs/batch_<N>/2.1-batch_manager_<timestamp>.log`

**Throttle:** `%20` concurrent tasks → 20 × 4 CPUs = 80 CPUs max (≈ 4 nodes at 20 CPUs each). Adjust to control how many nodes are used simultaneously.

### 2.2-check_batch_status.sh

Inspects output directories and log files for each sample in a batch:
- **Download OK:** `data/raw/<SRR>.log` has `SUCCESS:` OR FASTQ files present
- **Preprocess OK:** `data/preprocessed/<SRR>.log` has `SUCCESS:` OR FASTQ files present
- **Assembly OK:** `data/mapped/<SRR>.log` has `SUCCESS:` OR BAM files present

Writes:
- `logs/batch_<N>/status.txt` — `OK`/`FAILED` per line number (used by `--retry`)
- `logs/batch_<N>/details.csv` — per-sample stage breakdown

### 2.3-batch_dashboard.sh

Color-coded terminal dashboard showing progress across all 13 batches:
- Green = completed, Yellow = in progress, Red = not started/failed
- `--watch` flag auto-refreshes every 60 seconds

---

## SLURM Node Strategy

- **`--nodes=1`**: each array task is pinned to a single node
- SLURM bin-packs by default: fills one node before spilling to the next
- With `%20` throttle: 20 concurrent tasks × 4 CPUs = 80 CPUs → typically 4 nodes at full capacity
- Reduce throttle (e.g. `%10`) to concentrate onto fewer nodes

---

## Data Flow Summary

```
resources/acc_map.tsv
(ERZ_ACC  SRR_ACC)
        │
        ├─ ERZ_ACC ──→ data/assemblies/<ERZ>*.fasta.gz  (pre-existing contigs)
        │
        └─ SRR_ACC ──→ [1.1 Download]
                              │
                        data/raw/<SRR>/
                              │
                       [1.2 Preprocess]
                              │
                   data/preprocessed/<SRR>/
                              │
                    [1.3 Assemble & Map]
                       ├── MEGAHIT (if no pre-existing assembly)
                       └── BWA-MEM + SAMtools
                              │
                       data/mapped/<SRR>/
                       ├── <SRR>_sorted.bam
                       └── <SRR>_sorted.bam.bai
                              │
                        [1.4 Cleanup]
                              │
                   raw + preprocessed FASTQ deleted
                   (MD5 audit trail kept in logs)
```

---

## Project Structure

```
ocean-metagenomes/
├── conf.sh                              # Exports: WORKSPACE, DATA, SCRIPTS, RESOURCES, CONTIGS
├── scripts/
│   ├── 0.1-check_contigs_gz.sh          # Validate .fasta.gz integrity (SLURM array)
│   ├── 0.2-download_assemblies.sh       # Re-download assemblies from ENA (SLURM array)
│   ├── 0.3-check_md5_sequences.sh       # MD5 cross-check inbox vs assemblies (SLURM array)
│   ├── 1.0-metagenome_pipeline.sh       # Orchestrator — all SLURM headers live here
│   ├── 1.1-download_metagenomes.sh      # Download step (no SLURM headers)
│   ├── 1.2-preprocess_metagenomes.sh    # Preprocess step (no SLURM headers)
│   ├── 1.3-assemble_and_map_metagenomes.sh  # Assembly + mapping (no SLURM headers)
│   ├── 1.4-cleanup_fastq.sh             # FASTQ cleanup (no SLURM headers)
│   ├── 2.1-batch_manager.sh             # Batch submission and retry
│   ├── 2.2-check_batch_status.sh        # Batch status report
│   ├── 2.3-batch_dashboard.sh           # Multi-batch dashboard
│   └── toolbox/metagenomic_pipelines/
│       └── modules/
│           ├── 1.1-quality_check_fastp.sh
│           ├── 2-preprocess_pipeline.sh
│           └── environment.yml
├── data/
│   ├── raw/                             # Downloaded FASTQ (deleted after step 1.4)
│   ├── preprocessed/                    # QC'd reads (deleted after step 1.4)
│   ├── mapped/                          # Final BAM files (kept)
│   └── assemblies/                      # Pre-existing contig FASTA files
├── resources/
│   ├── acc_map.tsv                      # ERZ<TAB>SRR per line; line N = array task N
│   └── Notes.md
└── logs/
    ├── slurm_logs/                      # %x_%A_%a.out / .err per task
    └── batch_<N>/
        ├── 2.1-batch_manager_<ts>.log
        ├── status.txt                   # OK/FAILED per line number
        └── details.csv                  # Per-sample stage breakdown
```

---

## Key Dependencies

| Stage | Tools | Purpose |
|-------|-------|---------|
| 0.* | curl, wget, gzip | Assembly download and integrity checks |
| 1.1 | kingfisher | Multi-source FASTQ download with MD5 validation |
| 1.2 | fastp, BBTools, PEAR/BBMerge, seqtk, pigz | QC and read preprocessing |
| 1.3 | MEGAHIT, BWA, SAMtools, Picard | Assembly, mapping, BAM processing |
| 1.4 | md5sum, bash | FASTQ cleanup with audit trail |
| 2.* | sbatch, squeue, sacct | SLURM job management |

---

## Notes on Data

- 1,379 total samples from ocean metagenomes (ENA/SRA)
- 226 assemblies were re-downloaded due to gzip integrity failures (identified by `0.1`)
- Re-downloads validated against originals using MD5 on first N sequences (`0.3`)
- Accession `ERZ477576` not found in ENA but exists in local storage
- See `resources/Notes.md` for full processing history
