# Privacy and Interpretation Boundaries

Open Genome is designed for local analysis. Sequencing reads, alignments, variants, de novo assemblies, reports, logs, and manifest files stay on the user's machine unless the user explicitly moves or uploads them outside Open Genome.

## What May Be Downloaded

Open Genome can download public software packages, reference resources, annotation databases, and workflow code, including conda packages, GRCh38 reference files, ClinVar/dbSNP resources, hifiasm/gfastats/seqkit packages, and Nextflow pipeline dependencies. Optional report enrichments such as gnomAD VCFs, VEP/SnpEff caches, and PharmCAT are treated as local resources.

## What Is Not Uploaded

Open Genome does not upload user genome data, de novo assemblies, variant calls, sample metadata, or reports as part of the bundled setup, pipeline, or reporting scripts.

Skipped ClinVar, dbSNP, gnomAD, VEP/SnpEff, or PharmCAT sections mean a local resource or annotation field was not configured. Open Genome does not send variants to hosted annotation APIs to fill those sections.

## Interpretation Limits

Reports are evidence summaries, not diagnosis or treatment advice. Variant matches require review by classification, review status, source date, ancestry context, phenotype, family history, and clinician judgment.

Negative findings do not remove genetic risk. Positive findings do not by themselves establish disease risk or clinical actionability.

Assembly reports summarize technical assembly outputs such as contig count, total bases, N50, and longest contig. These metrics describe assembly contiguity and completeness signals; they are not health, ancestry, or trait interpretations.

Mitochondrial outputs summarize mtDNA coverage, mtDNA variants, and a reference-guided consensus sequence when possible. They are not de novo mtDNA assembly, heteroplasmy validation, haplogroup assignment, or medical interpretation.
