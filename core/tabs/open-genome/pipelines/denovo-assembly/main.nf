nextflow.enable.dsl = 2

def required(name, value) {
    if (value == null || value.toString().trim() == '') {
        error "Missing required parameter: ${name}"
    }
}

def normalizedMode(value, fallback) {
    def s = value == null ? '' : value.toString().trim().toLowerCase()
    return s ? s : fallback
}

def requireMode(name, value, allowed) {
    def mode = normalizedMode(value, '')
    if (!allowed.contains(mode)) {
        error "Invalid ${name}: ${value}. Expected one of: ${allowed.join(', ')}"
    }
    return mode
}

process STAGE_LONG_READS {
    tag { row_id }
    publishDir "${params.outdir}/reads", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(reads)

    output:
    tuple val(sample), val(row_id), path("${row_id}.reads.fastq.gz"), emit: reads

    script:
    """
    case "$reads" in
      *.bam)
        samtools fastq -@ ${task.cpus} "$reads" | pigz -p ${task.cpus} > "${row_id}.reads.fastq.gz"
        ;;
      *.gz)
        ln -s "$reads" "${row_id}.reads.fastq.gz"
        ;;
      *)
        pigz -c -p ${task.cpus} "$reads" > "${row_id}.reads.fastq.gz"
        ;;
    esac
    """

    stub:
    """
    printf '@read1\\nACGTACGTACGTACGTACGTACGTACGTACGT\\n+\\nIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\\n' | gzip -c > "${row_id}.reads.fastq.gz"
    """
}

process READ_SUMMARY {
    tag { row_id }
    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(reads)

    output:
    path "${row_id}.seqkit_stats.tsv", emit: summary

    script:
    """
    seqkit stats -T "$reads" > "${row_id}.seqkit_stats.tsv"
    """

    stub:
    """
    printf 'file\\tformat\\ttype\\tnum_seqs\\tsum_len\\tmin_len\\tavg_len\\tmax_len\\n%s\\tFASTQ\\tDNA\\t1\\t32\\t32\\t32.0\\t32\\n' "$reads" > "${row_id}.seqkit_stats.tsv"
    """
}

process HIFIASM_ASSEMBLE {
    tag { row_id }
    publishDir "${params.outdir}/assembly", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(reads)

    output:
    tuple val(sample), val(row_id), path("${row_id}.primary.fasta"), path("${row_id}.primary.gfa"), emit: assembly
    path "${row_id}.hifiasm.log", emit: hifiasm_log

    script:
    def platform = normalizedMode(params.long_read_platform, 'hifi')
    def platformArgs = platform == 'ont' ? '--ont' : ''
    """
    hifiasm -t ${task.cpus} ${platformArgs} -o "${row_id}" "$reads" > "${row_id}.hifiasm.log" 2>&1
    primary_gfa=""
    for candidate in "${row_id}.bp.p_ctg.gfa" "${row_id}.p_ctg.gfa" "${row_id}.bp.hap1.p_ctg.gfa" "${row_id}.asm.p_ctg.gfa"; do
      if [[ -s "\$candidate" ]]; then
        primary_gfa="\$candidate"
        break
      fi
    done
    if [[ -z "\$primary_gfa" ]]; then
      primary_gfa=\$(find . -maxdepth 1 -type f \\( -name "${row_id}*.p_ctg.gfa" -o -name "${row_id}*.ctg.gfa" \\) | sort | head -n 1 || true)
    fi
    if [[ -z "\$primary_gfa" ]]; then
      echo "hifiasm did not produce a primary contig GFA" >&2
      exit 1
    fi
    cp "\$primary_gfa" "${row_id}.primary.gfa"
    awk 'BEGIN { OFS="\\n" } /^S/ { print ">" \$2, \$3 }' "${row_id}.primary.gfa" > "${row_id}.primary.fasta"
    if [[ ! -s "${row_id}.primary.fasta" ]]; then
      echo "hifiasm GFA contained no contig sequence records" >&2
      exit 1
    fi
    """

    stub:
    """
    printf 'S\\tcontig_1\\tACGTACGTACGTACGTACGTACGTACGTACGT\\n' > "${row_id}.primary.gfa"
    printf '>contig_1\\nACGTACGTACGTACGTACGTACGTACGTACGT\\n' > "${row_id}.primary.fasta"
    printf 'hifiasm stub for %s\\n' "${row_id}" > "${row_id}.hifiasm.log"
    """
}

