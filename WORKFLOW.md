# Ocean Metagenomic Analysis Workflow

## Architectural Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    OCEAN METAGENOMIC ANALYSIS WORKFLOW                       │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│ STAGE 1: DATA ACQUISITION                                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  1.1-download_metagenomes.sh                                                  │
│  ├─ Downloads raw metagenomic sequences from ENA                             │
│  ├─ Retrieves assembly metadata (accession, sample info)                     │
│  └─ Validates file integrity (gzip -tv checks)                              │
│      └─> Output: Raw FASTQ/FASTA files                                       │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────────┐
│ STAGE 2: QUALITY CONTROL & ASSESSMENT                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  1.1-quality_check_fastp.sh                   1.2-quality_check.R            │
│  ├─ Fastp quality assessment                  ├─ Quality metrics analysis    │
│  ├─ HTML & JSON reports                       ├─ PhiX contamination detect   │
│  ├─ PhiX detection                            ├─ Read count distributions    │
│  └─ Adapter identification                    └─ Quality score plots         │
│      └─> fastp_reports/                           └─> QC_plots/             │
│          ├─ Sample_html_report/                       ├─ r1_mean_q_*.png    │
│          └─ Sample_json_report/                       ├─ r2_mean_q_*.png    │
│                                                       └─ phix_barplot.png    │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────────┐
│ STAGE 3: PREPROCESSING (1.2-preprocess_metagenomes.sh)                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  2-preprocess_pipeline.sh                                                     │
│  ├─ Adapter Trimming (BBDuk)                                                 │
│  │   └─> Trimmed reads (FASTQ)                                               │
│  │                                                                             │
│  ├─ Paired-End Merging (PEAR/BBMerge)                                        │
│  │   └─> Merged reads (FASTQ)                                                │
│  │   └─> Unmerged R1/R2 (FASTQ)                                              │
│  │                                                                             │
│  ├─ Quality Trimming (using trimmomatic params)                              │
│  │   └─> Quality-trimmed reads (FASTQ)                                       │
│  │                                                                             │
│  └─ Format Conversion (fq2fa.sh)                                             │
│      └─> Output: *workable.fasta file (main output)                          │
│          + stats.tsv (read statistics)                                       │
│          + stats_plots.png (visualization)                                   │
│                                                                                │
│  Input: Raw R1/R2 paired-end reads                                           │
│  Output: Quality-controlled FASTA for assembly                               │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────────┐
│ STAGE 4: ASSEMBLY & MAPPING (1.3-assemble_and_map_metagenomes.sh)            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  3-assembly_and_map_pipeline.sh                                              │
│  ├─ DE NOVO ASSEMBLY (or use pre-assembled contigs)                         │
│  │   ├─ MEGAHIT (meta-sensitive preset)                                     │
│  │   └─> Output: contigs.fa (≥250 bp minimum)                               │
│  │       Optional pre-assembled contigs input                                │
│  │                                                                             │
│  ├─ READ MAPPING                                                              │
│  │   ├─ BWA-MEM indexing                                                     │
│  │   ├─ Quality filtering (q≥10, primary alignments)                         │
│  │   └─> SAM → BAM conversion (direct, memory-efficient)                     │
│  │                                                                             │
│  ├─ BAM PROCESSING                                                            │
│  │   ├─ Sorting (SAMtools)                                                   │
│  │   ├─ Indexing (.bam.bai files)                                            │
│  │   └─ Optional duplicate removal (Picard)                                  │
│  │                                                                             │
│  └─ CLEANUP                                                                   │
│      └─> Remove intermediate files & BWA indices                             │
│                                                                                │
│  Input: *workable.fasta (preprocessed reads)                                │
│  Output: *_sorted.bam + *_sorted.bam.bai (final mapping)                   │
│          [or *_sorted_markdup.bam if PCR duplicates removed]                │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────────┐
│ STAGE 5: OUTPUTS & DATA PRODUCTS                                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  Assemblies:                  Mappings:              Diagnostics:            │
│  ├─ contigs.fa               ├─ sorted.bam          ├─ QC plots             │
│  └─ contigs_filtered.fa      ├─ sorted.bam.bai      ├─ statistics (TSV)     │
│                               └─ markdup.metrics     ├─ fastp reports        │
│                                  (if duplicates)    └─ preprocessing stats   │
│                                                                                │
│  Integration point: BAM files serve as input for:                           │
│  • Binning and taxonomic classification                                     │
│  • Gene prediction and functional annotation                                │
│  • Abundance estimation and profiling                                       │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Workflow Stages in Detail

