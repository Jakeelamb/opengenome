use crate::{
    confirmation::{ConfirmPrompt, ConfirmStatus},
    file_picker::{FilePicker, FilePickerMode},
    filter::{Filter, SearchAction},
    float::{Float, FloatContent},
    floating_text::FloatingText,
    hint::{create_shortcut_list, Shortcut},
    logo::Logo,
    root::check_root_status,
    running_command::RunningCommand,
    setup_status::SetupChecklist,
    setup_wizard::{SetupWizard, SetupWizardStarts},
    shortcuts,
    system_info::SystemInfo,
    theme::Theme,
    Args,
};
use opengenome_core::{ego_tree::NodeId, Command, Config, ConfigValues, ListNode, TabList};
use ratatui::{
    crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseEvent, MouseEventKind},
    layout::Flex,
    prelude::*,
    symbols::border,
    widgets::{Block, List, ListState, Padding, Paragraph},
};
use std::{
    path::{Path, PathBuf},
    rc::Rc,
};

const MIN_WIDTH: u16 = 100;
const MIN_HEIGHT: u16 = 25;
const FLOAT_SIZE: u16 = 95;
const CONFIRM_PROMPT_FLOAT_SIZE: u16 = 40;
const LEFT_EXTRA_WIDTH: u16 = 4;
const TITLE: &str = " OPEN GENOME ";
const LIST_HIGHLIGHT_SYMBOL: &str = "> ";
const ACTIONS_GUIDE: &str = "Open Genome tags:

CFG  changes local settings
ENV  installs or updates local tools
CHK  checks installed tools
REF  prepares reference-genome files
DATA reads or prepares sequencing data
PIPE runs or previews a workflow

Actions still ask before writing files, installing tools, or launching long work.
";

pub struct AppState {
    /// Areas of tabs
    areas: Option<Areas>,
    /// Selected theme
    theme: Theme,
    /// Currently focused area
    focus: Focus,
    /// List of tabs
    tabs: TabList,
    /// Current tab
    current_tab: ListState,
    longest_tab_display_len: u16,
    /// This stack keeps track of our "current directory". You can think of it as `pwd`. but not
    /// just the current directory, all paths that took us here, so we can "cd .."
    visit_stack: Vec<(NodeId, usize)>,
    /// This is the state associated with the list widget, used to display the selection in the
    /// widget
    selection: ListState,
    filter: Filter,
    multi_select: bool,
    selected_commands: Vec<Rc<ListNode>>,
    drawable: bool,
    #[cfg(feature = "tips")]
    tip: &'static str,
    size_bypass: bool,
    skip_confirmation: bool,
    mouse_enabled: bool,
    system_info: Option<SystemInfo>,
    logo: Option<Logo>,
    setup_checklist: SetupChecklist,
}

pub enum Focus {
    Search,
    TabList,
    List,
    FloatingWindow(Float<dyn FloatContent>),
    ConfirmationPrompt(Float<ConfirmPrompt>),
    FilePicker(Float<FilePicker>, SetupPathAction),
    SetupWizard(Float<SetupWizard>),
}

#[derive(Clone)]
pub struct SetupPathAction {
    title: &'static str,
    mode: FilePickerMode,
    script: PathBuf,
    manifest_key: &'static str,
}

pub struct ListEntry {
    pub node: Rc<ListNode>,
    pub id: NodeId,
    pub has_children: bool,
}

struct Areas {
    tab_list: Rect,
    list: Rect,
}

enum SelectedItem {
    UpDir,
    Directory,
    Command,
    None,
}

enum ScrollDir {
    Up,
    Down,
}

fn setup_path_action(command: &Command) -> Option<SetupPathAction> {
    let Command::LocalFile { file, .. } = command else {
        return None;
    };

    if file.ends_with("setup/scripts/set_workdir.sh") {
        Some(SetupPathAction {
            title: "Choose Output Folder",
            mode: FilePickerMode::Directory,
            script: file.clone(),
            manifest_key: "paths.workdir",
        })
    } else if file.ends_with("setup/scripts/set_reference_path.sh") {
        Some(SetupPathAction {
            title: "Choose Reference Genome",
            mode: FilePickerMode::Either,
            script: file.clone(),
            manifest_key: "paths.reference",
        })
    } else if file.ends_with("setup/scripts/scan_sequencing_folder.sh") {
        Some(SetupPathAction {
            title: "Import Sequencing Files",
            mode: FilePickerMode::Either,
            script: file.clone(),
            manifest_key: "paths.dataset",
        })
    } else if file.ends_with("setup/scripts/set_results_path.sh") {
        Some(SetupPathAction {
            title: "Choose Existing Results Folder",
            mode: FilePickerMode::Directory,
            script: file.clone(),
            manifest_key: "workflow.outdir",
        })
    } else {
        None
    }
}

fn setup_wizard_script(command: &Command) -> Option<PathBuf> {
    let Command::LocalFile { file, .. } = command else {
        return None;
    };

    file.ends_with("setup/scripts/first_time_setup.sh")
        .then(|| file.clone())
}

