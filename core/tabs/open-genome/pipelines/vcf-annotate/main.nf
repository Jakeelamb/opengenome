nextflow.enable.dsl = 2

def required(String name, value) {
    if (value == null || value.toString().trim() == '') {
        error "Missing required parameter: --${name}"
    }
}

def optionalPath(value) {
    if (value == null) {
        return ''
    }
    def text = value.toString().trim()
    if (!text || text in ['true', 'false', 'null']) {
        return ''
    }
    return text
}

process NORMALIZE_EXISTING_VCF {
    tag { row_id }
    publishDir "${params.outdir}/variants", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(vcf)

    output:
    tuple val(sample), val(row_id), path("${row_id}.normalized.vcf.gz"), path("${row_id}.normalized.vcf.gz.tbi"), emit: normalized_vcf
    path "${row_id}.bcftools.stats.txt", emit: bcftools_stats
    path "${row_id}.vcf_ingress_status.tsv", emit: ingress_status

    script:
    """
    printf 'row_id\\tsample\\tstep\\tstate\\tmessage\\n' > "${row_id}.vcf_ingress_status.tsv"
    bcftools norm -f "${params.fasta}" -m -any "$vcf" -Oz -o "${row_id}.normalized.vcf.gz"
    tabix -f -p vcf "${row_id}.normalized.vcf.gz"
    bcftools stats "${row_id}.normalized.vcf.gz" > "${row_id}.bcftools.stats.txt"
    printf '%s\\t%s\\tnormalize\\tcomplete\\tExisting VCF normalized with bcftools\\n' "${row_id}" "${sample}" >> "${row_id}.vcf_ingress_status.tsv"
    """

    stub:
    """
    cp "$vcf" "${row_id}.normalized.vcf.gz" || touch "${row_id}.normalized.vcf.gz"
    touch "${row_id}.normalized.vcf.gz.tbi"
    printf 'SN\\tnumber of records:\\t0\\n' > "${row_id}.bcftools.stats.txt"
    printf 'row_id\\tsample\\tstep\\tstate\\tmessage\\n%s\\t%s\\tnormalize\\tstub\\tExisting VCF normalize stub\\n' "${row_id}" "${sample}" > "${row_id}.vcf_ingress_status.tsv"
    """
}

