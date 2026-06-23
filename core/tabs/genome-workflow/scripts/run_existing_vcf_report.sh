#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export OPEN_GENOME_REQUIRED_ENGINE=vcf-annotate
export OPEN_GENOME_REQUIRED_ENGINE_LABEL="existing VCF report"
exec bash "$HERE/run_open_genome.sh"
