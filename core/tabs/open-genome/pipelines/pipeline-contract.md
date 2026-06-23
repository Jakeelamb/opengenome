# OpenGenome Pipeline Contract

OpenGenome pipelines are split by user outcome, not by sequencing technology.

## Workflows

| Workflow | Accepted `input_type` values | Purpose |
| --- | --- | --- |
| `open-genome` | `fastq`, `long_reads`, `alignment` | Reference-based germline analysis from Illumina WGS, PacBio HiFi, ONT, BAM, or CRAM. |
| `vcf-annotate` | `vcf` | Normalize, locally annotate, and report existing VCF inputs without alignment or variant calling. |
| `denovo-assembly` | `long_reads` | De novo assembly and assembly report generation from PacBio HiFi or ONT reads. |

The scanner may produce mixed samplesheets, but each run preparation script must choose one outcome and fail early if the samplesheet contains incompatible rows for that outcome.

## First-Class Presets

| Preset | Workflow | Default stack |
| --- | --- | --- |
| `illumina_wgs_gatk` | `open-genome` | BWA-MEM2, samtools, mosdepth, GATK HaplotypeCaller, bcftools normalization. |
| `pacbio_hifi_clair3` | `open-genome` | pbmm2 CCS preset, samtools, mosdepth, Clair3 `hifi`. |
| `ont_clair3` | `open-genome` | minimap2 `map-ont`, samtools, mosdepth, Clair3 `ont`. |
| `existing_vcf_report` | `vcf-annotate` | bcftools normalization, local public-overlap annotations, OpenGenome report compiler. |
| `hifi_denovo_hifiasm` | `denovo-assembly` | hifiasm, gfastats, de novo assembly report. |
| `ont_denovo_flye` | `denovo-assembly` | Flye, gfastats, de novo assembly report for ONT-only read sets. |
| `hybrid_denovo_verkko` | `denovo-assembly` | Verkko, only after samplesheet v2 supports separate HiFi and ultra-long ONT read streams. |

Expert overrides are allowed through environment variables and params files, but the TUI should present presets first. If users do not know which path to choose, OpenGenome defaults to `illumina_wgs_gatk` for paired short reads, `pacbio_hifi_clair3` for HiFi/CCS long-read reference runs, `ont_clair3` for ONT reference runs, `hifi_denovo_hifiasm` for HiFi de novo assembly, and `ont_denovo_flye` for ONT-only de novo assembly.

## Evidence ABI

All workflows publish report inputs into stable output bands:

- `qc/`
- `alignment/`
- `variants/`
- `annotations/`
- `assembly/`
- `report/`
- `pipeline_info/`

The TUI reads report state from `report/evidence.json`, `report/run_manifest.json`, and status TSV files. It must not depend on a specific caller or assembler being present.
