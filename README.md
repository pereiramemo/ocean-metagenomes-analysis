# Ocean Metagenomes

A comprehensive bioinformatics pipeline for processing, assembling, and analyzing ocean metagenomic sequences.

## Overview

This project implements a multi-stage workflow for metagenomic analysis with integrated quality control, preprocessing, de novo assembly, and read mapping capabilities. The pipeline processes raw sequencing data from ocean samples through systematic quality assessment and generates publication-ready assemblies and alignments.

## Quick Start

### Prerequisites
- Mamba or Conda installation
- SLURM job scheduling system (for batch processing)

### Installation

```bash
cd scripts/toolbox/metagenomic_pipelines
mamba env create -f environment.yml
mamba activate metagenomic_pipeline
```

### Basic Usage

Execute the pipeline stages in sequence:

```bash
# Stage 1: Download raw sequences
./scripts/1.1-download_metagenomes.sh

# Stage 2: Quality assessment and preprocessing
./scripts/1.2-preprocess_metagenomes.sh

# Stage 3: Assembly and read mapping
./scripts/1.3-assemble_and_map_metagenomes.sh
```

## Workflow Stages

### 1. Data Acquisition
Downloads raw metagenomic sequences from ENA with integrity validation.

### 2. Quality Control & Assessment
Comprehensive quality evaluation using fastp and R-based statistical analysis, including:
- Quality score distributions
- PhiX contamination detection
- Adapter identification
- Read count metrics

### 3. Preprocessing
Transforms raw reads into assembly-ready sequences:
- Adapter trimming
- Paired-end merging
- Quality filtering
- FASTA format conversion

### 4. Assembly & Mapping
De novo assembly using MEGAHIT followed by read mapping with BWA:
- Generates contigs from preprocessed reads
- Maps reads back to assembled contigs
- Produces sorted, indexed BAM files
- Optional PCR duplicate removal

### 5. Outputs
- Assembled contigs (FASTA)
- Sorted alignments (BAM + indices)
- Quality control reports and plots
- Processing statistics

## Directory Structure

```
ocean-metagenomes/
├── scripts/                          # Main pipeline scripts
│   ├── 1.1-download_metagenomes.sh
│   ├── 1.2-preprocess_metagenomes.sh
│   ├── 1.3-assemble_and_map_metagenomes.sh
│   └── toolbox/metagenomic_pipelines/  # Core modules
├── data/                             # Input sequences (symlinked)
├── resources/                        # Metadata and reference files
├── logs/                             # SLURM job logs
└── WORKFLOW.md                      # Detailed architecture & design
```

## Core Tools

- **Quality Control:** fastp, ShortRead, dada2
- **Preprocessing:** BBTools, PEAR, seqtk
- **Assembly:** MEGAHIT
- **Mapping:** BWA, SAMtools
- **Utilities:** Picard, EMBOSS

## Documentation

For detailed workflow architecture, data flow diagrams, and tool specifications, see [WORKFLOW.md](WORKFLOW.md).

For comprehensive module documentation, see the [metagenomic_pipelines README](scripts/toolbox/metagenomic_pipelines/README.md).

## Data Notes

- 226 assemblies were re-downloaded and validated due to integrity issues
- All downloads verified using MD5 checksums
- See [resources/Notes.md](resources/Notes.md) for processing history

## Features

✅ Modular pipeline design
✅ Parallel processing support
✅ Comprehensive quality control
✅ Memory-efficient BAM generation
✅ Automatic intermediate file cleanup
✅ Batch processing capabilities
✅ Optional duplicate removal
✅ Pre-assembled contig support

## Configuration

Pipeline parameters are configurable via command-line options. See individual module help:

```bash
./modules/1.1-quality_check_fastp.sh --help
./modules/2-preprocess_pipeline.sh --help
./modules/3-assembly_and_map_pipeline.sh --help
```

## License

GNU General Public License v3.0 - See LICENSE file for details.

Copyright (C) 2025 Emiliano Pereira

## Contact

For issues, questions, or contributions, please refer to the project repository.
