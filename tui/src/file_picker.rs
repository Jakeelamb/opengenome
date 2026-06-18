use crate::{float::FloatContent, hint::Shortcut, shortcuts, theme::Theme};
use ratatui::{
    crossterm::event::{KeyCode, KeyEvent, KeyModifiers, MouseEvent},
    prelude::*,
    symbols::border,
    widgets::{Block, Clear, List, ListItem, ListState, Padding, Paragraph, Wrap},
};
use std::{
    fs,
    path::{Path, PathBuf},
};

#[derive(Clone, Copy)]
pub enum FilePickerMode {
    Directory,
    Either,
}

pub struct FilePicker {
    title: String,
    mode: FilePickerMode,
    allow_skip: bool,
    cwd: PathBuf,
    entries: Vec<PickerEntry>,
    selection: ListState,
    filter: String,
    selected: Option<PathBuf>,
    skipped: bool,
    cancelled: bool,
    message: String,
}

#[derive(Clone)]
enum PickerEntry {
    Skip,
    CreateDirectory { path: PathBuf, name: String },
    ChooseCurrent,
    Parent,
    File(FileEntry),
}

#[derive(Clone)]
struct FileEntry {
    path: PathBuf,
    name: String,
    is_dir: bool,
}

impl FilePicker {
    pub fn new(title: &str, mode: FilePickerMode, start: PathBuf) -> Self {
        let cwd = start_dir(&start);
        let mut picker = Self {
            title: title.to_string(),
            mode,
            allow_skip: false,
            cwd,
            entries: Vec::new(),
            selection: ListState::default().with_selected(Some(0)),
            filter: String::new(),
            selected: None,
            skipped: false,
            cancelled: false,
            message: String::new(),
        };
        picker.refresh();
        picker
    }

    pub fn with_skip(mut self) -> Self {
        self.allow_skip = true;
        self.refresh();
        self
    }

    pub fn take_selected(&mut self) -> Option<PathBuf> {
        self.selected.take()
    }

    pub fn take_skipped(&mut self) -> bool {
        std::mem::take(&mut self.skipped)
    }

    fn refresh(&mut self) {
        self.entries = read_entries(&self.cwd, &self.filter, self.allow_skip, self.mode);
        let selected = if self.entries.is_empty() {
            None
        } else {
            Some(0)
        };
        self.selection.select(selected);
    }

    fn selected_entry(&self) -> Option<&FileEntry> {
        self.selection
            .selected()
            .and_then(|selected| self.entries.get(selected))
            .and_then(|entry| match entry {
                PickerEntry::File(file) => Some(file),
                _ => None,
            })
    }

    fn select_current(&mut self) {
        match self
            .selection
            .selected()
            .and_then(|selected| self.entries.get(selected))
        {
            Some(PickerEntry::Skip) => {
                self.skipped = true;
                return;
            }
            Some(PickerEntry::CreateDirectory { path, .. }) => {
                let path = path.clone();
                match fs::create_dir_all(&path) {
                    Ok(()) => self.selected = Some(path),
                    Err(err) => {
                        self.message = format!("Could not create folder: {err}");
                    }
                }
                return;
            }
            Some(PickerEntry::ChooseCurrent) => {
                self.choose_current_folder();
                return;
            }
            Some(PickerEntry::Parent) => {
                self.parent();
                return;
            }
            Some(PickerEntry::File(_)) => {}
            None => {
                self.message = "No item selected".to_string();
                return;
            }
        }

        let Some(entry) = self.selected_entry().cloned() else {
            return;
        };

        if entry.is_dir {
            self.cwd = entry.path;
            self.filter.clear();
            self.refresh();
        } else if matches!(self.mode, FilePickerMode::Either) {
            self.selected = Some(entry.path);
        } else {
            self.message = "Select a folder for this step".to_string();
        }
    }

    fn open_current(&mut self) {
        match self
            .selection
            .selected()
            .and_then(|selected| self.entries.get(selected))
        {
            Some(PickerEntry::Parent) => self.parent(),
            Some(PickerEntry::File(file)) if file.is_dir => {
                self.cwd = file.path.clone();
                self.filter.clear();
                self.refresh();
            }
            _ => {}
        }
    }

