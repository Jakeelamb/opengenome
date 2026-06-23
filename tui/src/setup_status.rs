use crate::theme::Theme;
use ratatui::{
    prelude::*,
    symbols::border,
    widgets::{Block, Padding, Paragraph, Wrap},
};
use std::{
    collections::HashMap,
    env, fs,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

const REFRESH_INTERVAL: Duration = Duration::from_secs(2);
const CHECKLIST_HEIGHT: u16 = 10;

pub struct SetupChecklist {
    status: ChecklistStatus,
    last_refresh: Instant,
}

#[derive(Default)]
struct ChecklistStatus {
    ready: usize,
    total: usize,
    rows: Vec<ChecklistRow>,
}

struct ChecklistRow {
    label: &'static str,
    state: ChecklistState,
    value: String,
    next: &'static str,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum ChecklistState {
    Ready,
    Missing,
    Info,
}

impl SetupChecklist {
    pub fn new() -> Self {
        Self {
            status: load_status(),
            last_refresh: Instant::now(),
        }
    }

    pub fn preferred_height(&self, area: Rect) -> u16 {
        if area.height >= 18 {
            CHECKLIST_HEIGHT
        } else {
            0
        }
    }

    pub fn draw(&mut self, frame: &mut Frame, area: Rect, theme: &Theme) {
        self.refresh_if_needed();

        let block = Block::bordered()
            .border_set(border::PLAIN)
            .border_style(Style::default().fg(theme.unfocused_color()))
            .title(format!(
                " SETUP CHECKLIST {}/{} ",
                self.status.ready, self.status.total
            ))
            .title_style(Style::default().fg(theme.tab_color()).bold())
            .padding(Padding::horizontal(1));
        let inner_width = block.inner(area).width as usize;
        let lines = self
            .status
            .rows
            .iter()
            .map(|row| row.render(theme, inner_width))
            .collect::<Vec<_>>();

        frame.render_widget(
            Paragraph::new(Text::from(lines))
                .block(block)
                .wrap(Wrap { trim: true }),
            area,
        );
    }

    fn refresh_if_needed(&mut self) {
        if self.last_refresh.elapsed() >= REFRESH_INTERVAL {
            self.status = load_status();
            self.last_refresh = Instant::now();
        }
    }
}

impl ChecklistRow {
    fn ready(label: &'static str, value: impl Into<String>) -> Self {
        Self {
            label,
            state: ChecklistState::Ready,
            value: value.into(),
            next: "",
        }
    }

    fn missing(label: &'static str, value: impl Into<String>, next: &'static str) -> Self {
        Self {
            label,
            state: ChecklistState::Missing,
            value: value.into(),
            next,
        }
    }

    fn info(label: &'static str, value: impl Into<String>) -> Self {
        Self {
            label,
            state: ChecklistState::Info,
            value: value.into(),
            next: "",
        }
    }

    fn render(&self, theme: &Theme, width: usize) -> Line<'static> {
        let marker = match self.state {
            ChecklistState::Ready => "[x]",
            ChecklistState::Missing => "[ ]",
            ChecklistState::Info => "[-]",
        };
        let marker_style = match self.state {
            ChecklistState::Ready => Style::default().fg(theme.success_color()).bold(),
            ChecklistState::Missing => Style::default().fg(theme.fail_color()).bold(),
            ChecklistState::Info => Style::default().fg(theme.unfocused_color()),
        };
        let label_width = 14usize;
        let prefix_width = marker.len() + 1 + label_width + 2;
        let value_width = width.saturating_sub(prefix_width).max(12);
        let detail = if self.state == ChecklistState::Missing && self.value.is_empty() {
            self.next.to_string()
        } else if self.state == ChecklistState::Missing && !self.next.is_empty() {
            format!("{} | {}", self.value, self.next)
        } else {
            self.value.clone()
        };
        let detail_style = match self.state {
            ChecklistState::Ready => Style::default().fg(theme.cmd_color()),
            ChecklistState::Missing => Style::default().fg(theme.unfocused_color()),
            ChecklistState::Info => Style::default().fg(theme.unfocused_color()),
        };

        Line::from(vec![
            Span::styled(marker.to_string(), marker_style),
            Span::raw(" "),
            Span::styled(
                format!("{:<label_width$}", self.label),
                Style::default().fg(theme.tab_color()).bold(),
            ),
            Span::raw("  "),
            Span::styled(compact(&detail, value_width), detail_style),
        ])
    }
}