### Stage 1: Data Acquisition
**Script:** `1.1-download_metagenomes.sh`

Downloads raw metagenomic sequences from the European Nucleotide Archive (ENA). This stage:
- Retrieves FASTQ/FASTA files using provided accession numbers
- Extracts metadata (sample information, collection date, location)
- Validates file integrity using gzip integrity checks
- Identifies incomplete or corrupted files for re-download

**Output:** Raw sequence files ready for quality assessment

---

### Stage 2: Quality Control & Assessment
**Scripts:**
- `1.1-quality_check_fastp.sh`
- `1.2-quality_check.R`

Comprehensive quality evaluation of raw sequences without modification:

**Fastp Analysis:**
- Generates HTML and JSON quality reports
- Detects and quantifies PhiX contamination
- Identifies adapter sequences
- Produces quality metrics per sample

**R-based Statistical Analysis:**
- Calculates mean quality scores (Q values) for R1 and R2 reads
- Generates quality vs. read count scatter plots
- Creates read count distribution histograms
- Quantifies PhiX contamination percentages
- Produces publication-ready visualizations

**Output:**
- QC plots (PNG format)
- Fastp HTML/JSON reports
- Statistical summaries

---

### Stage 3: Preprocessing
**Script:** `2-preprocess_pipeline.sh`

Transforms raw reads into assembly-ready FASTA sequences through:

1. **Adapter Trimming** (BBDuk)
   - Removes Illumina adapters and other contaminants
   - Configurable pattern matching

2. **Paired-End Merging** (PEAR or BBMerge)
   - Merges overlapping paired-end reads
   - Retains unmerged R1/R2 for downstream analysis
   - Reduces dataset redundancy

3. **Quality Trimming**
   - Removes low-quality bases
   - Configurable Q-score threshold (default: 20)
   - Minimum length filtering

4. **Format Conversion** (fq2fa.sh)
   - Converts FASTQ to FASTA format
   - Single unified FASTA file for assembly

**Output:**
- `*workable.fasta` - Main quality-controlled FASTA file
- `stats.tsv` - Read statistics (count, length distributions)
- `stats_plots.png` - Visual summary of preprocessing

**Key Parameters:**
- Minimum read length: 75 bp (default)
- Quality score threshold: 20 (default)
- Merger tool: PEAR or BBMerge (default: PEAR)

---

### Stage 4: Assembly & Mapping
**Script:** `3-assembly_and_map_pipeline.sh`

Performs de novo metagenome assembly and aligns reads to assembled contigs:

1. **De Novo Assembly** (MEGAHIT)
   - Sensitive assembly for low-abundance sequences
   - Supports pre-existing assemblies as alternative input
   - Filters contigs by minimum length (250 bp default)
   - Multi-k assembly strategy for improved completeness

2. **Read Mapping** (BWA-MEM)
   - High-throughput alignment of reads to contigs
   - Quality filtering (mapping quality ≥ 10)
   - Primary alignments only (excludes secondary/supplementary)
   - Memory-efficient: direct SAM-to-BAM conversion

3. **BAM Processing**
   - Sorting by genomic coordinate
   - Index generation (.bam.bai)
   - Optional PCR duplicate removal (Picard)
   - Metrics generation for duplicate analysis

4. **Automatic Cleanup**
   - Removes intermediate SAM files
   - Deletes BWA indices to save disk space

**Output:**
- `*_sorted.bam` - Primary alignment file
- `*_sorted.bam.bai` - BAM index
- `*_sorted_markdup.bam` (optional) - Duplicate-marked BAM
- `*.metrics.txt` - Picard duplicate metrics

---

### Stage 5: Outputs & Data Products

**Assembly Files:**
- `contigs.fa` - Full assembly
- `contigs_filtered.fa` - Filtered to minimum length