    fn choose_current_folder(&mut self) {
        self.selected = Some(self.cwd.clone());
    }

    fn parent(&mut self) {
        if let Some(parent) = self.cwd.parent() {
            self.cwd = parent.to_path_buf();
            self.filter.clear();
            self.refresh();
        }
    }

    fn home(&mut self) {
        if let Some(home) = std::env::var_os("HOME") {
            self.cwd = PathBuf::from(home);
            self.filter.clear();
            self.refresh();
        }
    }

    fn scroll_down(&mut self) {
        if self.entries.is_empty() {
            return;
        }
        let selected = self.selection.selected().unwrap_or(0);
        self.selection
            .select(Some((selected + 1).min(self.entries.len() - 1)));
    }

    fn scroll_up(&mut self) {
        if self.entries.is_empty() {
            return;
        }
        let selected = self.selection.selected().unwrap_or(0);
        self.selection.select(Some(selected.saturating_sub(1)));
    }
}

impl FloatContent for FilePicker {
    fn draw(&mut self, frame: &mut Frame, area: Rect, theme: &Theme) {
        frame.render_widget(Clear, area);

        let block = Block::bordered()
            .border_set(border::ROUNDED)
            .border_style(Style::default().fg(theme.tab_color()))
            .title(format!(" {} ", self.title))
            .padding(Padding::horizontal(1));
        let inner = block.inner(area);
        frame.render_widget(block, area);

        let chunks = Layout::vertical([
            Constraint::Length(3),
            Constraint::Min(5),
            Constraint::Length(3),
        ])
        .split(inner);

        let mode = match self.mode {
            FilePickerMode::Directory => "folder",
            FilePickerMode::Either => "file or folder",
        };
        let filter = if self.filter.is_empty() {
            "(start typing to filter)"
        } else {
            self.filter.as_str()
        };
        let header = format!(
            "Current: {}\nType to filter: {}    Select a {mode}",
            self.cwd.display(),
            filter,
        );
        frame.render_widget(Paragraph::new(header).wrap(Wrap { trim: true }), chunks[0]);

        let items = self.entries.iter().map(|entry| {
            let (icon, label, style) = match entry {
                PickerEntry::Skip => (
                    "[S]",
                    "Skip this step".to_string(),
                    Style::default().fg(theme.tab_color()).bold(),
                ),
                PickerEntry::CreateDirectory { path, name } => (
                    "[N]",
                    format!("Create folder \"{name}\" ({})", path.display()),
                    Style::default().fg(theme.success_color()).bold(),
                ),
                PickerEntry::ChooseCurrent => (
                    "[+]",
                    format!("Choose this folder ({})", self.cwd.display()),
                    Style::default().fg(theme.success_color()).bold(),
                ),
                PickerEntry::Parent => (
                    "[<]",
                    "Parent folder".to_string(),
                    Style::default().fg(theme.unfocused_color()),
                ),
                PickerEntry::File(file) => {
                    let icon = if file.is_dir { "[D]" } else { "[F]" };
                    let style = if file.is_dir {
                        Style::default().fg(theme.dir_color())
                    } else {
                        Style::default().fg(theme.cmd_color())
                    };
                    (icon, file.name.clone(), style)
                }
            };
            ListItem::new(Line::from(vec![
                Span::styled(icon, style),
                Span::raw("  "),
                Span::styled(label, style),
            ]))
        });

        let list = List::new(items)
            .highlight_symbol("> ")
            .highlight_style(
                Style::default()
                    .bg(theme.focused_color())
                    .fg(Color::Black)
                    .bold(),
            )
            .scroll_padding(1);
        frame.render_stateful_widget(list, chunks[1], &mut self.selection);

        let default_footer = match self.mode {
            FilePickerMode::Directory if self.allow_skip => {
                "Type to filter or name a new folder. Arrow keys move. Enter activates the highlighted row. Backspace edits filter, then goes up when empty."
            }
            FilePickerMode::Directory => {
                "Type to filter or name a new folder. Arrow keys move. Enter activates the highlighted row. Backspace edits filter, then goes up when empty."
            }
            FilePickerMode::Either if self.allow_skip => {
                "Type to filter. Arrow keys move. Enter activates the highlighted row. Backspace edits filter, then goes up when empty."
            }
            FilePickerMode::Either => {
                "Type to filter. Arrow keys move. Enter activates the highlighted row. Backspace edits filter, then goes up when empty."
            }
        };
        let footer = if self.message.is_empty() {
            default_footer
        } else {
            self.message.as_str()
        };
        frame.render_widget(
            Paragraph::new(footer)
                .style(Style::default().fg(theme.unfocused_color()))
                .wrap(Wrap { trim: true }),
            chunks[2],
        );
    }

