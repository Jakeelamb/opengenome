#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
Open Genome report boundaries

Report now:
  - Data quality and coverage.
  - Assembly quality.
  - Variants matched to public sources.
  - ClinVar classifications with review status and source date.
  - Population frequency context.
  - Raw TSV/JSON outputs and exact tool/database versions.

Do not hide:
  - Reference build.
  - Pipeline/tool versions.
  - Database release dates.
  - Filters used.
  - Variants screened but not found.
  - Uncertain or conflicting evidence.

Do not claim:
  - Diagnosis.
  - Treatment advice.
  - Overall disease risk from one variant.
  - That a negative screen removes risk.
  - That research associations are clinically actionable.

User-facing result card fields:
  - Finding.
  - Source database.
  - Source release date.
  - Classification and review status.
  - Genotype/zygosity.
  - Population frequency.
  - What this does not mean.
  - Suggested next step.
  - Raw evidence rows.

V1 tone:
  Clear enough for a non-specialist, explicit enough for a scientist.
EOF