process FLYE_ASSEMBLE {
    tag { row_id }
    publishDir "${params.outdir}/assembly", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(reads)

    output:
    tuple val(sample), val(row_id), path("${row_id}.primary.fasta"), path("${row_id}.primary.gfa"), emit: assembly
    path "${row_id}.flye.log", emit: assembler_log

    script:
    def platform = normalizedMode(params.long_read_platform, 'hifi')
    def readType = normalizedMode(params.flye_read_type, 'auto')
    def readArg = readType == 'auto' ? (platform == 'ont' ? '--nano-hq' : '--pacbio-hifi') : "--${readType}"
    """
    flye ${readArg} "$reads" --out-dir "${row_id}.flye" --threads ${task.cpus} --genome-size "${params.genome_size}" > "${row_id}.flye.log" 2>&1
    cp "${row_id}.flye/assembly.fasta" "${row_id}.primary.fasta"
    if [[ -f "${row_id}.flye/assembly_graph.gfa" ]]; then
      cp "${row_id}.flye/assembly_graph.gfa" "${row_id}.primary.gfa"
    else
      awk 'BEGIN { OFS="\\t" } /^>/ { if (seq) { print "S", name, seq }; name=substr(\$0,2); seq=""; next } { seq=seq \$0 } END { if (seq) print "S", name, seq }' "${row_id}.primary.fasta" > "${row_id}.primary.gfa"
    fi
    """

    stub:
    """
    printf 'S\\tcontig_1\\tACGTACGTACGTACGTACGTACGTACGTACGT\\n' > "${row_id}.primary.gfa"
    printf '>contig_1\\nACGTACGTACGTACGTACGTACGTACGTACGT\\n' > "${row_id}.primary.fasta"
    printf 'Flye stub for %s\\n' "${row_id}" > "${row_id}.flye.log"
    """
}

process VERKKO_ASSEMBLE {
    tag { row_id }
    publishDir "${params.outdir}/assembly", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(reads)

    output:
    tuple val(sample), val(row_id), path("${row_id}.primary.fasta"), path("${row_id}.primary.gfa"), emit: assembly
    path "${row_id}.verkko.log", emit: assembler_log

    script:
    def platform = normalizedMode(params.long_read_platform, 'hifi')
    def readArg = platform == 'ont' ? '--nano' : '--hifi'
    def refGuide = params.reference_guide?.toString()?.trim() ? "--ref '${params.reference_guide}'" : ''
    """
    verkko -d "${row_id}.verkko" ${readArg} "$reads" ${refGuide} > "${row_id}.verkko.log" 2>&1
    cp "${row_id}.verkko/assembly.fasta" "${row_id}.primary.fasta"
    if [[ -f "${row_id}.verkko/assembly.homopolymer-compressed.gfa" ]]; then
      cp "${row_id}.verkko/assembly.homopolymer-compressed.gfa" "${row_id}.primary.gfa"
    else
      awk 'BEGIN { OFS="\\t" } /^>/ { if (seq) { print "S", name, seq }; name=substr(\$0,2); seq=""; next } { seq=seq \$0 } END { if (seq) print "S", name, seq }' "${row_id}.primary.fasta" > "${row_id}.primary.gfa"
    fi
    """

    stub:
    """
    printf 'S\\tcontig_1\\tACGTACGTACGTACGTACGTACGTACGTACGT\\n' > "${row_id}.primary.gfa"
    printf '>contig_1\\nACGTACGTACGTACGTACGTACGTACGTACGT\\n' > "${row_id}.primary.fasta"
    printf 'Verkko stub for %s\\n' "${row_id}" > "${row_id}.verkko.log"
    """
}

process ASSEMBLY_QC {
    tag { row_id }
    publishDir "${params.outdir}/assembly", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(primary_fasta), path(primary_gfa)

    output:
    path "${row_id}.gfastats.txt", emit: gfastats

    script:
    """
    gfastats "$primary_fasta" > "${row_id}.gfastats.txt"
    """

    stub:
    """
    printf 'scaffold count: 1\\ntotal scaffold length: 32\\nscaffold N50: 32\\nlongest scaffold: 32\\n' > "${row_id}.gfastats.txt"
    """
}

