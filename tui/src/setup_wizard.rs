use crate::{
    file_picker::{FilePicker, FilePickerMode},
    float::FloatContent,
    hint::Shortcut,
    shortcuts,
    theme::Theme,
};
use ratatui::{
    crossterm::event::{KeyEvent, MouseEvent},
    prelude::*,
    widgets::{Block, Clear, Padding, Paragraph, Wrap},
};
use std::path::{Path, PathBuf};

pub struct SetupWizard {
    script_dir: PathBuf,
    step: SetupStep,
    picker: FilePicker,
    dataset_start: PathBuf,
    reference_start: PathBuf,
    workdir: Option<PathBuf>,
    dataset: Option<PathBuf>,
    reference: Option<PathBuf>,
    command_script: Option<String>,
    finished: bool,
}

pub struct SetupWizardStarts {
    pub workdir: PathBuf,
    pub dataset: PathBuf,
    pub reference: PathBuf,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum SetupStep {
    Workdir,
    Dataset,
    Reference,
}

impl SetupWizard {
    pub fn new(script_dir: PathBuf, starts: SetupWizardStarts) -> Self {
        Self {
            script_dir,
            step: SetupStep::Workdir,
            picker: picker_for_step(SetupStep::Workdir, starts.workdir),
            dataset_start: starts.dataset,
            reference_start: starts.reference,
            workdir: None,
            dataset: None,
            reference: None,
            command_script: None,
            finished: false,
        }
    }

    pub fn take_command_script(&mut self) -> Option<String> {
        self.command_script.take()
    }

    fn advance(&mut self) {
        if let Some(path) = self.picker.take_selected() {
            match self.step {
                SetupStep::Workdir => self.workdir = Some(path),
                SetupStep::Dataset => self.dataset = Some(path),
                SetupStep::Reference => self.reference = Some(path),
            }
        } else if !self.picker.take_skipped() {
            self.finished = true;
            return;
        }

        match self.step {
            SetupStep::Workdir => {
                let start = self
                    .dataset
                    .clone()
                    .or_else(|| Some(self.dataset_start.clone()))
                    .or_else(|| self.workdir.clone())
                    .unwrap_or_else(default_start_path);
                self.step = SetupStep::Dataset;
                self.picker = picker_for_step(SetupStep::Dataset, start);
            }
            SetupStep::Dataset => {
                let start = self
                    .reference
                    .clone()
                    .or_else(|| Some(self.reference_start.clone()))
                    .or_else(|| self.workdir.clone())
                    .unwrap_or_else(default_start_path);
                self.step = SetupStep::Reference;
                self.picker = picker_for_step(SetupStep::Reference, start);
            }
            SetupStep::Reference => {
                self.command_script = Some(build_guided_setup_script(
                    &self.script_dir,
                    self.workdir.as_deref(),
                    self.dataset.as_deref(),
                    self.reference.as_deref(),
                ));
                self.finished = true;
            }
        }
    }

    fn progress_label(&self) -> &'static str {
        match self.step {
            SetupStep::Workdir => "Step 1 of 3: output/work folder",
            SetupStep::Dataset => "Step 2 of 3: sequencing data",
            SetupStep::Reference => "Step 3 of 3: reference genome",
        }
    }
}

impl FloatContent for SetupWizard {
    fn draw(&mut self, frame: &mut Frame, area: Rect, theme: &Theme) {
        frame.render_widget(Clear, area);

        let block = Block::bordered()
            .border_style(Style::default().fg(theme.tab_color()))
            .title(" Automated Setup ")
            .padding(Padding::horizontal(1));
        let inner = block.inner(area);
        frame.render_widget(block, area);

        let chunks = Layout::vertical([Constraint::Length(3), Constraint::Min(8)]).split(inner);
        let intro = format!(
            "{}\nUse the picker below; optional steps include a skip row.",
            self.progress_label()
        );
        frame.render_widget(
            Paragraph::new(intro)
                .style(Style::default().fg(theme.cmd_color()))
                .wrap(Wrap { trim: true }),
            chunks[0],
        );
        self.picker.draw(frame, chunks[1], theme);
    }

    fn handle_key_event(&mut self, key: &KeyEvent) -> bool {
        if self.picker.handle_key_event(key) {
            self.advance();
        }
        self.finished
    }

    fn handle_mouse_event(&mut self, key: &MouseEvent) -> bool {
        self.picker.handle_mouse_event(key)
    }

    fn is_finished(&self) -> bool {
        self.finished
    }

    fn get_shortcut_list(&self) -> (&str, Box<[Shortcut]>) {
        (
            "Automated setup",
            shortcuts!(
                ("Choose highlighted", ["Enter"]),
                ("Open folder", ["Right", "l"]),
                ("Choose current folder", ["Space"]),
                ("Parent", ["Backspace", "Left"]),
                ("Cancel", ["Esc", "q"]),
            ),
        )
    }
}

