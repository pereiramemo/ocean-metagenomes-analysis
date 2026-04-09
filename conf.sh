#!/bin/bash

# Configuration file for ocean-metagenomes project

# Set MAMBA_ROOT_PREFIX for mamba 2.0+
export MAMBA_ROOT_PREFIX="$HOME/miniconda"

# Initialize conda - try common installation paths
if [ -f "$HOME/mambaforge/etc/profile.d/conda.sh" ]; then
    . "$HOME/mambaforge/etc/profile.d/conda.sh"
elif [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    . "$HOME/miniconda3/etc/profile.d/conda.sh"
    export MAMBA_ROOT_PREFIX="$HOME/miniconda3"
elif [ -f "$HOME/miniconda/etc/profile.d/conda.sh" ]; then
    . "$HOME/miniconda/etc/profile.d/conda.sh"
    export MAMBA_ROOT_PREFIX="$HOME/miniconda"
elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
    . "$HOME/anaconda3/etc/profile.d/conda.sh"
    export MAMBA_ROOT_PREFIX="$HOME/anaconda3"
elif [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
    . "/opt/conda/etc/profile.d/conda.sh"
    export MAMBA_ROOT_PREFIX="/opt/conda"
else
    echo "WARNING: Could not find conda.sh to initialize conda"
fi

# Initialize mamba - source mamba.sh files
if [ -f "$HOME/mambaforge/etc/profile.d/mamba.sh" ]; then
    . "$HOME/mambaforge/etc/profile.d/mamba.sh"
elif [ -f "$HOME/miniconda3/etc/profile.d/mamba.sh" ]; then
    . "$HOME/miniconda3/etc/profile.d/mamba.sh"
elif [ -f "$HOME/miniconda/etc/profile.d/mamba.sh" ]; then
    . "$HOME/miniconda/etc/profile.d/mamba.sh"
elif [ -f "$HOME/anaconda3/etc/profile.d/mamba.sh" ]; then
    . "$HOME/anaconda3/etc/profile.d/mamba.sh"
fi

# Activate conda environment
conda activate ocean-metagenomes-env

# Main workspace directory
WORKSPACE="/home/epereira/workspace/dev/ocean-metagenomes"

# Data directory
DATA="${WORKSPACE}/data"

# Scripts directory
SCRIPTS="${WORKSPACE}/scripts"

# Resources directory
RESOURCES="${WORKSPACE}/resources"

# Contigs 
CONTIGS_ORG="/home/phuber/wplace/AtlantECO_j/MGNIFY/test/conting_sequences"
CONTIGS="${WORKSPACE}/data/assemblies"

# Export variables
export WORKSPACE
export DATA
export SCRIPTS
export RESOURCES
export CONTIGS