process ASSEMBLY_REVIEW {
    tag { row_id }
    publishDir "${params.outdir}/assembly", mode: 'copy'

    input:
    tuple val(sample), val(row_id), path(primary_fasta), path(primary_gfa), path(reads)

    output:
    path "${row_id}.circularity.tsv", emit: circularity
    path "${row_id}.read_density.tsv", emit: read_density_tsv
    path "${row_id}.read_density.svg", emit: read_density_plot
    path "${row_id}.assembly_graph.svg", emit: assembly_graph

    script:
    def preset = normalizedMode(params.long_read_platform, 'hifi') == 'ont' ? 'map-ont' : 'map-hifi'
    """
    python3 - "$row_id" "$primary_fasta" "$primary_gfa" <<'PY'
import math
import sys
from pathlib import Path

row_id = sys.argv[1]
fasta_path = Path(sys.argv[2])
gfa_path = Path(sys.argv[3])

def read_fasta(path):
    seqs = {}
    name = None
    chunks = []
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if name is not None:
                    seqs[name] = "".join(chunks).upper()
                name = line[1:].split()[0]
                chunks = []
            else:
                chunks.append(line)
    if name is not None:
        seqs[name] = "".join(chunks).upper()
    return seqs

def terminal_overlap(seq):
    if len(seq) < 16:
        return 0
    max_len = min(5000, len(seq) // 2)
    min_len = min(100, max(8, len(seq) // 10))
    for size in range(max_len, min_len - 1, -1):
        if seq[:size] == seq[-size:]:
            return size
    return 0

def graph_links(path):
    links = {}
    if not path.exists():
        return links
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.startswith("L\\t"):
                continue
            parts = line.rstrip("\\n").split("\\t")
            if len(parts) < 5:
                continue
            left, right = parts[1], parts[3]
            links[left] = links.get(left, 0) + 1
            links[right] = links.get(right, 0) + 1
    return links

seqs = read_fasta(fasta_path)
links = graph_links(gfa_path)

with Path(f"{row_id}.circularity.tsv").open("w", encoding="utf-8") as out:
    out.write("row_id\\tcontig\\tlength\\tcircularity\\tterminal_overlap_bp\\tevidence\\tnote\\n")
    for contig, seq in sorted(seqs.items(), key=lambda item: (-len(item[1]), item[0])):
        overlap = terminal_overlap(seq)
        link_count = links.get(contig, 0)
        if overlap:
            state = "review_circular"
            evidence = f"terminal_overlap_bp={overlap};gfa_links={link_count}"
            note = "Contig ends share sequence; inspect assembler graph and read support before interpreting as circular."
        elif link_count >= 2:
            state = "graph_connected"
            evidence = f"terminal_overlap_bp=0;gfa_links={link_count}"
            note = "GFA links touch this contig, but terminal sequence did not support a circular call."
        else:
            state = "linear_or_unresolved"
            evidence = f"terminal_overlap_bp=0;gfa_links={link_count}"
            note = "No conservative circularity signal from terminal overlap or GFA links."
        out.write(f"{row_id}\\t{contig}\\t{len(seq)}\\t{state}\\t{overlap}\\t{evidence}\\t{note}\\n")

with Path("assembly_windows.bed").open("w", encoding="utf-8") as out:
    for contig, seq in sorted(seqs.items(), key=lambda item: (-len(item[1]), item[0])):
        length = len(seq)
        if length <= 0:
            continue
        target_bins = 100
        window = max(1, math.ceil(length / target_bins))
        for start in range(0, length, window):
            end = min(length, start + window)
            out.write(f"{contig}\\t{start}\\t{end}\\n")
PY

    minimap2 -t ${task.cpus} -ax ${preset} "$primary_fasta" "$reads" \\
      | samtools sort -@ ${task.cpus} -o "${row_id}.assembly_support.bam" -
    samtools index "${row_id}.assembly_support.bam"
    samtools bedcov assembly_windows.bed "${row_id}.assembly_support.bam" > "${row_id}.read_density.raw.tsv"

    python3 - "$row_id" "$primary_fasta" "$primary_gfa" "${row_id}.read_density.raw.tsv" <<'PY'
import html
import sys
from pathlib import Path

row_id = sys.argv[1]
fasta_path = Path(sys.argv[2])
gfa_path = Path(sys.argv[3])
raw_density = Path(sys.argv[4])

def read_fasta_lengths(path):
    lengths = {}
    name = None
    current = 0
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if name is not None:
                    lengths[name] = current
                name = line[1:].split()[0]
                current = 0
            else:
                current += len(line)
    if name is not None:
        lengths[name] = current
    return lengths

def read_circular_states(path):
    states = {}
    if not path.exists():
        return states
    with path.open("r", encoding="utf-8") as handle:
        next(handle, None)
        for line in handle:
            fields = line.rstrip("\\n").split("\\t")
            if len(fields) >= 4:
                states[fields[1]] = fields[3]
    return states

def read_links(path):
    links = []
    if not path.exists():
        return links
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.startswith("L\\t"):
                continue
            fields = line.rstrip("\\n").split("\\t")
            if len(fields) >= 5:
                links.append((fields[1], fields[3]))
    return links

lengths = read_fasta_lengths(fasta_path)
states = read_circular_states(Path(f"{row_id}.circularity.tsv"))
links = read_links(gfa_path)

density_rows = []
with raw_density.open("r", encoding="utf-8", errors="replace") as handle:
    for line in handle:
        fields = line.rstrip("\\n").split("\\t")
        if len(fields) < 4:
            continue
        contig, start, end, bases = fields[0], int(fields[1]), int(fields[2]), float(fields[3])
        width = max(1, end - start)
        density_rows.append((contig, start, end, bases / width))

with Path(f"{row_id}.read_density.tsv").open("w", encoding="utf-8") as out:
    out.write("contig\\twindow_start\\twindow_end\\tmean_depth\\n")
    for contig, start, end, mean_depth in density_rows:
        out.write(f"{contig}\\t{start}\\t{end}\\t{mean_depth:.4f}\\n")

plot_rows = density_rows[:1000]
max_depth = max((row[3] for row in plot_rows), default=0.0) or 1.0
contig_order = [name for name, _ in sorted(lengths.items(), key=lambda item: (-item[1], item[0]))][:6]
contig_y = {name: 64 + idx * 52 for idx, name in enumerate(contig_order)}
width = 920
height = max(220, 110 + len(contig_order) * 52)
left = 150
right = width - 36
usable = right - left

svg = [
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-label="Assembly read density">',
    '<rect width="100%" height="100%" fill="#fbfcfc"/>',
    '<text x="24" y="34" font-family="sans-serif" font-size="20" fill="#172026">Assembly read density</text>',
    '<text x="24" y="56" font-family="sans-serif" font-size="12" fill="#5d6a72">Long reads aligned back to assembled contigs; bars show mean depth per contig window.</text>',
]
for contig in contig_order:
    y = contig_y[contig]
    length = max(1, lengths[contig])
    svg.append(f'<text x="24" y="{y + 4}" font-family="sans-serif" font-size="12" fill="#172026">{html.escape(contig[:28])}</text>')
    svg.append(f'<line x1="{left}" y1="{y}" x2="{right}" y2="{y}" stroke="#d4dbe3" stroke-width="10" stroke-linecap="round"/>')
    for row_contig, start, end, depth in plot_rows:
        if row_contig != contig:
            continue
        x1 = left + usable * (start / length)
        x2 = left + usable * (end / length)
        bar_height = max(3, min(42, 42 * (depth / max_depth)))
        svg.append(f'<rect x="{x1:.1f}" y="{y - bar_height:.1f}" width="{max(1.0, x2 - x1):.1f}" height="{bar_height:.1f}" fill="#196b69" opacity="0.82"/>')
    svg.append(f'<text x="{right - 70}" y="{y + 24}" font-family="sans-serif" font-size="11" fill="#5d6a72">{length:,} bp</text>')
svg.append(f'<text x="24" y="{height - 18}" font-family="sans-serif" font-size="11" fill="#5d6a72">Max window mean depth: {max_depth:.2f}</text>')
svg.append('</svg>')
Path(f"{row_id}.read_density.svg").write_text("\\n".join(svg) + "\\n", encoding="utf-8")

graph_order = contig_order[:8]
graph_width = 920
graph_height = max(260, 120 + len(graph_order) * 64)
graph_svg = [
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{graph_width}" height="{graph_height}" viewBox="0 0 {graph_width} {graph_height}" role="img" aria-label="Assembly graph preview">',
    '<rect width="100%" height="100%" fill="#fbfcfc"/>',
    '<text x="24" y="34" font-family="sans-serif" font-size="20" fill="#172026">Assembly graph preview</text>',
    '<text x="24" y="56" font-family="sans-serif" font-size="12" fill="#5d6a72">Contig sketch from primary GFA plus conservative circularity review.</text>',
]
node_pos = {}
for idx, contig in enumerate(graph_order):
    y = 102 + idx * 58
    state = states.get(contig, "linear_or_unresolved")
    node_pos[contig] = (250, y)
    color = "#196b69" if state == "review_circular" else "#7a4f12" if state == "graph_connected" else "#4f6673"
    if state == "review_circular":
        graph_svg.append(f'<circle cx="250" cy="{y}" r="21" fill="none" stroke="{color}" stroke-width="8"/>')
    else:
        graph_svg.append(f'<line x1="210" y1="{y}" x2="290" y2="{y}" stroke="{color}" stroke-width="10" stroke-linecap="round"/>')
    graph_svg.append(f'<text x="322" y="{y + 4}" font-family="sans-serif" font-size="13" fill="#172026">{html.escape(contig[:44])}</text>')
    graph_svg.append(f'<text x="650" y="{y + 4}" font-family="sans-serif" font-size="12" fill="#5d6a72">{lengths.get(contig, 0):,} bp · {html.escape(state)}</text>')
for left_contig, right_contig in links[:40]:
    if left_contig not in node_pos or right_contig not in node_pos or left_contig == right_contig:
        continue
    x1, y1 = node_pos[left_contig]
    x2, y2 = node_pos[right_contig]
    graph_svg.append(f'<path d="M{x1 + 46},{y1} C430,{y1} 430,{y2} {x2 - 46},{y2}" fill="none" stroke="#99a7b3" stroke-width="2"/>')
graph_svg.append(f'<text x="24" y="{graph_height - 18}" font-family="sans-serif" font-size="11" fill="#5d6a72">Circular labels are review signals, not automatic biological interpretation.</text>')
graph_svg.append('</svg>')
Path(f"{row_id}.assembly_graph.svg").write_text("\\n".join(graph_svg) + "\\n", encoding="utf-8")
PY
    """

    stub:
    """
    printf 'row_id\\tcontig\\tlength\\tcircularity\\tterminal_overlap_bp\\tevidence\\tnote\\n%s\\tcontig_1\\t32\\tlinear_or_unresolved\\t0\\tterminal_overlap_bp=0;gfa_links=0\\tstub review\\n' "${row_id}" > "${row_id}.circularity.tsv"
    printf 'contig\\twindow_start\\twindow_end\\tmean_depth\\ncontig_1\\t0\\t32\\t1.0000\\n' > "${row_id}.read_density.tsv"
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="120"><text x="16" y="32">Assembly read density</text><rect x="16" y="64" width="240" height="16" fill="#196b69"/></svg>\\n' > "${row_id}.read_density.svg"
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="120"><text x="16" y="32">Assembly graph preview</text><line x1="16" y1="72" x2="256" y2="72" stroke="#4f6673" stroke-width="8"/></svg>\\n' > "${row_id}.assembly_graph.svg"
    """
}

