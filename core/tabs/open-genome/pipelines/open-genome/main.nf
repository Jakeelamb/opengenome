nextflow.enable.dsl = 2

def required(name, value) {
    if (value == null || value.toString().trim() == '') {
        error "Missing required parameter: ${name}"
    }
}

def optionalPath(value) {
    if (value == null) return ''
    def s = value.toString().trim()
    return s in ['', 'true', 'false', 'null'] ? '' : s
}

process READ_QC {
    tag { row_id }
    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(read1), path(read2)

    output:
    tuple val(sample), val(row_id), path("${row_id}.trimmed.R1.fastq.gz"), path("${row_id}.trimmed.R2.fastq.gz"), emit: trimmed_fastq
    path "fastp.${row_id}.json", emit: fastp_json
    path "fastp.${row_id}.html", emit: fastp_html
    path "*_fastqc.html", emit: fastqc_html
    path "*_fastqc.zip", emit: fastqc_zip

    script:
    """
    fastp \\
      -i "$read1" -I "$read2" \\
      -o "${row_id}.trimmed.R1.fastq.gz" -O "${row_id}.trimmed.R2.fastq.gz" \\
      -j "fastp.${row_id}.json" -h "fastp.${row_id}.html"
    fastqc "${row_id}.trimmed.R1.fastq.gz" "${row_id}.trimmed.R2.fastq.gz"
    """

    stub:
    """
    printf '{}' > "fastp.${row_id}.json"
    printf '<html><body>fastp stub</body></html>' > "fastp.${row_id}.html"
    touch "${row_id}.trimmed.R1.fastq.gz" "${row_id}.trimmed.R2.fastq.gz"
    touch "${row_id}.trimmed.R1_fastqc.html" "${row_id}.trimmed.R1_fastqc.zip"
    touch "${row_id}.trimmed.R2_fastqc.html" "${row_id}.trimmed.R2_fastqc.zip"
    """
}

process ALIGN_FASTQ {
    tag { row_id }
    publishDir "${params.outdir}/alignment", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(read1), path(read2)

    output:
    tuple val(sample), val(row_id), path("${row_id}.sorted.bam"), emit: bam
    path "${row_id}.sorted.bam.bai", emit: bai

    script:
    """
    bwa mem -t ${task.cpus} -R "@RG\\tID:${row_id}\\tSM:${sample}\\tPL:ILLUMINA" "${params.fasta}" "$read1" "$read2" \\
      | samtools sort -@ ${task.cpus} -o "${row_id}.sorted.bam" -
    samtools index "${row_id}.sorted.bam"
    """

    stub:
    """
    touch "${row_id}.sorted.bam" "${row_id}.sorted.bam.bai"
    """
}

process STAGE_ALIGNMENT {
    tag { row_id }
    publishDir "${params.outdir}/alignment", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(alignment), val(kind)

    output:
    tuple val(sample), val(row_id), path("${row_id}.input.bam"), emit: alignment

    script:
    """
    if [[ "$kind" == "cram" ]]; then
      samtools view -@ ${task.cpus} -T "${params.fasta}" -b -o "${row_id}.input.bam" "$alignment"
    else
      cp "$alignment" "${row_id}.input.bam"
    fi
    samtools index "${row_id}.input.bam"
    """

    stub:
    """
    touch "${row_id}.input.bam"
    """
}

process ALIGNMENT_QC {
    tag { row_id }
    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(alignment)

    output:
    tuple val(sample), val(row_id), path(alignment), emit: alignment_passthrough
    path "${row_id}.samtools.flagstat.txt", emit: flagstat
    path "${row_id}.samtools.stats.txt", emit: samtools_stats
    path "${row_id}.mosdepth.summary.txt", emit: mosdepth_summary

    script:
    """
    samtools flagstat "$alignment" > "${row_id}.samtools.flagstat.txt"
    samtools stats --reference "${params.fasta}" "$alignment" > "${row_id}.samtools.stats.txt"
    samtools index "$alignment"
    mosdepth -f "${params.fasta}" -t ${task.cpus} "${row_id}" "$alignment"
    """

    stub:
    """
    printf '0 + 0 in total\\n' > "${row_id}.samtools.flagstat.txt"
    printf 'SN\\tnumber of records:\\t0\\n' > "${row_id}.samtools.stats.txt"
    printf 'chrom\\tlength\\tbases\\tmean\\tmin\\tmax\\n' > "${row_id}.mosdepth.summary.txt"
    """
}