fn load_status() -> ChecklistStatus {
    let manifest = read_manifest();
    let mut rows = Vec::new();

    if let Some(conda) = resolve_conda(&manifest) {
        rows.push(ChecklistRow::ready("Conda", conda));
    } else {
        rows.push(ChecklistRow::missing(
            "Conda",
            "",
            "Start Here -> Install or update local tools",
        ));
    }

    let dataset = first_value(&manifest, &["paths.dataset", "sample.input_dir"]);
    rows.push(path_row(
        "Sequencing",
        &dataset,
        PathKind::DirOrFile,
        "Start Here -> Choose sequencing files",
    ));

    let output = first_value(&manifest, &["workflow.outdir", "paths.workdir"]);
    rows.push(path_row(
        "Output",
        &output,
        PathKind::Directory,
        "Start Here -> Choose results folder",
    ));

    let cores = first_value(&manifest, &["paths.threads"]);
    rows.push(ChecklistRow::info(
        "Cores",
        if cores.is_empty() {
            "default available CPUs".to_string()
        } else {
            format!("limit {cores}")
        },
    ));

    let samplesheet = first_value(&manifest, &["sample.samplesheet"]);
    rows.push(path_row(
        "Samplesheet",
        &samplesheet,
        PathKind::File,
        "Start Here -> Choose sequencing files",
    ));

    rows.push(ChecklistRow::info(
        "Plan",
        analysis_plan(&samplesheet, &manifest),
    ));

    let reference = first_value(&manifest, &["reference.fasta", "paths.reference"]);
    rows.push(path_row(
        "Reference",
        &reference,
        PathKind::DirOrFile,
        "Start Here -> Choose reference genome",
    ));

    let report = first_value(
        &manifest,
        &["results.report_html", "results.denovo_report_html"],
    );
    if report.is_empty() {
        rows.push(ChecklistRow::info("Report", "not generated yet"));
    } else {
        rows.push(path_row(
            "Report",
            &report,
            PathKind::File,
            "Results -> Open my report",
        ));
    }

    let total = rows
        .iter()
        .filter(|row| row.state != ChecklistState::Info)
        .count();
    let ready = rows
        .iter()
        .filter(|row| row.state == ChecklistState::Ready)
        .count();

    ChecklistStatus { ready, total, rows }
}

#[derive(Clone, Copy)]
enum PathKind {
    File,
    Directory,
    DirOrFile,
}

fn path_row(label: &'static str, value: &str, kind: PathKind, next: &'static str) -> ChecklistRow {
    if value.trim().is_empty() {
        return ChecklistRow::missing(label, "", next);
    }
    let path = Path::new(value).expand_home();
    let ok = match kind {
        PathKind::File => path.is_file(),
        PathKind::Directory => path.is_dir(),
        PathKind::DirOrFile => path.exists(),
    };
    if ok {
        ChecklistRow::ready(label, value)
    } else {
        ChecklistRow::missing(label, value, next)
    }
}

fn read_manifest() -> HashMap<String, String> {
    let path = user_manifest_path();
    let Ok(text) = fs::read_to_string(path) else {
        return HashMap::new();
    };
    parse_manifest(&text)
}

fn user_manifest_path() -> PathBuf {
    if let Some(dir) = env::var_os("OPEN_GENOME_CONFIG_DIR") {
        return PathBuf::from(dir).join("manifest.toml");
    }
    let config_home = env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
        .unwrap_or_else(|| PathBuf::from("."));
    config_home.join("open-genome").join("manifest.toml")
}

fn parse_manifest(text: &str) -> HashMap<String, String> {
    let mut section = String::new();
    let mut values = HashMap::new();

    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with("[[") {
            section.clear();
            continue;
        }
        if let Some(name) = line.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
            section = name.trim().to_string();
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        if section.is_empty() {
            continue;
        }
        values.insert(
            format!("{}.{}", section, key.trim()),
            unquote(value.trim()).to_string(),
        );
    }
    values
}

fn unquote(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.len() >= 2 && trimmed.starts_with('"') && trimmed.ends_with('"') {
        trimmed[1..trimmed.len() - 1]
            .replace("\\\"", "\"")
            .replace("\\\\", "\\")
    } else {
        trimmed.to_string()
    }
}

fn first_value(values: &HashMap<String, String>, keys: &[&str]) -> String {
    keys.iter()
        .find_map(|key| {
            let value = values.get(*key)?.trim();
            (!value.is_empty()).then(|| value.to_string())
        })
        .unwrap_or_default()
}