process COMPILE_DENOVO_REPORT {
    publishDir "${params.outdir}/report", mode: 'copy'

    input:
    path report_inputs

    output:
    path "denovo_assembly_report.html", emit: report_html
    path "denovo_assembly_summary.tsv", emit: summary_tsv
    path "denovo_assembly_manifest.json", emit: manifest_json

    script:
    """
    python3 - <<'PY'
import html
import json
from pathlib import Path

def fasta_lengths(path):
    lengths = []
    current = 0
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if line.startswith(">"):
                if current:
                    lengths.append(current)
                current = 0
            else:
                current += len(line.strip())
    if current:
        lengths.append(current)
    return lengths

def n50(lengths):
    if not lengths:
        return 0
    total = sum(lengths)
    running = 0
    for value in sorted(lengths, reverse=True):
        running += value
        if running >= total / 2:
            return value
    return 0

rows = []
for fasta in sorted(Path(".").glob("*.primary.fasta")):
    row_id = fasta.name.removesuffix(".primary.fasta")
    lengths = fasta_lengths(fasta)
    gfa = Path(f"{row_id}.primary.gfa")
    stats = Path(f"{row_id}.gfastats.txt")
    circularity = Path(f"{row_id}.circularity.tsv")
    read_density = Path(f"{row_id}.read_density.tsv")
    read_density_plot = Path(f"{row_id}.read_density.svg")
    assembly_graph = Path(f"{row_id}.assembly_graph.svg")
    log = next((p for p in [Path(f"{row_id}.hifiasm.log"), Path(f"{row_id}.flye.log"), Path(f"{row_id}.verkko.log")] if p.exists()), None)
    read_stats = Path(f"{row_id}.seqkit_stats.tsv")
    circular_count = 0
    if circularity.exists():
        with circularity.open("r", encoding="utf-8", errors="replace") as handle:
            next(handle, None)
            for line in handle:
                fields = line.rstrip("\\n").split("\\t")
                if len(fields) >= 4 and fields[3] == "review_circular":
                    circular_count += 1
    rows.append({
        "row_id": row_id,
        "assembler": "${params.assembler}",
        "platform": "${params.long_read_platform}",
        "contigs": len(lengths),
        "total_bases": sum(lengths),
        "n50": n50(lengths),
        "longest_contig": max(lengths) if lengths else 0,
        "circular_contigs": circular_count,
        "primary_fasta": f"../assembly/{fasta.name}",
        "primary_gfa": f"../assembly/{gfa.name}" if gfa.exists() else "",
        "gfastats": f"../assembly/{stats.name}" if stats.exists() else "",
        "hifiasm_log": f"../assembly/{log.name}" if log else "",
        "read_summary": f"../qc/{read_stats.name}" if read_stats.exists() else "",
        "circularity": f"../assembly/{circularity.name}" if circularity.exists() else "",
        "read_density": f"../assembly/{read_density.name}" if read_density.exists() else "",
        "read_density_plot": f"../assembly/{read_density_plot.name}" if read_density_plot.exists() else "",
        "assembly_graph": f"../assembly/{assembly_graph.name}" if assembly_graph.exists() else "",
    })

with open("denovo_assembly_summary.tsv", "w", encoding="utf-8") as out:
    out.write("row_id\\tassembler\\tplatform\\tcontigs\\ttotal_bases\\tn50\\tlongest_contig\\tcircular_contigs\\tprimary_fasta\\tprimary_gfa\\tgfastats\\thifiasm_log\\tread_summary\\tcircularity\\tread_density\\tread_density_plot\\tassembly_graph\\n")
    for row in rows:
        out.write("\\t".join(str(row[key]) for key in ("row_id", "assembler", "platform", "contigs", "total_bases", "n50", "longest_contig", "circular_contigs", "primary_fasta", "primary_gfa", "gfastats", "hifiasm_log", "read_summary", "circularity", "read_density", "read_density_plot", "assembly_graph")) + "\\n")

manifest = {
    "pipeline": "denovo-assembly",
    "assembler": "${params.assembler}",
    "platform": "${params.long_read_platform}",
    "reference_guide": "${params.reference_guide}",
    "summary": rows,
}
Path("denovo_assembly_manifest.json").write_text(json.dumps(manifest, indent=2) + "\\n", encoding="utf-8")

def tsv_preview(path, limit=8):
    source = Path(path)
    if not source.exists():
        source = Path(Path(path).name)
    if not source.exists():
        return ""
    rows = []
    with source.open("r", encoding="utf-8", errors="replace") as handle:
        header = handle.readline().rstrip("\\n").split("\\t")
        for idx, line in enumerate(handle):
            if idx >= limit:
                break
            rows.append(line.rstrip("\\n").split("\\t"))
    if not header:
        return ""
    head = "".join(f"<th>{html.escape(value)}</th>" for value in header)
    body = "".join(
        "<tr>" + "".join(f"<td>{html.escape(value)}</td>" for value in row) + "</tr>"
        for row in rows
    )
    return f"<table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table>"

def artifact_link(title, href, desc):
    if not href:
        return ""
    return f'<a href="{html.escape(href)}"><strong>{html.escape(title)}</strong><br>{html.escape(desc)}</a>'

def visual_preview(title, href, desc):
    if not href:
        return ""
    return (
        f'<figure class="visual-panel">'
        f'<h3>{html.escape(title)}</h3>'
        f'<a href="{html.escape(href)}"><img src="{html.escape(href)}" alt="{html.escape(title)}"></a>'
        f'<figcaption>{html.escape(desc)}</figcaption>'
        f'</figure>'
    )

cards = []
for row in rows:
    artifact_links = "".join([
        artifact_link("Primary FASTA", row.get("primary_fasta", ""), "Assembled contig sequences."),
        artifact_link("Primary GFA", row.get("primary_gfa", ""), "Assembly graph from the assembler."),
        artifact_link("Circularity TSV", row.get("circularity", ""), "Terminal-overlap and graph-link review table."),
        artifact_link("Read density TSV", row.get("read_density", ""), "Per-window long-read support depths."),
        artifact_link("gfastats output", row.get("gfastats", ""), "Raw continuity metrics."),
        artifact_link("Assembler log", row.get("hifiasm_log", ""), "Assembler runtime messages."),
    ])
    visual_panels = "".join([
        visual_preview("Read density", row.get("read_density_plot", ""), "Long reads aligned back to assembled contigs; bars show mean depth by contig window."),
        visual_preview("Assembly graph", row.get("assembly_graph", ""), "Primary GFA sketch with conservative circularity review signals."),
    ])
    circular_table = tsv_preview(row.get("circularity", ""))
    cards.append(f'''
      <section class="sample">
        <h2>{html.escape(row['row_id'])}</h2>
        <p><strong>Assembler:</strong> {html.escape(row['assembler'])} · <strong>Platform:</strong> {html.escape(row['platform'])}</p>
        <dl>
          <div><dt>Contigs</dt><dd>{row['contigs']}</dd></div>
          <div><dt>Total assembled bases</dt><dd>{row['total_bases']:,}</dd></div>
          <div><dt>N50</dt><dd>{row['n50']:,}</dd></div>
          <div><dt>Longest contig</dt><dd>{row['longest_contig']:,}</dd></div>
          <div><dt>Circular review hits</dt><dd>{row['circular_contigs']}</dd></div>
        </dl>
        <p>The FASTA is the assembled sequence. The GFA keeps the assembly graph, which is useful when checking repeats, bubbles, and unresolved regions.</p>
        <h3>Assembly review visuals</h3>
        <div class="visual-grid">{visual_panels}</div>
        <h3>Circularity review</h3>
        {circular_table if circular_table else '<p class="empty">No circularity table was generated.</p>'}
        <h3>Assembly review artifacts</h3>
        <div class="artifact-grid">{artifact_links}</div>
      </section>
    ''')

html_doc = f'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Open Genome De Novo Assembly Report</title>
  <style>
    :root {{ color-scheme: light dark; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
    body {{ margin: 0; background: #f7f8fa; color: #1c2024; }}
    main {{ max-width: 1120px; margin: 0 auto; padding: 32px 20px 48px; }}
    h1 {{ margin: 0 0 8px; font-size: clamp(2rem, 5vw, 3.2rem); line-height: 1.05; }}
    h2 {{ margin-top: 0; }}
    .lede {{ max-width: 820px; color: #4a515c; font-size: 1.05rem; line-height: 1.6; }}
	    .sample {{ margin-top: 22px; padding: 20px; border: 1px solid #d9dee7; border-radius: 8px; background: white; }}
	    .artifact-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 12px; margin: 18px 0; }}
	    .artifact-grid a {{ display: block; padding: 12px; border: 1px solid #d9dee7; border-radius: 8px; color: inherit; text-decoration: none; }}
	    .visual-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); gap: 14px; margin: 14px 0 20px; }}
	    .visual-panel {{ margin: 0; border: 1px solid #d9dee7; border-radius: 8px; background: #fbfcfe; overflow: hidden; }}
	    .visual-panel h3 {{ margin: 0; padding: 12px 14px 0; }}
	    .visual-panel img {{ display: block; width: 100%; height: auto; }}
	    .visual-panel figcaption {{ padding: 10px 14px 12px; color: #65707f; border-top: 1px solid #d9dee7; }}
	    dl {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 12px; margin: 18px 0; }}
	    dt {{ color: #65707f; font-size: 0.82rem; }}
	    dd {{ margin: 4px 0 0; font-size: 1.45rem; font-weight: 700; }}
	    table {{ border-collapse: collapse; width: 100%; margin: 12px 0 20px; font-size: 0.92rem; }}
	    th, td {{ border: 1px solid #d9dee7; padding: 0.48rem 0.55rem; text-align: left; vertical-align: top; }}
	    th {{ background: #f1f4f7; }}
	    .empty {{ margin: 12px 0 20px; padding: 12px; border: 1px solid #d9dee7; border-radius: 8px; background: #f7f8fa; color: #65707f; }}
	    .note {{ margin-top: 24px; padding: 16px 18px; border-left: 4px solid #2b6cb0; background: #edf5ff; color: #20364f; }}
	    @media (max-width: 640px) {{
	      main {{ padding: 22px 14px 42px; }}
	      .sample {{ padding: 16px; }}
	      .visual-grid {{ grid-template-columns: 1fr; }}
	      table {{ display: block; overflow-x: auto; }}
	    }}
	    @media (prefers-color-scheme: dark) {{
	      body {{ background: #111417; color: #eef1f5; }}
	      .lede {{ color: #bac4cf; }}
	      .sample {{ background: #171b20; border-color: #2d3642; }}
	      .visual-panel {{ background: #171b20; border-color: #2d3642; }}
	      .visual-panel figcaption {{ border-top-color: #2d3642; color: #aab5c2; }}
	      th {{ background: #202730; }}
	      th, td {{ border-color: #2d3642; }}
	      .empty {{ background: #171b20; border-color: #2d3642; color: #aab5c2; }}
	      dt {{ color: #aab5c2; }}
	      .note {{ background: #162433; color: #d8e9ff; }}
	    }}
  </style>
</head>
<body>
  <main>
    <h1>De Novo Assembly Report</h1>
    <p class="lede">This report summarizes a local long-read assembly. Open Genome supports hifiasm for PacBio HiFi and modern ONT modes, Flye for broad long-read assembly, and Verkko for high-end T2T-style accurate-long-read plus ultra-long ONT assembly. Use this report to inspect assembly size, contiguity, and output files before deeper quality checks such as BUSCO, QUAST, Merqury, or reference alignment.</p>
    {''.join(cards) if cards else '<section class="sample"><h2>No assemblies found</h2><p>The pipeline completed without a primary FASTA in the report inputs.</p></section>'}
    <div class="note">N50 is a contiguity metric, not a health or ancestry result. Higher is often better for assemblies, but coverage, read quality, contamination, and collapsed repeats still need review.</div>
  </main>
</body>
</html>
'''
Path("denovo_assembly_report.html").write_text(html_doc, encoding="utf-8")
PY
    """

    stub:
    """
    printf 'row_id\\tassembler\\tplatform\\tcontigs\\ttotal_bases\\tn50\\tlongest_contig\\tcircular_contigs\\tprimary_fasta\\tprimary_gfa\\tgfastats\\thifiasm_log\\tread_summary\\tcircularity\\tread_density\\tread_density_plot\\tassembly_graph\\n' > denovo_assembly_summary.tsv
    printf 'toy_long_reads\\t%s\\t%s\\t1\\t32\\t32\\t32\\t0\\t../assembly/toy_long_reads.primary.fasta\\t../assembly/toy_long_reads.primary.gfa\\t../assembly/toy_long_reads.gfastats.txt\\t../assembly/toy_long_reads.hifiasm.log\\t../qc/toy_long_reads.seqkit_stats.tsv\\t../assembly/toy_long_reads.circularity.tsv\\t../assembly/toy_long_reads.read_density.tsv\\t../assembly/toy_long_reads.read_density.svg\\t../assembly/toy_long_reads.assembly_graph.svg\\n' "${params.assembler}" "${params.long_read_platform}" >> denovo_assembly_summary.tsv
    printf '{"pipeline":"denovo-assembly","assembler":"%s","platform":"%s","summary":[{"row_id":"toy_long_reads","read_density_plot":"../assembly/toy_long_reads.read_density.svg","assembly_graph":"../assembly/toy_long_reads.assembly_graph.svg","circularity":"../assembly/toy_long_reads.circularity.tsv"}]}\\n' "${params.assembler}" "${params.long_read_platform}" > denovo_assembly_manifest.json
    cat > denovo_assembly_report.html <<'HTML'
<!doctype html>
<html>
<body>
<h1>De Novo Assembly Report</h1>
<h3>Assembly review visuals</h3>
<figure class="visual-panel"><img src="../assembly/toy_long_reads.read_density.svg" alt="Read density"></figure>
<figure class="visual-panel"><img src="../assembly/toy_long_reads.assembly_graph.svg" alt="Assembly graph"></figure>
<h3>Circularity review</h3>
<table><tr><th>contig</th><th>circularity</th></tr><tr><td>contig_1</td><td>linear_or_unresolved</td></tr></table>
<h3>Assembly review artifacts</h3>
<a href="../assembly/toy_long_reads.circularity.tsv">Circularity table</a>
<a href="../assembly/toy_long_reads.read_density.svg">Read density plot</a>
<a href="../assembly/toy_long_reads.assembly_graph.svg">Assembly graph preview</a>
</body>
</html>
HTML
    """
}

