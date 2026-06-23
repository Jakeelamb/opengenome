# OpenGenome Reference Germline Output

Outputs are organized by report band so the TUI can read stable paths independent of caller choice.

| Directory | Contents |
| --- | --- |
| `qc/` | fastp/FastQC/MultiQC files, samtools stats, mosdepth depth summaries. |
| `long-read-qc/` | Long-read staging and `seqkit stats` outputs. |
| `alignment/` | Sorted BAM/BAI outputs and long-read alignment status TSVs. |
| `variants/` | Raw caller VCFs, normalized VCFs, indexes, and bcftools stats. |
| `annotations/` | Local annotation TSVs, consequence summaries, public overlap evidence, PharmCAT status. |
| `mitochondrial/` | Reference-guided mitochondrial consensus outputs when chrM/MT is available. |
| `report/` | `report_index.html`, `open_genome_report.html`, `findings.tsv`, `evidence.json`, `run_manifest.json`. |
| `pipeline_info/` | Nextflow timeline, report, trace, and DAG files. |

Optional local resources produce explicit `skipped`, `disabled`, `missing`, or `complete` state rows in status TSVs. The report must not imply a public evidence source was assessed when the matching local resource was absent.