process LOCAL_ANNOTATE_VCF {
    tag { row_id }
    publishDir "${params.outdir}/annotations", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(vcf), path(vcf_tbi)

    output:
    tuple val(sample), val(row_id), path("${row_id}.annotated.vcf.gz"), emit: annotated_vcf
    path "${row_id}.variant_summary.tsv", emit: variant_tsv
    path "${row_id}.clinvar.matches.tsv", emit: clinvar_tsv
    path "${row_id}.public_annotations.tsv", emit: public_annotations
    path "${row_id}.annotation_status.tsv", emit: annotation_status
    path "${row_id}.consequence_summary.tsv", emit: consequence_tsv
    path "${row_id}.consequence_status.tsv", emit: consequence_status
    path "${row_id}.pharmcat_status.tsv", emit: pharmcat_status

    script:
    def dbsnp = optionalPath(params.dbsnp)
    def clinvar = optionalPath(params.clinvar)
    def gnomad = optionalPath(params.gnomad)
    def vepCache = optionalPath(params.vep_cache)
    def snpEffDb = optionalPath(params.snpeff_db)
    def pharmcatJar = optionalPath(params.pharmcat_jar)
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

    if [[ "${gnomad}" != "" && -f "${gnomad}" ]]; then
      bcftools isec -n=2 -w1 "$vcf" "${gnomad}" -Oz -p gnomad_isec
      printf '%s\\t%s\\tgnomad\\tcomplete\\t%s\\n' "${row_id}" "${sample}" "${gnomad}" >> "${row_id}.annotation_status.tsv"
    else
      printf '%s\\t%s\\tgnomad\\tskipped\\tgnomAD VCF not configured\\n' "${row_id}" "${sample}" >> "${row_id}.annotation_status.tsv"
    fi

    python3 - "${row_id}" "${sample}" "${row_id}.annotated.vcf.gz" "clinvar_isec/0000.vcf.gz" "gnomad_isec/0000.vcf.gz" "${row_id}.public_annotations.tsv" "${row_id}.consequence_summary.tsv" "${row_id}.consequence_status.tsv" "${vepCache}" "${snpEffDb}" <<'PY'
import gzip
import re
import sys
from collections import Counter
from pathlib import Path

row_id, sample, annotated, clinvar, gnomad, public_out, consequence_out, consequence_status, vep_cache, snpeff_db = sys.argv[1:]

def open_text(path):
    p = Path(path)
    if not p.is_file():
        return None
    return gzip.open(p, "rt", encoding="utf-8", errors="replace") if p.suffix == ".gz" else p.open("r", encoding="utf-8", errors="replace")

def info_map(raw):
    out = {}
    for item in raw.split(";"):
        if not item:
            continue
        if "=" in item:
            key, value = item.split("=", 1)
        else:
            key, value = item, "present"
        out[key] = value
    return out

def iter_variants(path):
    fh = open_text(path)
    if fh is None:
        return
    with fh:
        for line in fh:
            if not line or line.startswith("#"):
                continue
            fields = line.rstrip("\\n").split("\\t")
            if len(fields) < 8:
                continue
            chrom, pos, vid, ref, alt = fields[:5]
            yield chrom, pos, vid, ref, alt, info_map(fields[7])

def write_public(fh, chrom, pos, vid, ref, alt, source, label, value, note):
    fh.write("\\t".join([row_id, sample, chrom, pos, vid, ref, alt, source, label, value, note]) + "\\n")

csq_fields = []
counts = Counter()
state = "skipped"
message = "No VEP CSQ or SnpEff ANN consequence field found; local consequence annotation not assessed"
fh = open_text(annotated)
if fh is not None:
    with fh:
        for line in fh:
            if line.startswith("##INFO=<ID=CSQ"):
                match = re.search(r"Format: ([^\\\"]+)", line)
                if match:
                    csq_fields = [part.strip() for part in match.group(1).split("|")]
            if line.startswith("#"):
                continue
            fields = line.rstrip("\\n").split("\\t")
            if len(fields) < 8:
                continue
            info = info_map(fields[7])
            if "ANN" in info:
                state = "parsed"
                message = "Parsed SnpEff ANN fields already present in VCF"
                for ann in info["ANN"].split(","):
                    parts = ann.split("|")
                    counts[("SnpEff ANN", parts[1] if len(parts) > 1 and parts[1] else "unknown", parts[3] if len(parts) > 3 else "", parts[2] if len(parts) > 2 else "unknown", "ANN field present in VCF")] += 1
            if "CSQ" in info:
                state = "parsed"
                message = "Parsed VEP CSQ fields already present in VCF"
                for csq in info["CSQ"].split(","):
                    parts = csq.split("|")
                    mapped = dict(zip(csq_fields, parts)) if csq_fields else {}
                    counts[("VEP CSQ", mapped.get("Consequence") or (parts[1] if len(parts) > 1 else "unknown"), mapped.get("SYMBOL") or mapped.get("Gene") or "", mapped.get("IMPACT") or "unknown", "CSQ field present in VCF")] += 1

if not counts and (vep_cache or snpeff_db):
    state = "configured_no_fields"
    message = "VEP/SnpEff config was present, but this VCF did not contain CSQ or ANN fields"

with open(public_out, "w", encoding="utf-8") as out:
    out.write("row_id\\tsample\\tchrom\\tpos\\tid\\tref\\talt\\tsource\\tlabel\\tvalue\\tnote\\n")
    for chrom, pos, vid, ref, alt, info in iter_variants(annotated) or []:
        if vid and vid != ".":
            write_public(out, chrom, pos, vid, ref, alt, "dbSNP", "variant ID", vid, "Known public ID on annotated VCF")
        for key in ("AF", "AF_popmax", "gnomAD_AF", "gnomADg_AF", "gnomADe_AF"):
            if key in info:
                write_public(out, chrom, pos, vid, ref, alt, "gnomAD", key, info[key], "Allele-frequency field present on VCF record")
    for chrom, pos, vid, ref, alt, info in iter_variants(clinvar) or []:
        write_public(out, chrom, pos, vid, ref, alt, "ClinVar", "overlap", "present", "Variant overlaps configured local ClinVar VCF")
    for chrom, pos, vid, ref, alt, info in iter_variants(gnomad) or []:
        write_public(out, chrom, pos, vid, ref, alt, "gnomAD", "overlap", "present", "Variant overlaps configured local gnomAD VCF")

with open(consequence_out, "w", encoding="utf-8") as out:
    out.write("row_id\\tsample\\ttool\\tstate\\tconsequence\\tgene\\timpact\\tcount\\tnote\\n")
    if counts:
        for (tool, consequence, gene, impact, note), count in sorted(counts.items()):
            out.write("\\t".join([row_id, sample, tool, state, consequence, gene, impact, str(count), note]) + "\\n")
    else:
        out.write("\\t".join([row_id, sample, "VEP/SnpEff", state, "not_assessed", "", "", "0", message]) + "\\n")

with open(consequence_status, "w", encoding="utf-8") as out:
    out.write("row_id\\tsample\\tstep\\tstate\\tmessage\\n")
    out.write("\\t".join([row_id, sample, "consequence", state, message]) + "\\n")
PY

    printf 'row_id\\tsample\\tstate\\tmessage\\n' > "${row_id}.pharmcat_status.tsv"
    if [[ "${params.enable_pgx}" != "true" ]]; then
      printf '%s\\t%s\\tdisabled\\tPharmCAT disabled\\n' "${row_id}" "${sample}" >> "${row_id}.pharmcat_status.tsv"
    elif [[ "${pharmcatJar}" != "" && -f "${pharmcatJar}" ]]; then
      mkdir -p pharmcat
      java -jar "${pharmcatJar}" -vcf "$vcf" -o pharmcat > pharmcat/pharmcat.log 2>&1
      printf '%s\\t%s\\tcomplete\\tPharmCAT completed\\n' "${row_id}" "${sample}" >> "${row_id}.pharmcat_status.tsv"
    else
      printf '%s\\t%s\\tskipped\\tPharmCAT jar not configured; PGx not assessed\\n' "${row_id}" "${sample}" >> "${row_id}.pharmcat_status.tsv"
    fi
    """

    stub:
    """
    cp "$vcf" "${row_id}.annotated.vcf.gz" || touch "${row_id}.annotated.vcf.gz"
    printf 'chrom\\tpos\\tid\\tref\\talt\\tgt\\n' > "${row_id}.variant_summary.tsv"
    printf 'chrom\\tpos\\tid\\tref\\talt\\tgt\\n' > "${row_id}.clinvar.matches.tsv"
    printf 'row_id\\tsample\\tchrom\\tpos\\tid\\tref\\talt\\tsource\\tlabel\\tvalue\\tnote\\n' > "${row_id}.public_annotations.tsv"
    printf 'row_id\\tsample\\tstep\\tstate\\tmessage\\n%s\\t%s\\tstub\\tcomplete\\tstub\\n' "${row_id}" "${sample}" > "${row_id}.annotation_status.tsv"
    printf 'row_id\\tsample\\ttool\\tstate\\tconsequence\\tgene\\timpact\\tcount\\tnote\\n%s\\t%s\\tVEP/SnpEff\\tstub\\tnot_assessed\\t\\t\\t0\\tstub\\n' "${row_id}" "${sample}" > "${row_id}.consequence_summary.tsv"
    printf 'row_id\\tsample\\tstep\\tstate\\tmessage\\n%s\\t%s\\tconsequence\\tstub\\tstub\\n' "${row_id}" "${sample}" > "${row_id}.consequence_status.tsv"
    printf 'row_id\\tsample\\tstate\\tmessage\\n%s\\t%s\\tstub\\tPharmCAT stub\\n' "${row_id}" "${sample}" > "${row_id}.pharmcat_status.tsv"
    """
}

process COMPILE_VCF_REPORT {
    publishDir "${params.outdir}/report", mode: 'copy'

    input:
    path report_inputs

    output:
    path "report_index.html", emit: report_index
    path "open_genome_report.html", emit: report_html
    path "findings.tsv", emit: findings
    path "evidence.json", emit: evidence
    path "run_manifest.json", emit: run_manifest

    script:
    def clinvar = optionalPath(params.clinvar)
    def dbsnp = optionalPath(params.dbsnp)
    def gnomad = optionalPath(params.gnomad)
    def vepCache = optionalPath(params.vep_cache)
    def snpEffDb = optionalPath(params.snpeff_db)
    def pharmcatJar = optionalPath(params.pharmcat_jar)
    """
    python3 "${params.report_compiler}" \\
      --input-dir . \\
      --out-dir . \\
      --samplesheet "${params.samplesheet}" \\
      --reference "${params.fasta}" \\
      --clinvar "${clinvar}" \\
      --dbsnp "${dbsnp}" \\
      --gnomad "${gnomad}" \\
      --vep-cache "${vepCache}" \\
      --snpeff-db "${snpEffDb}" \\
      --pharmcat-jar "${pharmcatJar}"
    """

    stub:
    """
    printf '<html><body>OpenGenome VCF report stub</body></html>\\n' > report_index.html
    printf '<html><body>OpenGenome VCF report stub</body></html>\\n' > open_genome_report.html
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
            if (inputType != 'vcf') error "vcf-annotate accepts only input_type=vcf, found ${inputType ?: 'unset'} for ${sample}"
            def vcf = row.vcf?.toString()?.trim()
            if (!vcf) error "vcf row for ${sample} is missing vcf"
            tuple(sample, rowId, file(vcf))
        }
        .ifEmpty { error "samplesheet has no vcf rows" }
        .set { vcf_input_ch }

    NORMALIZE_EXISTING_VCF(vcf_input_ch)
    LOCAL_ANNOTATE_VCF(NORMALIZE_EXISTING_VCF.out.normalized_vcf)

    report_inputs_ch = NORMALIZE_EXISTING_VCF.out.bcftools_stats
        .mix(NORMALIZE_EXISTING_VCF.out.ingress_status)
        .mix(LOCAL_ANNOTATE_VCF.out.variant_tsv)
        .mix(LOCAL_ANNOTATE_VCF.out.clinvar_tsv)
        .mix(LOCAL_ANNOTATE_VCF.out.public_annotations)
        .mix(LOCAL_ANNOTATE_VCF.out.annotation_status)
        .mix(LOCAL_ANNOTATE_VCF.out.consequence_tsv)
        .mix(LOCAL_ANNOTATE_VCF.out.consequence_status)
        .mix(LOCAL_ANNOTATE_VCF.out.pharmcat_status)
        .collect()

    COMPILE_VCF_REPORT(report_inputs_ch)
}