workflow {
    required('samplesheet', params.samplesheet)
    assembler_mode = requireMode('assembler', params.assembler, ['hifiasm', 'flye', 'verkko'])
    requireMode('long_read_platform', params.long_read_platform, ['hifi', 'ont', 'hybrid'])
    requireMode('flye_read_type', params.flye_read_type, ['auto', 'pacbio-hifi', 'pacbio-corr', 'pacbio-raw', 'nano-hq', 'nano-corr', 'nano-raw'])

    Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true)
        .filter { row -> row.input_type?.toString()?.trim() == 'long_reads' }
        .map { row ->
            def sample = row.sample?.toString()?.trim()
            def rowId = row.row_id?.toString()?.trim() ?: sample
            def reads = row.long_reads?.toString()?.trim()
            if (!sample) error "long-read row is missing sample"
            if (!rowId) error "long-read row for ${sample} is missing row_id"
            if (!reads) error "long-read row for ${sample} is missing long_reads"
            tuple(sample, rowId, file(reads))
        }
        .ifEmpty { error "samplesheet has no long_reads rows; import PacBio HiFi or ONT long-read files first" }
        .set { long_reads_ch }

    STAGE_LONG_READS(long_reads_ch)
    READ_SUMMARY(STAGE_LONG_READS.out.reads)

    if (assembler_mode == 'hifiasm') {
        HIFIASM_ASSEMBLE(STAGE_LONG_READS.out.reads)
        assembly_ch = HIFIASM_ASSEMBLE.out.assembly
        assembler_log_ch = HIFIASM_ASSEMBLE.out.hifiasm_log
    } else if (assembler_mode == 'flye') {
        FLYE_ASSEMBLE(STAGE_LONG_READS.out.reads)
        assembly_ch = FLYE_ASSEMBLE.out.assembly
        assembler_log_ch = FLYE_ASSEMBLE.out.assembler_log
    } else {
        VERKKO_ASSEMBLE(STAGE_LONG_READS.out.reads)
        assembly_ch = VERKKO_ASSEMBLE.out.assembly
        assembler_log_ch = VERKKO_ASSEMBLE.out.assembler_log
    }

    ASSEMBLY_QC(assembly_ch)

    assembly_review_input_ch = assembly_ch
        .map { sample, row_id, fasta, gfa -> tuple(row_id, sample, fasta, gfa) }
        .join(STAGE_LONG_READS.out.reads.map { sample, row_id, reads -> tuple(row_id, reads) })
        .map { row_id, sample, fasta, gfa, reads -> tuple(sample, row_id, fasta, gfa, reads) }
    ASSEMBLY_REVIEW(assembly_review_input_ch)

    primary_fasta_ch = assembly_ch.map { sample, row_id, fasta, gfa -> fasta }
    primary_gfa_ch = assembly_ch.map { sample, row_id, fasta, gfa -> gfa }

    report_inputs_ch = READ_SUMMARY.out.summary
        .mix(assembler_log_ch)
        .mix(primary_fasta_ch)
        .mix(primary_gfa_ch)
        .mix(ASSEMBLY_QC.out.gfastats)
        .mix(ASSEMBLY_REVIEW.out.circularity)
        .mix(ASSEMBLY_REVIEW.out.read_density_tsv)
        .mix(ASSEMBLY_REVIEW.out.read_density_plot)
        .mix(ASSEMBLY_REVIEW.out.assembly_graph)
        .collect()

    COMPILE_DENOVO_REPORT(report_inputs_ch)
}
