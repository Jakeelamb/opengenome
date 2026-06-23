# OpenGenome Existing VCF Report Output

| Directory | Contents |
| --- | --- |
| `variants/` | Normalized VCF, index, bcftools stats, and VCF ingress status. |
| `annotations/` | Local annotation TSVs, public-overlap evidence, consequence summaries, and PharmCAT status. |
| `report/` | `report_index.html`, `open_genome_report.html`, `findings.tsv`, `evidence.json`, `run_manifest.json`. |
| `pipeline_info/` | Nextflow timeline, report, trace, and DAG files. |

This workflow is intentionally report-only. If the user wants to regenerate variants from reads or alignments, run the reference germline workflow instead.