fn resolve_conda(values: &HashMap<String, String>) -> Option<String> {
    if let Some(configured) = values.get("conda.conda_exe") {
        let path = PathBuf::from(configured).expand_home();
        if is_executable(&path) {
            return Some(configured.clone());
        }
    }
    find_on_path("conda").or_else(|| find_on_path("mamba"))
}

fn analysis_plan(samplesheet: &str, manifest: &HashMap<String, String>) -> String {
    if samplesheet.trim().is_empty() || !Path::new(samplesheet).expand_home().is_file() {
        let saved_plan = first_value(manifest, &["sample.recommended_plan"]);
        if !saved_plan.is_empty() {
            return saved_plan;
        }
        let input_type = first_value(manifest, &["sample.input_type"]);
        if input_type.is_empty() {
            return "choose sequencing files".to_string();
        }
        return format!("{input_type}: choose sequencing files again if wrong");
    }

    let Ok(text) = fs::read_to_string(Path::new(samplesheet).expand_home()) else {
        return "samplesheet unreadable".to_string();
    };
    let mut headers: Vec<&str> = Vec::new();
    let mut counts: HashMap<String, usize> = HashMap::new();
    let mut long_read_text = String::new();

    for (idx, line) in text.lines().enumerate() {
        let fields = csv_fields(line);
        if idx == 0 {
            headers = fields;
            continue;
        }
        let Some(input_idx) = headers.iter().position(|field| *field == "input_type") else {
            return "samplesheet missing input_type".to_string();
        };
        let input_type = fields
            .get(input_idx)
            .map(|value| value.trim())
            .unwrap_or("");
        if input_type.is_empty() {
            continue;
        }
        *counts.entry(input_type.to_string()).or_insert(0) += 1;
        if input_type == "long_reads" {
            if let Some(long_idx) = headers.iter().position(|field| *field == "long_reads") {
                if let Some(value) = fields.get(long_idx) {
                    long_read_text.push_str(&value.to_lowercase());
                    long_read_text.push(' ');
                }
            }
        }
    }

    if counts.is_empty() {
        let input_type = first_value(manifest, &["sample.input_type"]);
        return match input_type.as_str() {
            "fastq" => "Illumina -> BWA-MEM2 + GATK".to_string(),
            "long_reads" => "Long reads -> Clair3; de novo available".to_string(),
            "alignment" => "BAM/CRAM -> reference workflow".to_string(),
            "vcf" => "VCF -> report-only workflow".to_string(),
            "assembly" => "Assembly -> report review".to_string(),
            _ => "samplesheet has no runnable rows".to_string(),
        };
    }
    if counts.len() == 1 {
        if counts.contains_key("fastq") {
            return "Illumina -> BWA-MEM2 + GATK".to_string();
        }
        if counts.contains_key("alignment") {
            return "BAM/CRAM -> reference workflow".to_string();
        }
        if counts.contains_key("vcf") {
            return "VCF -> report-only workflow".to_string();
        }
        if counts.contains_key("assembly") {
            return "Assembly -> report review".to_string();
        }
        if counts.contains_key("long_reads") {
            if ["ont", "nanopore", "ultralong"]
                .iter()
                .any(|token| long_read_text.contains(token))
            {
                return "ONT -> minimap2 + Clair3; Flye de novo".to_string();
            }
            return "PacBio HiFi -> pbmm2 + Clair3; hifiasm de novo".to_string();
        }
    }

    let mut parts = counts
        .iter()
        .map(|(key, value)| format!("{key}={value}"))
        .collect::<Vec<_>>();
    parts.sort();
    format!("Mixed inputs ({})", parts.join(", "))
}

fn csv_fields(line: &str) -> Vec<&str> {
    line.split(',').map(str::trim).collect()
}

fn find_on_path(binary: &str) -> Option<String> {
    let path_var = env::var_os("PATH")?;
    env::split_paths(&path_var)
        .map(|dir| dir.join(binary))
        .find(|candidate| is_executable(candidate))
        .map(|path| path.to_string_lossy().to_string())
}

fn is_executable(path: &Path) -> bool {
    if !path.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        path.metadata()
            .is_ok_and(|metadata| metadata.permissions().mode() & 0o111 != 0)
    }
    #[cfg(not(unix))]
    {
        true
    }
}

fn compact(value: &str, width: usize) -> String {
    let value = home_compact(value);
    let chars = value.chars().collect::<Vec<_>>();
    if chars.len() <= width {
        return value;
    }
    if width <= 3 {
        return ".".repeat(width);
    }
    let keep = width - 3;
    format!(
        "...{}",
        chars[chars.len() - keep..].iter().collect::<String>()
    )
}