fn picker_for_step(step: SetupStep, start: PathBuf) -> FilePicker {
    match step {
        SetupStep::Workdir => FilePicker::new(
            "Choose Output and Work Folder",
            FilePickerMode::Directory,
            start,
        ),
        SetupStep::Dataset => {
            FilePicker::new("Import Sequencing Files", FilePickerMode::Either, start).with_skip()
        }
        SetupStep::Reference => {
            FilePicker::new("Choose Reference Genome", FilePickerMode::Either, start).with_skip()
        }
    }
}

fn build_guided_setup_script(
    script_dir: &Path,
    workdir: Option<&Path>,
    dataset: Option<&Path>,
    reference: Option<&Path>,
) -> String {
    let mut script = String::new();
    script.push_str("set -e\n");
    script.push_str("echo 'Open Genome automated setup'\n");
    script.push_str(&format!(
        "cd {}\n",
        shell_quote(&script_dir.to_string_lossy())
    ));

    if let Some(workdir) = workdir {
        script.push_str("echo ''\n");
        script.push_str("echo 'Saving output/work folder...'\n");
        script.push_str(&format!(
            "OPEN_GENOME_SELECTED_PATH={} sh ./set_workdir.sh\n",
            shell_quote(&workdir.to_string_lossy())
        ));
    }

    if let Some(dataset) = dataset {
        script.push_str("echo ''\n");
        script.push_str("echo 'Importing sequencing files...'\n");
        script.push_str(&format!(
            "OPEN_GENOME_SELECTED_PATH={} sh ./scan_sequencing_folder.sh\n",
            shell_quote(&dataset.to_string_lossy())
        ));
    } else {
        script.push_str("echo ''\n");
        script.push_str("echo 'Skipping sequencing import.'\n");
    }

    if let Some(reference) = reference {
        script.push_str("echo ''\n");
        script.push_str("echo 'Saving reference genome...'\n");
        script.push_str(&format!(
            "OPEN_GENOME_SELECTED_PATH={} sh ./set_reference_path.sh\n",
            shell_quote(&reference.to_string_lossy())
        ));
    } else {
        script.push_str("echo ''\n");
        script.push_str("echo 'Skipping reference selection.'\n");
    }

    script.push_str("echo ''\n");
    script.push_str("echo 'Setup path pass complete. Read-only readiness checklist:'\n");
    script.push_str("sh ./show_paths.sh\n");
    script
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn default_start_path() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from("/")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::{backend::TestBackend, Terminal};

    #[test]
    fn guided_script_uses_selected_paths_without_running_legacy_prompt_script() {
        let script = build_guided_setup_script(
            Path::new("/tmp/open genome/setup/scripts"),
            Some(Path::new("/tmp/work folder")),
            Some(Path::new("/tmp/data.fastq.gz")),
            Some(Path::new("/tmp/ref's.fa")),
        );

        assert!(script.contains("sh ./set_workdir.sh"));
        assert!(script.contains("sh ./scan_sequencing_folder.sh"));
        assert!(script.contains("sh ./set_reference_path.sh"));
        assert!(script.contains("sh ./show_paths.sh"));
        assert!(script.contains("'/tmp/work folder'"));
        assert!(script.contains("'/tmp/ref'\\''s.fa'"));
        assert!(!script.contains("first_time_setup.sh"));
    }

    #[test]
    fn guided_script_allows_optional_steps_to_be_skipped() {
        let script = build_guided_setup_script(
            Path::new("/tmp/setup/scripts"),
            Some(Path::new("/tmp/work")),
            None,
            None,
        );

        assert!(script.contains("Skipping sequencing import."));
        assert!(script.contains("Skipping reference selection."));
        assert!(!script.contains("scan_sequencing_folder.sh"));
        assert!(!script.contains("set_reference_path.sh"));
    }

    #[test]
    fn render_snapshot_when_requested() {
        let Some(path) = std::env::var_os("OPEN_GENOME_SETUP_WIZARD_SNAPSHOT") else {
            return;
        };

        let cwd = std::env::current_dir().unwrap();
        let mut wizard = SetupWizard::new(
            cwd.join("core/tabs/setup/scripts"),
            SetupWizardStarts {
                workdir: cwd.clone(),
                dataset: cwd.clone(),
                reference: cwd,
            },
        );
        if std::env::var_os("OPEN_GENOME_SETUP_WIZARD_STEP")
            .as_deref()
            .is_some_and(|step| step == "dataset")
        {
            wizard.step = SetupStep::Dataset;
            wizard.picker = picker_for_step(SetupStep::Dataset, std::env::current_dir().unwrap());
        }
        let backend = TestBackend::new(130, 38);
        let mut terminal = Terminal::new(backend).unwrap();

        terminal
            .draw(|frame| wizard.draw(frame, frame.area(), &Theme::Default))
            .unwrap();

        let buffer = terminal.backend().buffer();
        let area = buffer.area;
        let mut lines = Vec::new();
        for y in area.y..area.y + area.height {
            let mut line = String::new();
            for x in area.x..area.x + area.width {
                if let Some(cell) = buffer.cell((x, y)) {
                    line.push_str(cell.symbol());
                }
            }
            lines.push(line.trim_end().to_string());
        }
        std::fs::write(path, lines.join("\n")).unwrap();
    }
}