process GATK_GERMLINE {
    tag { row_id }
    publishDir "${params.outdir}/variants", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(alignment)

    output:
    tuple val(sample), val(row_id), path("${row_id}.raw.vcf.gz"), emit: raw_vcf
    path "${row_id}.raw.vcf.gz.tbi", emit: raw_tbi

    script:
    def known = []
    def dbsnp = optionalPath(params.dbsnp)
    def knownIndels = optionalPath(params.known_indels)
    if (dbsnp) known << "--known-sites '${dbsnp}'"
    if (knownIndels) known << "--known-sites '${knownIndels}'"
    def knownArgs = known.join(' ')
    """
    gatk MarkDuplicates -I "$alignment" -O "${row_id}.md.bam" -M "${row_id}.markduplicates.metrics.txt" --CREATE_INDEX true
    if [[ -n "${knownArgs}" ]]; then
      gatk BaseRecalibrator -R "${params.fasta}" -I "${row_id}.md.bam" ${knownArgs} -O "${row_id}.recal.table"
      gatk ApplyBQSR -R "${params.fasta}" -I "${row_id}.md.bam" --bqsr-recal-file "${row_id}.recal.table" -O "${row_id}.recal.bam"
      samtools index "${row_id}.recal.bam"
      call_bam="${row_id}.recal.bam"
    else
      call_bam="${row_id}.md.bam"
    fi
    gatk HaplotypeCaller -R "${params.fasta}" -I "\$call_bam" -O "${row_id}.raw.vcf.gz"
    tabix -f -p vcf "${row_id}.raw.vcf.gz"
    """

    stub:
    """
    printf '##fileformat=VCFv4.2\\n#CHROM\\tPOS\\tID\\tREF\\tALT\\tQUAL\\tFILTER\\tINFO\\n' | bgzip -c > "${row_id}.raw.vcf.gz"
    tabix -f -p vcf "${row_id}.raw.vcf.gz" || touch "${row_id}.raw.vcf.gz.tbi"
    """
}

process NORMALIZE_VCF {
    tag { row_id }
    publishDir "${params.outdir}/variants", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(vcf)

    output:
    tuple val(sample), val(row_id), path("${row_id}.normalized.vcf.gz"), emit: normalized_vcf
    path "${row_id}.normalized.vcf.gz.tbi", emit: normalized_tbi
    path "${row_id}.bcftools.stats.txt", emit: bcftools_stats

    script:
    """
    bcftools norm -f "${params.fasta}" -m -any "$vcf" -Oz -o "${row_id}.normalized.vcf.gz"
    tabix -f -p vcf "${row_id}.normalized.vcf.gz"
    bcftools stats "${row_id}.normalized.vcf.gz" > "${row_id}.bcftools.stats.txt"
    """

    stub:
    """
    cp "$vcf" "${row_id}.normalized.vcf.gz" || touch "${row_id}.normalized.vcf.gz"
    touch "${row_id}.normalized.vcf.gz.tbi"
    printf 'SN\\tnumber of records:\\t0\\n' > "${row_id}.bcftools.stats.txt"
    """
}