fn current_manifest_path(script: &Path, key: &str) -> Option<PathBuf> {
    let manifest_cli = manifest_cli_for_script(script)?;
    let output = std::process::Command::new("python3")
        .arg(manifest_cli)
        .arg("get")
        .arg(key)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let value = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if value.is_empty() {
        None
    } else {
        Some(PathBuf::from(value))
    }
}

fn manifest_cli_for_script(script: &Path) -> Option<PathBuf> {
    let tabs_root = script.parent()?.parent()?.parent()?;
    Some(tabs_root.join("open-genome/lib/manifest_cli.py"))
}

fn default_start_path(_mode: FilePickerMode) -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from("/")))
}

fn setup_script_command(script: &Path, selected_path: &Path) -> RunningCommand {
    let shell = format!(
        "OPEN_GENOME_SELECTED_PATH={} sh {}",
        shell_quote(&selected_path.to_string_lossy()),
        shell_quote(&script.to_string_lossy())
    );
    RunningCommand::new_shell(shell)
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn is_action_node(node: &ListNode) -> bool {
    !node.is_header && !matches!(&node.command, Command::None)
}

fn section_header(name: &str, width: usize) -> String {
    let label = format!(" {} ", name.to_ascii_uppercase());
    if width <= label.len() {
        return label.trim().to_string();
    }
    let left = 4.min((width - label.len()) / 2);
    let right = width.saturating_sub(left + label.len());
    format!("{}{}{}", "-".repeat(left), label, "-".repeat(right))
}

impl AppState {
    pub fn new(args: Args) -> Self {
        #[cfg(unix)]
        let root_warning = check_root_status(args.bypass_root);
        #[cfg(not(unix))]
        let root_warning = None;

        let tabs = opengenome_core::get_tabs(!args.override_validation);
        let root_id = tabs[0].tree.root().id();

        let longest_tab_display_len = tabs
            .iter()
            .map(|tab| tab.name.len() + args.theme.tab_icon().len())
            .max()
            .unwrap_or(22) as u16;

        let mut state = Self {
            areas: None,
            theme: args.theme,
            focus: Focus::List,
            tabs,
            current_tab: ListState::default().with_selected(Some(0)),
            longest_tab_display_len,
            visit_stack: vec![(root_id, 0usize)],
            selection: ListState::default().with_selected(Some(0)),
            filter: Filter::new(),
            multi_select: false,
            selected_commands: Vec::new(),
            drawable: false,
            #[cfg(feature = "tips")]
            tip: crate::tips::get_tip(),
            size_bypass: args.size_bypass,
            skip_confirmation: args.skip_confirmation,
            mouse_enabled: args.mouse,
            system_info: SystemInfo::gather(),
            logo: Logo::load(),
            setup_checklist: SetupChecklist::new(),
        };

        #[cfg(unix)]
        if let Some(root_warning) = root_warning {
            state.spawn_float(root_warning, FLOAT_SIZE, FLOAT_SIZE);
        }

        state.update_items();

        if let Some(config_path) = args.config {
            let config = Config::read_config(&config_path, &state.tabs);
            state.apply_config(config);
        }

        state
    }

    fn apply_config(&mut self, config_values: ConfigValues) {
        self.skip_confirmation = self.skip_confirmation || config_values.skip_confirmation;
        self.size_bypass = self.size_bypass || config_values.size_bypass;

        if !config_values.auto_execute_commands.is_empty() {
            self.selected_commands = config_values.auto_execute_commands;
            self.handle_initial_auto_execute();
        }
    }

    fn handle_initial_auto_execute(&mut self) {
        if !self.selected_commands.is_empty() {
            self.spawn_confirmprompt();
        }
    }

    fn spawn_confirmprompt(&mut self) {
        if self.skip_confirmation || self.should_skip_confirmation_for_selection() {
            self.handle_confirm_command();
        } else {
            let cmd_names: Vec<_> = self
                .selected_commands
                .iter()
                .map(|node| node.name.as_str())
                .collect();

            let prompt = ConfirmPrompt::new(&cmd_names);
            self.focus = Focus::ConfirmationPrompt(Float::new(
                Box::new(prompt),
                CONFIRM_PROMPT_FLOAT_SIZE,
                CONFIRM_PROMPT_FLOAT_SIZE,
            ));
        }
    }

    fn should_skip_confirmation_for_selection(&self) -> bool {
        !self.selected_commands.is_empty()
            && self
                .selected_commands
                .iter()
                .all(|node| self.should_skip_confirmation_for_command(&node.command))
    }

    fn should_skip_confirmation_for_command(&self, command: &Command) -> bool {
        match command {
            Command::LocalFile { file, .. } => {
                let path = file.to_string_lossy();
                path.ends_with("/welcome/scripts/about_open_genome.sh")
                    || path.ends_with("/welcome/scripts/what_to_expect.sh")
                    || path.ends_with("/welcome/scripts/support_project.sh")
                    || path.ends_with("/setup/scripts/show_paths.sh")
                    || path.ends_with("/genome-workflow/scripts/reference_bundle_status.sh")
                    || path.ends_with("/visualization/scripts/open_report_viewer.sh")
                    || path.ends_with("/visualization/scripts/results_summary.sh")
                    || path.ends_with("/reports/scripts/report_boundaries.sh")
                    || path.ends_with("/reports/scripts/report_sources.sh")
            }
            _ => false,
        }
    }

    fn get_list_item_shortcut(&self) -> Box<[Shortcut]> {
        if self.selected_item_is_dir() {
            shortcuts!(("Open group", ["l", "Right", "Enter"]))
        } else if self.selected_item_is_cmd() {
            shortcuts!(
                ("Run action", ["l", "Right", "Enter"]),
                ("Preview action", ["p"]),
                ("Action details", ["d"])
            )
        } else {
            shortcuts!()
        }
    }

    pub fn get_keybinds(&self) -> (&str, Box<[Shortcut]>) {
        match self.focus {
            Focus::Search => (
                "Search bar",
                shortcuts!(("Abort search", ["Esc", "CTRL-c"]), ("Search", ["Enter"])),
            ),

            Focus::List => {
                let mut hints = Vec::new();
                hints.push(Shortcut::new("Exit", ["q", "CTRL-c"]));

                if self.at_root() {
                    hints.push(Shortcut::new("Focus tab list", ["h", "Left"]));
                    hints.extend(self.get_list_item_shortcut());
                } else if self.selected_item_is_up_dir() {
                    hints.push(Shortcut::new(
                        "Go to parent directory",
                        ["l", "Right", "Enter", "h", "Left"],
                    ));
                } else {
                    hints.push(Shortcut::new("Go to parent directory", ["h", "Left"]));
                    hints.extend(self.get_list_item_shortcut());
                }

                hints.extend(shortcuts!(
                    ("Select item above", ["k", "Up"]),
                    ("Select item below", ["j", "Down"]),
                    ("Next theme", ["t"]),
                    ("Previous theme", ["T"]),
                    ("Multi-selection mode", ["v"]),
                ));
                if self.multi_select {
                    hints.push(Shortcut::new("Select multiple commands", ["Space"]));
                }
                hints.extend(shortcuts!(
                    ("Next tab", ["Tab"]),
                    ("Previous tab", ["Shift-Tab"]),
                    ("Tag guide", ["g"])
                ));

                ("Actions", hints.into_boxed_slice())
            }

            Focus::TabList => (
                "Sections",
                shortcuts!(
                    ("Exit", ["q", "CTRL-c"]),
                    ("Focus actions", ["l", "Right", "Enter"]),
                    ("Select item above", ["k", "Up"]),
                    ("Select item below", ["j", "Down"]),
                    ("Next theme", ["t"]),
                    ("Previous theme", ["T"]),
                    ("Next tab", ["Tab"]),
                    ("Previous tab", ["Shift-Tab"]),
                    ("Tag guide", ["g"]),
                    ("Multi-selection mode", ["v"]),
                ),
            ),

            Focus::FloatingWindow(ref float) => float.get_shortcut_list(),
            Focus::ConfirmationPrompt(ref prompt) => prompt.get_shortcut_list(),
            Focus::FilePicker(ref picker, _) => picker.get_shortcut_list(),
            Focus::SetupWizard(ref wizard) => wizard.get_shortcut_list(),
        }
    }

    fn is_terminal_drawable(&mut self, terminal_size: Rect) -> bool {
        !(self.size_bypass || matches!(self.focus, Focus::FloatingWindow(_)))
            && (terminal_size.height < MIN_HEIGHT || terminal_size.width < MIN_WIDTH)
    }

    pub fn draw(&mut self, frame: &mut Frame) {
        let area = frame.area();
        self.drawable = !self.is_terminal_drawable(area);
        if !self.drawable {
            let warning = Paragraph::new(format!(
                "Terminal size too small:\nWidth = {} Height = {}\n\nMinimum size:\nWidth = {}  Height = {}",
                area.width,
                area.height,
                MIN_WIDTH,
                MIN_HEIGHT,
            ))
                .alignment(Alignment::Center)
                .style(Style::default().fg(self.theme.fail_color()).bold())
                .wrap(ratatui::widgets::Wrap { trim: true });

            let centered_layout = Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Fill(1),
                    Constraint::Length(5),
                    Constraint::Fill(1),
                ])
                .split(area);

            return frame.render_widget(warning, centered_layout[1]);
        }

        let (keybind_scope, shortcuts) = self.get_keybinds();

        let keybinds_block = Block::bordered()
            .title(format!(" {keybind_scope} "))
            .border_set(border::PLAIN)
            .border_style(Style::default().fg(self.theme.unfocused_color()))
            .title_style(Style::default().fg(self.theme.tab_color()).bold())
            .padding(Padding::horizontal(1));

        let keybind_render_width = keybinds_block.inner(area).width;
        let keybinds = create_shortcut_list(shortcuts, keybind_render_width);
        let keybind_len = keybinds.len() as u16;
        let keybind_para = Paragraph::new(Text::from_iter(keybinds)).block(keybinds_block);

        let vertical =
            Layout::vertical([Constraint::Percentage(0), Constraint::Max(keybind_len + 2)])
                .flex(Flex::Legacy)
                .split(area);

        let horizontal = Layout::horizontal([
            Constraint::Min(self.longest_tab_display_len + 7 + LEFT_EXTRA_WIDTH),
            Constraint::Percentage(100),
        ])
        .split(vertical[0]);

        let info_height = self
            .system_info
            .as_ref()
            .map(|info| info.entries_len() as u16 + 2)
            .unwrap_or(0);
        let show_info = info_height > 0 && horizontal[0].height > info_height.saturating_add(3);

        let reserved_info_height = if show_info { info_height } else { 0 };
        let max_logo_area_height = horizontal[0]
            .height
            .saturating_sub(reserved_info_height)
            .saturating_sub(1);
        let logo_height = if let Some(logo) = &self.logo {
            logo.area_height_for_width(horizontal[0].width, max_logo_area_height)
        } else {
            max_logo_area_height.min(1)
        };
        let left_chunks = if show_info {
            Layout::vertical([
                Constraint::Length(logo_height),
                Constraint::Min(1),
                Constraint::Length(info_height),
            ])
            .split(horizontal[0])
        } else {
            Layout::vertical([Constraint::Length(logo_height), Constraint::Min(1)])
                .split(horizontal[0])
        };
        if let Some(logo) = &mut self.logo {
            logo.draw(frame, left_chunks[0], &self.theme);
        } else {
            let label = Paragraph::new(Line::styled(
                format!("Open Genome v{}", env!("CARGO_PKG_VERSION")),
                Style::default().fg(self.theme.tab_color()).bold(),
            ))
            .alignment(Alignment::Center);
            frame.render_widget(label, left_chunks[0]);
        }

        let tabs = self
            .tabs
            .iter()
            .map(|tab| tab.name.as_str())
            .collect::<Vec<_>>();

        let tab_focus = matches!(self.focus, Focus::TabList);
        let tab_hl_style = if tab_focus {
            Style::default()
                .bg(self.theme.focused_color())
                .fg(Color::Black)
                .bold()
        } else {
            Style::default().fg(self.theme.unfocused_color())
        };
        let highlight_symbol = self.theme.tab_icon();
        let tab_border_style = if tab_focus {
            Style::default().fg(self.theme.focused_color())
        } else {
            Style::default().fg(self.theme.unfocused_color())
        };

        let tab_list = List::new(tabs)
            .block(
                Block::bordered()
                    .border_set(border::PLAIN)
                    .border_style(tab_border_style)
                    .padding(Padding::horizontal(1)),
            )
            .style(Style::default().fg(self.theme.tab_color()))
            .highlight_style(tab_hl_style)
            .highlight_symbol(highlight_symbol);
        frame.render_stateful_widget(tab_list, left_chunks[1], &mut self.current_tab);
        if show_info && left_chunks.len() > 2 {
            self.draw_system_info(frame, left_chunks[2]);
        }

        let chunks =
            Layout::vertical([Constraint::Length(3), Constraint::Min(1)]).split(horizontal[1]);

        self.filter.draw_searchbar(frame, chunks[0], &self.theme);
        let content_area = chunks[1];
        let checklist_height = self.setup_checklist.preferred_height(content_area);
        let (list_area, checklist_area) = if checklist_height > 0 {
            let content_chunks =
                Layout::vertical([Constraint::Min(8), Constraint::Length(checklist_height)])
                    .split(content_area);
            (content_chunks[0], Some(content_chunks[1]))
        } else {
            (content_area, None)
        };

        self.areas = Some(Areas {
            tab_list: left_chunks[1],
            list: list_area,
        });

        let title = if self.multi_select {
            &format!("{TITLE}[Multi-Select] ")
        } else {
            TITLE
        };

        #[cfg(feature = "tips")]
        let bottom_title = Line::from(format!(" {} ", self.tip))
            .bold()
            .fg(self.theme.unfocused_color())
            .centered();
        #[cfg(not(feature = "tips"))]
        let bottom_title = "";

        let task_list_title = Line::from(" TAGS ").right_aligned();
        let list_focus = matches!(self.focus, Focus::List);
        let list_dim_style = if list_focus {
            Style::default()
        } else {
            Style::default().dim()
        };
        let list_border_style = if list_focus {
            Style::default().fg(self.theme.focused_color())
        } else {
            Style::default().fg(self.theme.unfocused_color())
        };
        let list_block = Block::bordered()
            .border_set(border::PLAIN)
            .border_style(list_border_style)
            .title(title)
            .title(task_list_title)
            .title_bottom(bottom_title)
            .padding(Padding::horizontal(1));
        let list_inner_width = list_block.inner(list_area).width as usize;
        let list_content_width = list_inner_width.saturating_sub(LIST_HIGHLIGHT_SYMBOL.len());

        let mut items: Vec<Line> = Vec::with_capacity(self.filter.item_list().len());

        if !self.at_root() {
            items.push(
                Line::from(format!("{}  ..", self.theme.dir_icon()))
                    .style(self.theme.dir_color())
                    .patch_style(list_dim_style),
            );
        }

        items.extend(self.filter.item_list().iter().map(
            |ListEntry {
                 node, has_children, ..
             }| {
                let is_selected = self.selected_commands.contains(node);
                let (indicator, style) = if is_selected {
                    (self.theme.multi_select_icon(), Style::new().bold())
                } else {
                    let ms_style = if self.multi_select && !node.multi_select {
                        Style::new().fg(self.theme.multi_select_disabled_color())
                    } else {
                        Style::new()
                    };
                    ("", ms_style)
                };
                if node.is_header {
                    Line::styled(
                        section_header(&node.name, list_content_width),
                        self.theme.unfocused_color(),
                    )
                    .patch_style(list_dim_style)
                } else if *has_children {
                    Line::styled(
                        format!("{}  {}", self.theme.dir_icon(), node.name,),
                        self.theme.dir_color(),
                    )
                    .patch_style(style)
                    .patch_style(list_dim_style)
                } else {
                    let left_content =
                        format!("{}  {} {}", self.theme.cmd_icon(), node.name, indicator);
                    let right_content = format!("{} ", node.task_list);
                    let center_space = " ".repeat(
                        list_content_width.saturating_sub(left_content.len() + right_content.len()),
                    );
                    Line::styled(
                        format!("{left_content}{center_space}{right_content}"),
                        self.theme.cmd_color(),
                    )
                    .patch_style(style)
                    .patch_style(list_dim_style)
                }
            },
        ));

        let list_highlight_style = if list_focus {
            Style::default()
                .bg(self.theme.focused_color())
                .fg(Color::Black)
                .bold()
        } else {
            list_dim_style
        };
        let list_highlight_symbol = if list_focus {
            LIST_HIGHLIGHT_SYMBOL
        } else {
            "  "
        };

        // Create the list widget with items
        let list = List::new(items)
            .highlight_style(list_highlight_style)
            .highlight_symbol(list_highlight_symbol)
            .block(list_block)
            .scroll_padding(1);
        frame.render_stateful_widget(list, list_area, &mut self.selection);

        if let Some(checklist_area) = checklist_area {
            self.setup_checklist
                .draw(frame, checklist_area, &self.theme);
        }

        match &mut self.focus {
            Focus::FloatingWindow(float) => float.draw(frame, content_area, &self.theme),
            Focus::ConfirmationPrompt(prompt) => prompt.draw(frame, content_area, &self.theme),
            Focus::FilePicker(picker, _) => picker.draw(frame, content_area, &self.theme),
            Focus::SetupWizard(wizard) => wizard.draw(frame, content_area, &self.theme),
            _ => {}
        }

        frame.render_widget(keybind_para, vertical[1]);
    }

    pub fn handle_mouse(&mut self, event: &MouseEvent) -> bool {
        if !self.mouse_enabled {
            return true;
        }

        if !self.drawable {
            return true;
        }

        if matches!(self.focus, Focus::TabList | Focus::List) {
            let position = Position::new(event.column, event.row);
            let mouse_in_tab_list = self.areas.as_ref().unwrap().tab_list.contains(position);
            let mouse_in_list = self.areas.as_ref().unwrap().list.contains(position);

            match event.kind {
                MouseEventKind::Moved => {
                    if mouse_in_list {
                        self.focus = Focus::List
                    } else if mouse_in_tab_list {
                        self.focus = Focus::TabList
                    }
                }
                MouseEventKind::ScrollDown => {
                    if mouse_in_tab_list {
                        if self.current_tab.selected().unwrap() != self.tabs.len() - 1 {
                            self.current_tab.select_next();
                        }
                        self.refresh_tab();
                    } else if mouse_in_list {
                        self.selection.select_next()
                    }
                }
                MouseEventKind::ScrollUp => {
                    if mouse_in_tab_list {
                        if self.current_tab.selected().unwrap() != 0 {
                            self.current_tab.select_previous();
                        }
                        self.refresh_tab();
                    } else if mouse_in_list {
                        self.selection.select_previous()
                    }
                }
                _ => {}
            }
        }
        match &mut self.focus {
            Focus::FloatingWindow(float) => {
                float.handle_mouse_event(event);
            }
            Focus::ConfirmationPrompt(confirm) => {
                confirm.content.handle_mouse_event(event);
            }
            Focus::FilePicker(picker, _) => {
                picker.handle_mouse_event(event);
            }
            Focus::SetupWizard(wizard) => {
                wizard.handle_mouse_event(event);
            }
            _ => {}
        }
        true
    }

    pub fn handle_key(&mut self, key: &KeyEvent) -> bool {
        // This should be defined first to allow closing
        // the application even when not drawable ( If terminal is small )
        // Exit on 'q' or 'Ctrl-c' input
        if matches!(self.focus, Focus::TabList | Focus::List)
            && (key.code == KeyCode::Char('q')
                || key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c'))
        {
            return false;
        }

        if matches!(self.focus, Focus::ConfirmationPrompt(_))
            && (key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c'))
        {
            return false;
        }

        // If UI is not drawable returning true will mark as the key handled
        if !self.drawable {
            return true;
        }

        // Handle key only when Tablist or List is focused
        // Prevents exiting the application even when a command is running
        // Add keys here which should work on both TabList and List
        if matches!(self.focus, Focus::TabList | Focus::List)
            && self.handle_tablist_and_list_keys(key)
        {
            return true;
        }

        if let Focus::FloatingWindow(command) = &mut self.focus {
            if command.handle_key_event(key) {
                self.focus = Focus::List;
            }
            return true;
        }

        if matches!(self.focus, Focus::FilePicker(_, _)) {
            let mut command_to_run = None;
            if let Focus::FilePicker(picker, action) = &mut self.focus {
                if picker.handle_key_event(key) {
                    command_to_run = picker
                        .content
                        .take_selected()
                        .map(|path| setup_script_command(&action.script, &path));
                } else {
                    return true;
                }
            }
            self.focus = Focus::List;
            if let Some(command) = command_to_run {
                self.spawn_float(command, FLOAT_SIZE, FLOAT_SIZE);
            }
            return true;
        }

        if matches!(self.focus, Focus::SetupWizard(_)) {
            let mut command_to_run = None;
            if let Focus::SetupWizard(wizard) = &mut self.focus {
                if wizard.handle_key_event(key) {
                    command_to_run = wizard
                        .content
                        .take_command_script()
                        .map(RunningCommand::new_shell);
                } else {
                    return true;
                }
            }
            self.focus = Focus::List;
            if let Some(command) = command_to_run {
                self.spawn_float(command, FLOAT_SIZE, FLOAT_SIZE);
            }
            return true;
        }

        match &mut self.focus {
            Focus::ConfirmationPrompt(confirm) => {
                confirm.content.handle_key_event(key);
                match confirm.content.status {
                    ConfirmStatus::Abort => {
                        self.focus = Focus::List;
                        // selected command was pushed to selection list if multi-select was
                        // enabled, need to clear it to prevent state corruption
                        if !self.multi_select {
                            self.selected_commands.clear()
                        } else {
                            // Prevents non multi_selectable cmd from being pushed into the selected list
                            if let Some(node) = self.get_selected_node() {
                                if !node.multi_select {
                                    self.selected_commands.retain(|cmd| cmd.name != node.name);
                                }
                            }
                        }
                    }
                    ConfirmStatus::Confirm => self.handle_confirm_command(),
                    ConfirmStatus::None => {}
                }
            }

            Focus::Search => match self.filter.handle_key(key) {
                SearchAction::Exit => self.exit_search(),
                SearchAction::Update => self.update_items(),
                SearchAction::None => {}
            },

            Focus::TabList => match key.code {
                KeyCode::Enter | KeyCode::Char('l') | KeyCode::Right => self.focus = Focus::List,
                KeyCode::Char('j') | KeyCode::Down => self.scroll_tab_down(),
                KeyCode::Char('k') | KeyCode::Up => self.scroll_tab_up(),

                _ => {}
            },

            Focus::List if key.kind != KeyEventKind::Release => match key.code {
                KeyCode::Char('j') | KeyCode::Down => self.scroll_down(),
                KeyCode::Char('k') | KeyCode::Up => self.scroll_up(),
                KeyCode::Char('p') | KeyCode::Char('P') => self.enable_preview(),
                KeyCode::Char('d') | KeyCode::Char('D') => self.enable_description(),
                KeyCode::Enter | KeyCode::Char('l') | KeyCode::Right => self.handle_enter(),
                KeyCode::Char('h') | KeyCode::Left => self.go_back(),
                KeyCode::Char(' ') if self.multi_select => self.toggle_selection(),
                _ => {}
            },

            _ => (),
        };
        true
    }

    fn handle_tablist_and_list_keys(&mut self, key: &KeyEvent) -> bool {
        match key.code {
            KeyCode::Tab => self.scroll_tab_down(),
            KeyCode::BackTab => self.scroll_tab_up(),
            KeyCode::Char('/') => self.enter_search(),
            KeyCode::Char('g') | KeyCode::Char('G') => self.enable_task_list_guide(),
            KeyCode::Char('v') | KeyCode::Char('V') => self.toggle_multi_select(),
            KeyCode::Char('t') => self.theme.next(),
            KeyCode::Char('T') => self.theme.prev(),
            _ => return false,
        }
        true
    }

    fn scroll(&mut self, direction: ScrollDir) {
        let Some(selected) = self.selection.selected() else {
            return;
        };
        let list_len = if !self.at_root() {
            self.filter.item_list().len() + 1
        } else {
            self.filter.item_list().len()
        };

        if list_len == 0 {
            return;
        };

        let next_selection = match direction {
            ScrollDir::Up if selected == 0 => list_len - 1,
            ScrollDir::Down if selected >= list_len - 1 => 0,
            ScrollDir::Up => selected - 1,
            ScrollDir::Down => selected + 1,
        };
        self.selection.select(Some(next_selection));
    }

    fn scroll_up(&mut self) {
        self.scroll(ScrollDir::Up)
    }

    fn scroll_down(&mut self) {
        self.scroll(ScrollDir::Down)
    }

    fn toggle_multi_select(&mut self) {
        self.multi_select = !self.multi_select;
        if !self.multi_select {
            self.selected_commands.clear();
        }
    }

    fn toggle_selection(&mut self) {
        if let Some(node) = self.get_selected_node() {
            if node.multi_select {
                if self.selected_commands.contains(&node) {
                    self.selected_commands.retain(|c| c != &node);
                } else {
                    self.selected_commands.push(node);
                }
            }
        }
    }

    fn update_items(&mut self) {
        self.filter.update_items(
            &self.tabs,
            self.current_tab.selected().unwrap(),
            self.visit_stack.last().unwrap().0,
        );

        let len = self.filter.item_list().len();
        if len > 0 {
            let current = self.selection.selected().unwrap_or(0);
            self.selection.select(Some(current.min(len - 1)));
        } else {
            self.selection.select(None);
        }
    }

    /// Checks either the current tree node is the root node (can we go up the tree or no)
    /// Returns `true` if we can't go up the tree (we are at the tree root)
    /// else returns `false`
    pub fn at_root(&self) -> bool {
        self.visit_stack.len() == 1
    }

    fn go_back(&mut self) {
        if self.at_root() {
            self.focus = Focus::TabList;
        } else {
            self.enter_parent_directory();
        }
    }

    fn enter_parent_directory(&mut self) {
        if let Some((_, previous_position)) = self.visit_stack.pop() {
            self.selection.select(Some(previous_position));
            self.update_items();
        }
    }

    fn get_selected_node(&self) -> Option<Rc<ListNode>> {
        let mut selected_index = self.selection.selected().unwrap_or(0);

        if !self.at_root() {
            if selected_index == 0 {
                return None;
            } else {
                selected_index = selected_index.saturating_sub(1);
            }
        }

        if let Some(item) = self.filter.item_list().get(selected_index) {
            if is_action_node(&item.node) {
                return Some(item.node.clone());
            }
        }
        None
    }

    fn get_selected_description(&self) -> Option<String> {
        self.get_selected_node()
            .map(|node| node.description.clone())
    }

    pub fn go_to_selected_dir(&mut self) {
        let selected_index = self.selection.selected().unwrap_or(0);

        if !self.at_root() && selected_index == 0 {
            self.enter_parent_directory();
            return;
        }

        let actual_index = if self.at_root() {
            selected_index
        } else {
            selected_index - 1
        };

        if let Some(item) = self.filter.item_list().get(actual_index) {
            if item.has_children {
                self.visit_stack.push((item.id, selected_index));
                self.selection.select(Some(0));
                self.update_items();
            }
        }
    }

    pub fn selected_item_is_dir(&self) -> bool {
        let mut selected_index = self.selection.selected().unwrap_or(0);

        if !self.at_root() {
            if selected_index == 0 {
                return false;
            } else {
                selected_index = selected_index.saturating_sub(1);
            }
        }

        self.filter
            .item_list()
            .get(selected_index)
            .is_some_and(|i| i.has_children && !i.node.is_header)
    }

    pub fn selected_item_is_cmd(&self) -> bool {
        let mut selected_index = self.selection.selected().unwrap_or(0);

        if !self.at_root() {
            if selected_index == 0 {
                return false;
            } else {
                selected_index = selected_index.saturating_sub(1);
            }
        }

        self.filter
            .item_list()
            .get(selected_index)
            .is_some_and(|item| is_action_node(&item.node))
    }

    pub fn selected_item_is_up_dir(&self) -> bool {
        let selected_index = self.selection.selected().unwrap_or(0);
        !self.at_root() && selected_index == 0
    }

    fn enable_preview(&mut self) {
        if let Some(list_node) = self.get_selected_node() {
            let preview_title = format!("[Preview] - {}", list_node.name.as_str());
            let preview = FloatingText::from_command(&list_node.command, &preview_title, false);
            self.spawn_float(preview, FLOAT_SIZE, FLOAT_SIZE);
        }
    }

    fn enable_description(&mut self) {
        if let Some(command_description) = self.get_selected_description() {
            if !command_description.is_empty() {
                let description = FloatingText::new(command_description, "Action Details", true);
                self.spawn_float(description, FLOAT_SIZE, FLOAT_SIZE);
            }
        }
    }

    fn enable_task_list_guide(&mut self) {
        self.spawn_float(
            FloatingText::new(ACTIONS_GUIDE.to_string(), "Tag Guide", true),
            FLOAT_SIZE,
            FLOAT_SIZE,
        );
    }

    fn get_selected_item_type(&self) -> SelectedItem {
        if self.selected_item_is_up_dir() {
            SelectedItem::UpDir
        } else if self.selected_item_is_dir() {
            SelectedItem::Directory
        } else if self.selected_item_is_cmd() {
            SelectedItem::Command
        } else {
            SelectedItem::None
        }
    }

    fn handle_enter(&mut self) {
        match self.get_selected_item_type() {
            SelectedItem::UpDir => self.enter_parent_directory(),
            SelectedItem::Directory => self.go_to_selected_dir(),
            SelectedItem::Command => {
                if self.selected_commands.is_empty() {
                    if let Some(node) = self.get_selected_node() {
                        if self.spawn_setup_wizard(&node) {
                            return;
                        }
                        if self.spawn_setup_path_picker(&node) {
                            return;
                        }
                        self.selected_commands.push(node);
                    }
                }
                self.spawn_confirmprompt();
            }
            SelectedItem::None => {}
        }
    }

    fn handle_confirm_command(&mut self) {
        let commands: Vec<&Command> = self
            .selected_commands
            .iter()
            .map(|node| &node.command)
            .collect();

        let command = RunningCommand::new(&commands);
        self.spawn_float(command, FLOAT_SIZE, FLOAT_SIZE);
        self.selected_commands.clear();
    }

    fn spawn_setup_path_picker(&mut self, node: &ListNode) -> bool {
        let Some(action) = setup_path_action(&node.command) else {
            return false;
        };
        let start = current_manifest_path(&action.script, action.manifest_key)
            .unwrap_or_else(|| default_start_path(action.mode));
        let picker = FilePicker::new(action.title, action.mode, start);
        self.focus =
            Focus::FilePicker(Float::new(Box::new(picker), FLOAT_SIZE, FLOAT_SIZE), action);
        true
    }

    fn spawn_setup_wizard(&mut self, node: &ListNode) -> bool {
        let Some(script) = setup_wizard_script(&node.command) else {
            return false;
        };
        let Some(script_dir) = script.parent().map(Path::to_path_buf) else {
            return false;
        };
        let default = default_start_path(FilePickerMode::Directory);
        let starts = SetupWizardStarts {
            workdir: current_manifest_path(&script, "paths.workdir")
                .unwrap_or_else(|| default.clone()),
            dataset: current_manifest_path(&script, "paths.dataset")
                .unwrap_or_else(|| default.clone()),
            reference: current_manifest_path(&script, "paths.reference").unwrap_or(default),
        };
        let wizard = SetupWizard::new(script_dir, starts);
        self.focus = Focus::SetupWizard(Float::new(Box::new(wizard), FLOAT_SIZE, FLOAT_SIZE));
        true
    }

    fn spawn_float<T: FloatContent + 'static>(&mut self, float: T, width: u16, height: u16) {
        self.focus = Focus::FloatingWindow(Float::new(Box::new(float), width, height));
    }

    fn enter_search(&mut self) {
        self.focus = Focus::Search;
        self.filter.activate_search();
        self.selection.select(None);
    }

    fn exit_search(&mut self) {
        self.selection.select(Some(0));
        self.focus = Focus::List;
        self.filter.deactivate_search();
        self.update_items();
    }

    fn refresh_tab(&mut self) {
        self.visit_stack = vec![(
            self.tabs[self.current_tab.selected().unwrap()]
                .tree
                .root()
                .id(),
            0usize,
        )];
        self.selection.select(Some(0));
        self.filter.clear_search();
        self.update_items();
    }

    fn scroll_tab_down(&mut self) {
        if self.current_tab.selected().unwrap() == self.tabs.len() - 1 {
            self.current_tab.select_first();
        } else {
            self.current_tab.select_next();
        }
        self.refresh_tab();
    }

    fn scroll_tab_up(&mut self) {
        if self.current_tab.selected().unwrap() == 0 {
            self.current_tab.select(Some(self.tabs.len() - 1));
        } else {
            self.current_tab.select_previous();
        }
        self.refresh_tab();
    }

    fn draw_system_info(&self, frame: &mut Frame, area: Rect) {
        let Some(info) = &self.system_info else {
            return;
        };

        let block = Block::bordered()
            .border_set(border::PLAIN)
            .border_style(Style::default().fg(self.theme.unfocused_color()))
            .title(" SYSTEM ")
            .title_style(Style::default().fg(self.theme.tab_color()).bold())
            .padding(Padding::horizontal(1));

        let inner_width = block.inner(area).width as usize;
        let text = Text::from(info.render_lines(&self.theme, inner_width));
        frame.render_widget(Paragraph::new(text).block(block), area);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::{backend::TestBackend, Terminal};

    #[test]
    fn setup_results_path_uses_native_directory_picker() {
        let command = Command::LocalFile {
            executable: "sh".to_string(),
            args: Vec::new(),
            file: PathBuf::from("/tmp/open_genome_scripts/setup/scripts/set_results_path.sh"),
        };

        let action = setup_path_action(&command).expect("results action should use picker");

        assert_eq!(action.title, "Choose Existing Results Folder");
        assert!(matches!(action.mode, FilePickerMode::Directory));
        assert_eq!(action.manifest_key, "workflow.outdir");
    }

    #[test]
    fn render_setup_snapshot_when_requested() {
        let Some(path) = std::env::var_os("OPEN_GENOME_SETUP_TAB_SNAPSHOT") else {
            return;
        };

        let mut state = AppState::new(Args {
            config: None,
            theme: Theme::Default,
            skip_confirmation: false,
            override_validation: false,
            size_bypass: false,
            mouse: false,
            bypass_root: true,
            demo_output: false,
            human_validation_output: false,
        });
        let backend = TestBackend::new(140, 42);
        let mut terminal = Terminal::new(backend).unwrap();

        terminal.draw(|frame| state.draw(frame)).unwrap();

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
