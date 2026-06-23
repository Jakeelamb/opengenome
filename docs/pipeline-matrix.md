# Open Genome Pipeline Matrix

Open Genome keeps user data local and treats external public resources as optional local inputs. The bundled Nextflow pipelines are designed around a small number of explicit modes instead of one opaque catch-all workflow.

## Outcome Workflows

| Workflow | Accepted rows | Purpose |
| --- | --- | --- |
| `open-genome` | `fastq`, `long_reads`, `alignment` | Reference-based germline analysis from reads or existing BAM/CRAM. |
| `vcf-annotate` | `vcf` | Existing VCF normalization, local annotation, and report generation. |
| `denovo-assembly` | `long_reads` | De novo assembly from PacBio HiFi or ONT long reads. |

The scanner can write mixed samplesheets, but run preparation chooses one outcome and fails early when rows mix incompatible workflows.

## Reference-Based WGS

| Input | Default path | Optional path | Output contract |
| --- | --- | --- | --- |
| Illumina paired FASTQ | fastp/FastQC -> BWA-MEM2 -> samtools/mosdepth -> GATK | BWA instead of BWA-MEM2; DeepVariant or Clair3 when selected | aligned BAM, QC, normalized VCF, report evidence |
| Existing BAM/CRAM | samtools/mosdepth -> selected caller | GATK, DeepVariant, or Clair3 | QC, normalized VCF, report evidence |
| PacBio HiFi reads | pbmm2 CCS preset when available, otherwise minimap2 `map-hifi` -> Clair3 `hifi` in auto mode | DeepVariant when a compatible external executable/container wrapper is supplied | aligned BAM, caller status, normalized VCF, report evidence |
| ONT reads | minimap2 `map-ont` -> Clair3 `ont` in auto mode | Dorado aligner when installed; DeepVariant when a compatible external executable/container wrapper is supplied | aligned BAM, caller status, normalized VCF, report evidence |
| Existing VCF | `vcf-annotate`: bcftools normalization and local annotation | ClinVar/dbSNP/gnomAD/VEP/SnpEff/PharmCAT local resources | normalized/annotated VCF, report evidence |

DeepVariant and Dorado are executable integrations because many users install them through Docker, Apptainer, or vendor archives. Clair3, pbmm2, BWA-MEM2, minimap2, GATK, and the report/QC tools are part of the conda environment when available from conda-forge/bioconda.

The caller defaults are intentionally platform-specific. GATK is the default for Illumina short-read germline SNP/indel calling. Clair3 is the default for PacBio HiFi and ONT long-read germline small variants because it was built for long-read sequencing with pileup plus full-alignment models: Zheng et al., [Symphonizing pileup and full-alignment for deep learning-based long-read variant calling](https://doi.org/10.1038/s43588-022-00387-x), Nature Computational Science 2022. The 2026 accelerated Clair3 paper is also useful background for runtime expectations: Zheng et al., [Accelerated long-read variant calling with Clair3 for whole-genome sequencing](https://doi.org/10.1093/bioinformatics/btag181), Bioinformatics 2026.

## De Novo Assembly

| Input | Assembler | Intended use | Output contract |
| --- | --- | --- | --- |
| PacBio HiFi / CCS | hifiasm | Default human long-read assembly path | primary FASTA/GFA, assembler log, gfastats, report |
| ONT high-quality reads | Flye | Default ONT-only local assembly path | primary FASTA/GFA, assembler log, gfastats, report |
| HiFi plus ultra-long ONT | Verkko | High-end T2T-style accurate-long-read plus ultra-long ONT assembly once separate read streams are available | primary FASTA/GFA, assembler log, gfastats, report |

The de novo pipeline normalizes each assembler branch into the same report contract so the TUI does not need separate result handling for hifiasm, Flye, and Verkko.

## Verification

`scripts/check-genomics.sh` runs tiny local stub graphs for:

- existing-VCF report mode through `vcf-annotate`,
- PacBio HiFi reference mode with Clair3 stubs,
- hifiasm de novo mode,
- Flye de novo mode,
- Verkko de novo mode.

These tests verify graph wiring, output names, and report contracts without requiring human-scale reads or heavyweight callers.

`scripts/pipeline-real-smoke.sh` adds tiny non-stub checks when the local conda environments are available. It executes:

- `vcf-annotate` on a valid synthetic VCF with an ANN consequence field, verifying normalized VCFs, parsed consequence summaries, and report artifacts.
- `open-genome` on paired synthetic FASTQ reads with the default BWA-MEM2 plus GATK path, verifying aligned BAM, QC outputs, normalized VCFs, and report artifacts.
- `open-genome` on official Clair3 PacBio HiFi and ONT demo alignments, verifying real Clair3 VCFs, normalized VCFs, and report artifacts.
- direct Flye assembly-stage smoke on Flye's bundled raw-read E. coli 500 kb fixture, verifying draft FASTA and gfastats output.
- `denovo-assembly` with hifiasm on Flye's bundled HiFi E. coli 500 kb fixture, verifying primary FASTA/GFA, gfastats, and assembly report artifacts.