process ANNOTATE_VCF {
    tag { row_id }
    publishDir "${params.outdir}/annotations", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(vcf)

    output:
    tuple val(sample), val(row_id), path("${row_id}.annotated.vcf.gz"), emit: annotated_vcf
    path "${row_id}.clinvar.matches.tsv", emit: clinvar_tsv
    path "${row_id}.variant_summary.tsv", emit: variant_tsv
    path "${row_id}.annotation_status.tsv", emit: annotation_status

    script:
    def dbsnp = optionalPath(params.dbsnp)
    def clinvar = optionalPath(params.clinvar)
    """
    printf 'row_id\\tsample\\tstep\\tstate\\tmessage\\n' > "${row_id}.annotation_status.tsv"
    cp "$vcf" "${row_id}.annotated.vcf.gz"
    if [[ "${dbsnp}" != "" && -f "${dbsnp}" ]]; then
      bcftools annotate -a "${dbsnp}" -c ID "$vcf" -Oz -o "${row_id}.annotated.vcf.gz"
      printf '%s\\t%s\\tdbsnp\\tcomplete\\t%s\\n' "${row_id}" "${sample}" "${dbsnp}" >> "${row_id}.annotation_status.tsv"
    else
      printf '%s\\t%s\\tdbsnp\\tskipped\\tno dbSNP VCF configured\\n' "${row_id}" "${sample}" >> "${row_id}.annotation_status.tsv"
    fi
    tabix -f -p vcf "${row_id}.annotated.vcf.gz"
    printf 'chrom\\tpos\\tid\\tref\\talt\\tgt\\n' > "${row_id}.variant_summary.tsv"
    bcftools query -f '%CHROM\\t%POS\\t%ID\\t%REF\\t%ALT[\\t%GT]\\n' "${row_id}.annotated.vcf.gz" >> "${row_id}.variant_summary.tsv"
    if [[ "${params.enable_clinvar}" == "true" && "${clinvar}" != "" && -f "${clinvar}" ]]; then
      bcftools isec -n=2 -w1 "$vcf" "${clinvar}" -Oz -p clinvar_isec
      printf 'chrom\\tpos\\tid\\tref\\talt\\tgt\\n' > "${row_id}.clinvar.matches.tsv"
      if [[ -f clinvar_isec/0000.vcf.gz ]]; then
        bcftools query -f '%CHROM\\t%POS\\t%ID\\t%REF\\t%ALT[\\t%GT]\\n' clinvar_isec/0000.vcf.gz >> "${row_id}.clinvar.matches.tsv"
      fi
      printf '%s\\t%s\\tclinvar\\tcomplete\\t%s\\n' "${row_id}" "${sample}" "${clinvar}" >> "${row_id}.annotation_status.tsv"
    else
      printf 'chrom\\tpos\\tid\\tref\\talt\\tgt\\n' > "${row_id}.clinvar.matches.tsv"
      printf '%s\\t%s\\tclinvar\\tskipped\\tClinVar disabled or not configured\\n' "${row_id}" "${sample}" >> "${row_id}.annotation_status.tsv"
    fi
    """

    stub:
    """
    cp "$vcf" "${row_id}.annotated.vcf.gz" || touch "${row_id}.annotated.vcf.gz"
    printf 'chrom\\tpos\\tid\\tref\\talt\\tgt\\n' > "${row_id}.variant_summary.tsv"
    printf 'chrom\\tpos\\tid\\tref\\talt\\tgt\\n' > "${row_id}.clinvar.matches.tsv"
    printf 'row_id\\tsample\\tstep\\tstate\\tmessage\\n%s\\t%s\\tstub\\tcomplete\\tstub\\n' "${row_id}" "${sample}" > "${row_id}.annotation_status.tsv"
    """
}

process PHARMCAT {
    tag { row_id }
    publishDir "${params.outdir}/annotations/pharmcat", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(vcf)

    output:
    path "${row_id}.pharmcat_status.tsv", emit: status
    path "pharmcat", emit: pharmcat_dir

    script:
    def pharmcatJar = optionalPath(params.pharmcat_jar)
    """
    mkdir -p pharmcat
    printf 'row_id\\tsample\\tstate\\tmessage\\n' > "${row_id}.pharmcat_status.tsv"
    if [[ "${params.enable_pgx}" != "true" ]]; then
      printf '%s\\t%s\\tdisabled\\tPharmCAT disabled\\n' "${row_id}" "${sample}" >> "${row_id}.pharmcat_status.tsv"
    elif [[ "${pharmcatJar}" != "" && -f "${pharmcatJar}" ]]; then
      if java -jar "${pharmcatJar}" -vcf "$vcf" -o pharmcat > pharmcat/pharmcat.log 2>&1; then
        printf '%s\\t%s\\tcomplete\\tPharmCAT completed\\n' "${row_id}" "${sample}" >> "${row_id}.pharmcat_status.tsv"
      else
        printf '%s\\t%s\\tfailed\\tPharmCAT failed; see pharmcat.log\\n' "${row_id}" "${sample}" >> "${row_id}.pharmcat_status.tsv"
        exit 1
      fi
    else
      printf '%s\\t%s\\tskipped\\tPharmCAT jar not configured; PGx not assessed\\n' "${row_id}" "${sample}" >> "${row_id}.pharmcat_status.tsv"
    fi
    """

    stub:
    """
    mkdir -p pharmcat
    printf 'row_id\\tsample\\tstate\\tmessage\\n%s\\t%s\\tstub\\tPharmCAT stub\\n' "${row_id}" "${sample}" > "${row_id}.pharmcat_status.tsv"
    """
}

process ASSEMBLY_QC {
    tag { row_id }
    publishDir "${params.outdir}/assembly", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(assembly)

    output:
    path "${row_id}.gfastats.txt", emit: gfastats

    script:
    """
    gfastats "$assembly" > "${row_id}.gfastats.txt"
    """

    stub:
    """
    printf '# scaffolds: 0\\n' > "${row_id}.gfastats.txt"
    """
}