    fn handle_key_event(&mut self, key: &KeyEvent) -> bool {
        self.message.clear();
        match key.code {
            KeyCode::Esc => {
                self.cancelled = true;
                true
            }
            KeyCode::Enter => {
                self.select_current();
                self.selected.is_some() || self.skipped
            }
            KeyCode::Right => {
                self.open_current();
                false
            }
            KeyCode::Backspace => {
                if self.filter.is_empty() {
                    self.parent();
                } else {
                    self.filter.pop();
                    self.refresh();
                }
                false
            }
            KeyCode::Left => {
                self.parent();
                false
            }
            KeyCode::Home => {
                self.home();
                false
            }
            KeyCode::Down => {
                self.scroll_down();
                false
            }
            KeyCode::Up => {
                self.scroll_up();
                false
            }
            KeyCode::Char(ch) => {
                if !ch.is_control()
                    && !key
                        .modifiers
                        .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT)
                {
                    self.filter.push(ch);
                    self.refresh();
                }
                false
            }
            KeyCode::Delete => {
                self.filter.clear();
                self.refresh();
                false
            }
            _ => false,
        }
    }

    fn handle_mouse_event(&mut self, _key: &MouseEvent) -> bool {
        false
    }

    fn is_finished(&self) -> bool {
        self.selected.is_some() || self.skipped || self.cancelled
    }

    fn get_shortcut_list(&self) -> (&str, Box<[Shortcut]>) {
        (
            "File picker",
            shortcuts!(
                ("Choose highlighted", ["Enter"]),
                ("Open folder", ["Right"]),
                ("Skip optional step", ["S row"]),
                ("Parent", ["Backspace", "Left"]),
                ("Home", ["Home"]),
                ("Cancel", ["Esc"]),
            ),
        )
    }
}

fn start_dir(path: &Path) -> PathBuf {
    if path.is_dir() {
        path.to_path_buf()
    } else if let Some(parent) = path.parent().filter(|parent| parent.is_dir()) {
        parent.to_path_buf()
    } else if let Some(home) = std::env::var_os("HOME") {
        PathBuf::from(home)
    } else {
        std::env::current_dir().unwrap_or_else(|_| PathBuf::from("/"))
    }
}

fn read_entries(
    cwd: &Path,
    filter: &str,
    allow_skip: bool,
    mode: FilePickerMode,
) -> Vec<PickerEntry> {
    let create_directory = new_directory_entry(cwd, filter, mode);
    let filter = filter.to_lowercase();
    let Ok(read_dir) = fs::read_dir(cwd) else {
        return allow_skip
            .then_some(PickerEntry::Skip)
            .into_iter()
            .chain(create_directory)
            .collect();
    };

    let mut entries: Vec<_> = read_dir
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let path = entry.path();
            let file_type = entry.file_type().ok()?;
            let is_dir = file_type.is_dir();
            if matches!(mode, FilePickerMode::Directory) && !is_dir {
                return None;
            }
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with('.') && filter.is_empty() {
                return None;
            }
            if !filter.is_empty() && !name.to_lowercase().contains(&filter) {
                return None;
            }
            Some(FileEntry { path, name, is_dir })
        })
        .collect();

    entries.sort_by(|a, b| {
        b.is_dir
            .cmp(&a.is_dir)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });

    let skip = allow_skip.then_some(PickerEntry::Skip).into_iter();
    skip.chain(create_directory)
        .chain(std::iter::once(PickerEntry::ChooseCurrent))
        .chain(std::iter::once(PickerEntry::Parent))
        .chain(entries.into_iter().map(PickerEntry::File))
        .collect()
}