**Mapping Files:**
- Sorted BAM files with indices
- Ready for downstream analyses:
  - Metagenomic binning (MetaBAT, CONCOCT)
  - Taxonomic classification (Kraken2, CAT)
  - Gene prediction (FragGeneScan, Prodigal)
  - Abundance profiling (CoverM, jgi_summarize_bam_contig_depths)

---

## Key Dependencies & Tools

| Stage | Tools | Purpose |
|-------|-------|---------|
| **1** | curl, wget, gzip | Download and validate sequences |
| **2** | fastp, ShortRead (R), dada2 (R), ggplot2 (R) | Quality assessment and visualization |
| **3** | BBTools (BBDuk), PEAR/BBMerge, seqtk, pigz | Read preprocessing |
| **4** | MEGAHIT, BWA, SAMtools, Picard, EMBOSS | Assembly and mapping |

---

## Data Flow Summary

```
Raw Sequences → QC Assessment → Preprocessing → Assembly → Mapping → BAM Files
(ENA FASTQ)    (fastp + R)    (Merge + Trim)  (MEGAHIT)  (BWA)    (Indexed)
    ↓                ↓             ↓              ↓         ↓          ↓
HTML Reports     QC Plots    FASTA Output    Contigs    SAM→BAM   Ready for
JSON Reports   PhiX %age    Statistics      Filtered   Dedup      Downstream
             Distribution   Metadata        Quality    Indexed    Analyses
```

---

## Project Structure

```
ocean-metagenomes/
├── scripts/
│   ├── 1.1-download_metagenomes.sh
│   ├── 1.2-preprocess_metagenomes.sh
│   ├── 1.3-assemble_and_map_metagenomes.sh
│   ├── check_contigs_gz.sh
│   ├── download_assemblies.sh
│   └── toolbox/
│       └── metagenomic_pipelines/
│           ├── modules/
│           │   ├── 1.1-quality_check_fastp.sh
│           │   ├── 1.2-quality_check.R
│           │   ├── 2-preprocess_pipeline.sh
│           │   ├── 3-assembly_and_map_pipeline.sh
│           │   ├── conf.sh
│           │   └── resources/
│           │       ├── fq2fa.sh
│           │       └── plots.R
│           └── environment.yml
├── data/                    # Input data directory
├── resources/               # Metadata and reference files
├── logs/                    # SLURM logs and run outputs
└── tmp/                     # Temporary files
```

---

## Execution Flow

The workflow is orchestrated through three main wrapper scripts:

1. **`1.1-download_metagenomes.sh`** → Downloads raw sequences
2. **`1.2-preprocess_metagenomes.sh`** → QC assessment + preprocessing
3. **`1.3-assemble_and_map_metagenomes.sh`** → Assembly + read mapping

Each wrapper script calls corresponding modules from the `metagenomic_pipelines` toolbox.

---

## Quality Control & Validation

- **Integrity checks:** gzip -tv on downloaded files
- **PhiX contamination:** Detected and quantified at QC stage
- **Read quality:** Assessed per-position and per-read
- **Contig filtering:** Minimum 250 bp length threshold
- **Mapping quality:** Minimum mapping quality score of 10
- **Duplicate detection:** Optional Picard duplicate marking

---

## Environment & Dependencies

All dependencies are specified in `scripts/toolbox/metagenomic_pipelines/environment.yml` and can be installed via:

```bash
mamba env create -f environment.yml
mamba activate metagenomic_pipeline
```

**Core Dependencies:**
- Sequence processing: seqtk, BBTools, PEAR
- Quality control: fastp, ShortRead, dada2
- Assembly: MEGAHIT
- Mapping: BWA, SAMtools
- Utilities: Picard, EMBOSS, pigz
- Statistical analysis: R with tidyverse, ggplot2

---

## Notes on Data Processing

- **226 assemblies were initially incomplete** (identified via gzip -tv integrity checks)
- Re-downloaded assemblies were validated against originals using MD5 checksums
- The accession "ERZ477576" was not found in ENA but exists in local storage
- See `resources/Notes.md` for detailed re-download logs

