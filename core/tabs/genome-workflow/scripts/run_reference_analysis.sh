#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export OPEN_GENOME_REQUIRED_ENGINE=open-genome
export OPEN_GENOME_REQUIRED_ENGINE_LABEL="reference-based analysis"
exec bash "$HERE/run_open_genome.sh"