process COMPILE_REPORT {
    publishDir "${params.outdir}/report", mode: 'copy'

    input:
    path report_inputs

    output:
    path "open_genome_report.html", emit: report_html
    path "findings.tsv", emit: findings_tsv
    path "evidence.json", emit: evidence_json
    path "run_manifest.json", emit: run_manifest

    script:
    def clinvar = optionalPath(params.clinvar)
    def dbsnp = optionalPath(params.dbsnp)
    def pharmcatJar = optionalPath(params.pharmcat_jar)
    """
    python3 "${params.report_compiler}" \\
      --input-dir . \\
      --out-dir . \\
      --samplesheet "${params.samplesheet}" \\
      --reference "${params.fasta}" \\
      --clinvar "${clinvar}" \\
      --dbsnp "${dbsnp}" \\
      --pharmcat-jar "${pharmcatJar}"
    """

    stub:
    """
    printf '<html><body>Open Genome stub report</body></html>\\n' > open_genome_report.html
    printf 'sample\\tfinding\\tsource\\n' > findings.tsv
    printf '{}\\n' > evidence.json
    printf '{}\\n' > run_manifest.json
    """
}

workflow {
    required('samplesheet', params.samplesheet)
    required('fasta', params.fasta)

    Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true)
        .map { row ->
            def sample = row.sample?.toString()?.trim()
            def rowId = row.row_id?.toString()?.trim() ?: sample
            def inputType = row.input_type?.toString()?.trim()
            if (!sample) error "samplesheet row is missing sample"
            if (!rowId) error "samplesheet row for ${sample} is missing row_id"
            if (!inputType) error "samplesheet row for ${sample} is missing input_type"
            tuple(sample, rowId, inputType, row)
        }
        .set { samples_ch }

    samples_ch
        .filter { sample, rowId, inputType, row -> inputType == 'fastq' }
        .map { sample, rowId, inputType, row -> tuple(sample, rowId, file(row.fastq_1), file(row.fastq_2)) }
        .set { fastq_ch }

    samples_ch
        .filter { sample, rowId, inputType, row -> inputType == 'alignment' }
        .map { sample, rowId, inputType, row -> tuple(sample, rowId, file(row.bam ?: row.cram), row.bam ? 'bam' : 'cram') }
        .set { alignment_input_ch }

    samples_ch
        .filter { sample, rowId, inputType, row -> inputType == 'vcf' }
        .map { sample, rowId, inputType, row -> tuple(sample, rowId, file(row.vcf)) }
        .set { vcf_input_ch }

    samples_ch
        .filter { sample, rowId, inputType, row -> inputType == 'assembly' }
        .map { sample, rowId, inputType, row -> tuple(sample, rowId, file(row.assembly)) }
        .set { assembly_input_ch }

    READ_QC(fastq_ch)
    ALIGN_FASTQ(READ_QC.out.trimmed_fastq)
    STAGE_ALIGNMENT(alignment_input_ch)

    alignment_for_qc_ch = ALIGN_FASTQ.out.bam.mix(STAGE_ALIGNMENT.out.alignment)
    ALIGNMENT_QC(alignment_for_qc_ch)
    GATK_GERMLINE(ALIGNMENT_QC.out.alignment_passthrough)

    vcf_for_norm_ch = GATK_GERMLINE.out.raw_vcf.mix(vcf_input_ch)
    NORMALIZE_VCF(vcf_for_norm_ch)
    ANNOTATE_VCF(NORMALIZE_VCF.out.normalized_vcf)
    PHARMCAT(NORMALIZE_VCF.out.normalized_vcf)
    ASSEMBLY_QC(assembly_input_ch)

    report_inputs_ch = READ_QC.out.fastp_json
        .mix(READ_QC.out.fastqc_html)
        .mix(ALIGNMENT_QC.out.flagstat)
        .mix(ALIGNMENT_QC.out.samtools_stats)
        .mix(ALIGNMENT_QC.out.mosdepth_summary)
        .mix(NORMALIZE_VCF.out.bcftools_stats)
        .mix(ANNOTATE_VCF.out.variant_tsv)
        .mix(ANNOTATE_VCF.out.clinvar_tsv)
        .mix(ANNOTATE_VCF.out.annotation_status)
        .mix(PHARMCAT.out.status)
        .mix(ASSEMBLY_QC.out.gfastats)
        .collect()

    COMPILE_REPORT(report_inputs_ch)
}