fn home_compact(value: &str) -> String {
    let Some(home) = env::var_os("HOME").map(PathBuf::from) else {
        return value.to_string();
    };
    let home = home.to_string_lossy();
    value
        .strip_prefix(home.as_ref())
        .map(|rest| format!("~{rest}"))
        .unwrap_or_else(|| value.to_string())
}

trait ExpandHome {
    fn expand_home(&self) -> PathBuf;
}

impl ExpandHome for Path {
    fn expand_home(&self) -> PathBuf {
        let path = self.to_string_lossy();
        if let Some(rest) = path.strip_prefix("~/") {
            if let Some(home) = env::var_os("HOME") {
                return PathBuf::from(home).join(rest);
            }
        }
        self.to_path_buf()
    }
}

impl ExpandHome for PathBuf {
    fn expand_home(&self) -> PathBuf {
        self.as_path().expand_home()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_manifest_values_for_checklist_rows() {
        let values = parse_manifest(
            r#"
[paths]
dataset = "/tmp/reads"
workdir = "/tmp/out"

[sample]
samplesheet = "/tmp/reads/samples.csv"

[conda]
conda_exe = "/opt/conda/bin/conda"
"#,
        );

        assert_eq!(values.get("paths.dataset").unwrap(), "/tmp/reads");
        assert_eq!(values.get("paths.workdir").unwrap(), "/tmp/out");
        assert_eq!(
            values.get("sample.samplesheet").unwrap(),
            "/tmp/reads/samples.csv"
        );
        assert_eq!(
            values.get("conda.conda_exe").unwrap(),
            "/opt/conda/bin/conda"
        );
    }

    #[test]
    fn compact_keeps_path_tail() {
        assert_eq!(
            compact("/very/long/path/to/results/report.html", 22),
            "...results/report.html"
        );
    }

    #[test]
    fn analysis_plan_detects_illumina_fastq() {
        let temp =
            std::env::temp_dir().join(format!("opengenome-checklist-fastq-{}", std::process::id()));
        let _ = fs::remove_dir_all(&temp);
        fs::create_dir_all(&temp).unwrap();
        let samplesheet = temp.join("samples.csv");
        fs::write(
            &samplesheet,
            "sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\nHG002,HG002_l1,lane_1,fastq,/r1.fq.gz,/r2.fq.gz,,,,,,NA,0\n",
        )
        .unwrap();

        assert_eq!(
            analysis_plan(samplesheet.to_str().unwrap(), &HashMap::new()),
            "Illumina -> BWA-MEM2 + GATK"
        );
        let _ = fs::remove_dir_all(&temp);
    }

    #[test]
    fn analysis_plan_detects_ont_long_reads() {
        let temp =
            std::env::temp_dir().join(format!("opengenome-checklist-ont-{}", std::process::id()));
        let _ = fs::remove_dir_all(&temp);
        fs::create_dir_all(&temp).unwrap();
        let samplesheet = temp.join("samples.csv");
        fs::write(
            &samplesheet,
            "sample,row_id,lane,input_type,fastq_1,fastq_2,bam,cram,vcf,assembly,long_reads,sex,status\nHG002,HG002_long,lane_1,long_reads,,,,,,,/reads/HG002_nanopore.fastq.gz,NA,0\n",
        )
        .unwrap();

        assert_eq!(
            analysis_plan(samplesheet.to_str().unwrap(), &HashMap::new()),
            "ONT -> minimap2 + Clair3; Flye de novo"
        );
        let _ = fs::remove_dir_all(&temp);
    }

    #[test]
    fn load_status_shows_saved_core_limit() {
        let temp =
            std::env::temp_dir().join(format!("opengenome-checklist-cores-{}", std::process::id()));
        let _ = fs::remove_dir_all(&temp);
        fs::create_dir_all(&temp).unwrap();
        fs::write(
            temp.join("manifest.toml"),
            r#"
[paths]
threads = "8"
"#,
        )
        .unwrap();
        let old_config = env::var_os("OPEN_GENOME_CONFIG_DIR");
        env::set_var("OPEN_GENOME_CONFIG_DIR", &temp);
        let status = load_status();
        if let Some(value) = old_config {
            env::set_var("OPEN_GENOME_CONFIG_DIR", value);
        } else {
            env::remove_var("OPEN_GENOME_CONFIG_DIR");
        }
        let core_row = status
            .rows
            .iter()
            .find(|row| row.label == "Cores")
            .expect("cores row");
        assert_eq!(core_row.value, "limit 8");
        let _ = fs::remove_dir_all(&temp);
    }
}
