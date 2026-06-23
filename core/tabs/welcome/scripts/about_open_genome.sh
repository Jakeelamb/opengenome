#!/usr/bin/env sh
set -e

cat <<'EOF'
 ▗▄▖ ▗▄▄▖ ▗▄▄▄▖▗▖  ▗▖     ▗▄▄▖▗▄▄▄▖▗▖  ▗▖ ▗▄▖ ▗▖  ▗▖▗▄▄▄▖
▐▌ ▐▌▐▌ ▐▌▐▌   ▐▛▚▖▐▌    ▐▌   ▐▌   ▐▛▚▖▐▌▐▌ ▐▌▐▛▚▞▜▌▐▌
▐▌ ▐▌▐▛▀▘ ▐▛▀▀▘▐▌ ▝▜▌    ▐▌▝▜▌▐▛▀▀▘▐▌ ▝▜▌▐▌ ▐▌▐▌  ▐▌▐▛▀▀▘
▝▚▄▞▘▐▌   ▐▙▄▄▖▐▌  ▐▌    ▝▚▄▞▘▐▙▄▄▖▐▌  ▐▌▝▚▄▞▘▐▌  ▐▌▐▙▄▄▖



Open Genome is a local-first genomics workspace for people who
want to assemble and analyze their raw sequencing reads.

It is being built for non experts to be able to
install tools, configure their datasets, pull references,
run pipelines, analyze/interact with their results.

What Open Genome is:
  - a terminal app for setup, workflow launch, and reports
  - a set of Nextflow pipelines and small helper scripts
  - a local manifest for tools, data, outputs, and reports
  - an opinionated default path for common WGS inputs so users
    do not need to research every tool before their first run

What Open Genome is not:
  - a diagnosis or treatment system
  - a cloud upload service
  - a promise that every region is clinically interpreted

Your genome stays local by default.
Public tools and references are downloaded only when needed.
EOF