fn new_directory_entry(cwd: &Path, filter: &str, mode: FilePickerMode) -> Option<PickerEntry> {
    if !matches!(mode, FilePickerMode::Directory) {
        return None;
    }
    let name = filter.trim();
    if name.is_empty()
        || name == "."
        || name == ".."
        || name.contains('/')
        || name.contains('\\')
        || name.contains('\0')
    {
        return None;
    }
    let path = cwd.join(name);
    if path.exists() {
        return None;
    }
    Some(PickerEntry::CreateDirectory {
        path,
        name: name.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::Theme;
    use ratatui::{backend::TestBackend, Terminal};

    #[test]
    fn start_dir_uses_existing_parent_for_file() {
        let cwd = std::env::current_dir().unwrap();
        let path = cwd.join("does-not-exist.fastq.gz");
        assert_eq!(cwd, start_dir(&path));
    }

    #[test]
    fn read_entries_filters_current_directory() {
        let root = unique_test_dir("filter");
        std::fs::create_dir_all(root.join("alpha")).unwrap();
        std::fs::create_dir_all(root.join("beta")).unwrap();

        let entries = read_entries(&root, "alp", false, FilePickerMode::Directory);
        assert!(entries.iter().any(|entry| matches!(
            entry,
            PickerEntry::File(file) if file.name == "alpha"
        )));
        assert!(!entries.iter().any(|entry| matches!(
            entry,
            PickerEntry::File(file) if file.name == "beta"
        )));

        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn directory_mode_hides_files() {
        let root = unique_test_dir("directory-hides-files");
        std::fs::create_dir_all(root.join("folder")).unwrap();
        std::fs::write(root.join("reads.fastq.gz"), b"test").unwrap();

        let entries = read_entries(&root, "", false, FilePickerMode::Directory);

        assert!(entries.iter().any(|entry| matches!(
            entry,
            PickerEntry::File(file) if file.name == "folder" && file.is_dir
        )));
        assert!(!entries.iter().any(|entry| matches!(
            entry,
            PickerEntry::File(file) if file.name == "reads.fastq.gz"
        )));

        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn either_mode_keeps_files_visible() {
        let root = unique_test_dir("either-keeps-files");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("reads.fastq.gz"), b"test").unwrap();

        let entries = read_entries(&root, "", false, FilePickerMode::Either);

        assert!(entries.iter().any(|entry| matches!(
            entry,
            PickerEntry::File(file) if file.name == "reads.fastq.gz" && !file.is_dir
        )));

        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn directory_mode_shows_create_folder_for_new_filter() {
        let root = unique_test_dir("create-row");
        std::fs::create_dir_all(&root).unwrap();

        let entries = read_entries(&root, "new-work", false, FilePickerMode::Directory);

        assert!(matches!(
            entries.first(),
            Some(PickerEntry::CreateDirectory { name, path })
                if name == "new-work" && path == &root.join("new-work")
        ));

        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn directory_mode_enter_creates_and_selects_new_folder() {
        let root = unique_test_dir("create-select");
        let created = root.join("new-work");
        std::fs::create_dir_all(&root).unwrap();
        let mut picker = FilePicker::new(
            "Choose Output Folder",
            FilePickerMode::Directory,
            root.clone(),
        );
        picker.filter = "new-work".to_string();
        picker.refresh();

        let finished = picker.handle_key_event(&KeyEvent::from(KeyCode::Enter));

        assert!(finished);
        assert_eq!(picker.take_selected(), Some(created.clone()));
        assert!(created.is_dir());

        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn either_mode_does_not_offer_create_folder() {
        let root = unique_test_dir("no-create-either");
        std::fs::create_dir_all(&root).unwrap();

        let entries = read_entries(&root, "new-work", false, FilePickerMode::Either);

        assert!(!entries
            .iter()
            .any(|entry| matches!(entry, PickerEntry::CreateDirectory { .. })));

        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn optional_picker_can_skip_step() {
        let root = unique_test_dir("skip");
        std::fs::create_dir_all(&root).unwrap();
        let mut picker =
            FilePicker::new("Optional", FilePickerMode::Either, root.clone()).with_skip();

        let finished = picker.handle_key_event(&KeyEvent::from(KeyCode::Enter));

        assert!(finished);
        assert!(picker.take_skipped());
        assert!(picker.selected.is_none());

        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn directory_mode_enter_opens_directory() {
        let root = unique_test_dir("open-dir");
        let child = root.join("child");
        std::fs::create_dir_all(&child).unwrap();

        let mut picker = FilePicker::new(
            "Choose Output Folder",
            FilePickerMode::Directory,
            root.clone(),
        );
        picker.selection.select(Some(2));
        picker.select_current();

        assert_eq!(picker.cwd, child);
        assert!(picker.selected.is_none());

        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn right_arrow_does_not_choose_current_folder() {
        let root = unique_test_dir("right-no-accept");
        std::fs::create_dir_all(&root).unwrap();
        let mut picker = FilePicker::new(
            "Choose Output Folder",
            FilePickerMode::Directory,
            root.clone(),
        );

        let finished = picker.handle_key_event(&KeyEvent::from(KeyCode::Right));

        assert!(!finished);
        assert!(picker.selected.is_none());
        assert_eq!(picker.cwd, root);

        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn right_arrow_opens_highlighted_directory_without_accepting() {
        let root = unique_test_dir("right-open-dir");
        let child = root.join("child");
        std::fs::create_dir_all(&child).unwrap();
        let mut picker = FilePicker::new(
            "Choose Output Folder",
            FilePickerMode::Directory,
            root.clone(),
        );
        picker.selection.select(Some(2));

        let finished = picker.handle_key_event(&KeyEvent::from(KeyCode::Right));

        assert!(!finished);
        assert!(picker.selected.is_none());
        assert_eq!(picker.cwd, child);

        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn left_arrow_at_root_does_not_accept_path() {
        let mut picker = FilePicker::new(
            "Choose Output Folder",
            FilePickerMode::Directory,
            PathBuf::from("/"),
        );

        let finished = picker.handle_key_event(&KeyEvent::from(KeyCode::Left));

        assert!(!finished);
        assert!(picker.selected.is_none());
        assert_eq!(picker.cwd, PathBuf::from("/"));
    }

    #[test]
    fn backspace_edits_filter_before_leaving_directory() {
        let root = unique_test_dir("backspace");
        std::fs::create_dir_all(&root).unwrap();
        let mut picker = FilePicker::new(
            "Choose Output Folder",
            FilePickerMode::Directory,
            root.clone(),
        );
        picker.filter = "abc".to_string();

        picker.handle_key_event(&KeyEvent::from(KeyCode::Backspace));

        assert_eq!(picker.filter, "ab");
        assert_eq!(picker.cwd, root);

        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn printable_shortcut_letters_are_typed_into_filter() {
        let root = unique_test_dir("shortcut-letters");
        std::fs::create_dir_all(&root).unwrap();
        let mut picker = FilePicker::new(
            "Choose Output Folder",
            FilePickerMode::Directory,
            root.clone(),
        );

        for ch in ['h', 'j', 'k', 'l', 'q', ' '] {
            let finished = picker.handle_key_event(&KeyEvent::from(KeyCode::Char(ch)));
            assert!(!finished);
        }

        assert_eq!(picker.filter, "hjklq ");
        assert!(!picker.cancelled);
        assert_eq!(picker.cwd, root);

        std::fs::remove_dir_all(root).unwrap();
    }

    fn unique_test_dir(label: &str) -> PathBuf {
        std::env::temp_dir().join(format!("open-genome-picker-{label}-{}", std::process::id()))
    }

    #[test]
    fn render_snapshot_when_requested() {
        let Some(path) = std::env::var_os("OPEN_GENOME_PICKER_SNAPSHOT") else {
            return;
        };

        let backend = TestBackend::new(120, 34);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut picker = FilePicker::new(
            "Choose Output Folder",
            FilePickerMode::Directory,
            std::env::current_dir().unwrap(),
        );
        if let Some(filter) = std::env::var_os("OPEN_GENOME_PICKER_FILTER") {
            picker.filter = filter.to_string_lossy().to_string();
            picker.refresh();
        }

        terminal
            .draw(|frame| picker.draw(frame, frame.area(), &Theme::Default))
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
