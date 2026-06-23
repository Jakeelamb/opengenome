use crate::theme::Theme;
use image::{imageops::FilterType, RgbaImage};
use ratatui::{prelude::*, widgets::Paragraph};
use ratatui_image::{
    picker::{Picker, ProtocolType},
    protocol::StatefulProtocol,
    Resize, StatefulImage,
};
use std::time::Instant;

const LOGO_TEXT_GAP: u16 = 0;
const LOGO_ALPHA_CUTOFF: u8 = 10;
const LOGO_SCALE_NUM: u32 = 70;
const LOGO_SCALE_DEN: u32 = 100;
const HELIX_VIRTUAL_SIZE: (u32, u32) = (48, 12);
const HELIX_FONT: (u16, u16) = (1, 1);

enum Renderer {
    Protocol {
        protocol: Box<StatefulProtocol>,
        resize: Resize,
    },
    Blocks,
}

/// Optional PNG / half-block logo fallback.
pub(crate) struct ImageLogo {
    renderer: Renderer,
    rgba: RgbaImage,
    font_size: (u16, u16),
    image_size: (u32, u32),
    cached_size: (u16, u16),
    cached_lines: Vec<Line<'static>>,
    last_area_size: (u16, u16),
}

pub(crate) struct HelixLogo {
    started_at: Instant,
}

pub enum Logo {
    Helix(HelixLogo),
    Image(ImageLogo),
}

impl Logo {
    pub fn load() -> Option<Self> {
        if std::env::var("OPEN_GENOME_USE_PNG_LOGO").ok().as_deref() != Some("1") {
            return Some(Self::Helix(HelixLogo {
                started_at: Instant::now(),
            }));
        }
        ImageLogo::load().map(Logo::Image)
    }

    pub fn area_height_for_width(&self, width: u16, max_height: u16) -> u16 {
        match self {
            Logo::Helix(inner) => inner.area_height_for_width(width, max_height),
            Logo::Image(inner) => inner.area_height_for_width(width, max_height),
        }
    }

    pub fn draw(&mut self, frame: &mut Frame, area: Rect, theme: &Theme) {
        match self {
            Logo::Helix(inner) => inner.draw(frame, area, theme),
            Logo::Image(inner) => inner.draw(frame, area, theme),
        }
    }
}

impl ImageLogo {
    fn load() -> Option<Self> {
        let dyn_image =
            image::load_from_memory(include_bytes!("../assets/open_genome_logo.png")).ok()?;
        let rgba = dyn_image.to_rgba8();
        let image_size = rgba.dimensions();

        let mut picker = Picker::from_query_stdio().unwrap_or_else(|_| Picker::halfblocks());
        picker.set_background_color(Some([0, 0, 0, 0]));
        let font_size = picker.font_size();
        let font_size = (font_size.width, font_size.height);
        let renderer = if picker.protocol_type() == ProtocolType::Halfblocks {
            Renderer::Blocks
        } else {
            let protocol =
                Box::new(picker.new_resize_protocol(image::DynamicImage::ImageRgba8(rgba.clone())));
            Renderer::Protocol {
                protocol,
                resize: Resize::Scale(Some(FilterType::Triangle)),
            }
        };

        Some(Self {
            renderer,
            rgba,
            font_size,
            image_size,
            cached_size: (0, 0),
            cached_lines: Vec::new(),
            last_area_size: (0, 0),
        })
    }

    fn area_height_for_width(&self, width: u16, max_height: u16) -> u16 {
        if width == 0 || max_height == 0 {
            return 0;
        }

        let scaled_width = self.scaled_width(width);
        let max_image_height = max_height.saturating_sub(LOGO_TEXT_GAP + 1);
        if max_image_height == 0 {
            return max_height.min(1);
        }

        let mut image_height = self.rows_for_width(scaled_width);
        if image_height > max_image_height {
            image_height = max_image_height;
        }

        image_height + LOGO_TEXT_GAP + 1
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect, theme: &Theme) {
        if area.height == 0 || area.width == 0 {
            return;
        }

        self.refresh_protocol_if_needed(area);

        let max_image_height = area.height.saturating_sub(LOGO_TEXT_GAP + 1);
        let (draw_width, draw_height) = self.draw_size(area.width, max_image_height);

        if draw_width > 0 && draw_height > 0 {
            let centered_x = area.x + area.width.saturating_sub(draw_width) / 2;
            let max_x = area.x + area.width.saturating_sub(draw_width);
            let image_x = centered_x.min(max_x);
            let image_area = Rect::new(image_x, area.y, draw_width, draw_height);
            let mut use_blocks = matches!(self.renderer, Renderer::Blocks);

            if !use_blocks {
                if let Renderer::Protocol { protocol, resize } = &mut self.renderer {
                    let widget =
                        StatefulImage::<StatefulProtocol>::default().resize(resize.clone());
                    frame.render_stateful_widget(widget, image_area, protocol.as_mut());
                    if let Some(result) = protocol.last_encoding_result() {
                        if result.is_err() {
                            use_blocks = true;
                        }
                    }
                }
            }

            if use_blocks {
                self.renderer = Renderer::Blocks;
                self.render_blocks(frame, image_area);
            }
        }

        let text_y = if draw_height > 0 {
            area.y + draw_height + LOGO_TEXT_GAP
        } else {
            area.y
        };
        if text_y < area.y + area.height {
            let text_area = Rect::new(area.x, text_y, area.width, 1);
            let label = Line::styled(
                format!("Open Genome v{}", env!("CARGO_PKG_VERSION")),
                Style::default().fg(theme.tab_color()).bold(),
            );
            let text = Paragraph::new(label).alignment(Alignment::Center);
            frame.render_widget(text, text_area);
        }
    }

    fn draw_size(&self, width: u16, max_height: u16) -> (u16, u16) {
        if width == 0 || max_height == 0 {
            return (0, 0);
        }

        let scaled_width = self.scaled_width(width);
        let mut draw_width = scaled_width;
        let mut draw_height = self.rows_for_width(draw_width);
        if draw_height > max_height {
            draw_height = max_height;
            draw_width = self.width_for_height(draw_height).min(scaled_width);
        }

        (draw_width, draw_height)
    }

    fn rows_for_width(&self, width: u16) -> u16 {
        if width == 0 || self.image_size.0 == 0 || self.font_size.0 == 0 || self.font_size.1 == 0 {
            return 0;
        }

        let pixel_width = u64::from(width) * u64::from(self.font_size.0);
        let scaled_pixel_height =
            u64::from(self.image_size.1) * pixel_width / u64::from(self.image_size.0);
        let row_height = u64::from(self.font_size.1);
        let rows = scaled_pixel_height.div_ceil(row_height);

        rows.min(u64::from(u16::MAX)) as u16
    }

    fn width_for_height(&self, height: u16) -> u16 {
        if height == 0 || self.image_size.1 == 0 || self.font_size.0 == 0 || self.font_size.1 == 0 {
            return 0;
        }

        let pixel_height = u64::from(height) * u64::from(self.font_size.1);
        let scaled_pixel_width =
            u64::from(self.image_size.0) * pixel_height / u64::from(self.image_size.1);
        let col_width = u64::from(self.font_size.0);
        let cols = scaled_pixel_width.div_ceil(col_width);

        cols.min(u64::from(u16::MAX)) as u16
    }

    fn render_blocks(&mut self, frame: &mut Frame, area: Rect) {
        if area.width == 0 || area.height == 0 {
            return;
        }

        let size = (area.width, area.height);
        if self.cached_size != size {
            self.cached_size = size;
            self.cached_lines.clear();

            let resized = image::imageops::resize(
                &self.rgba,
                area.width as u32,
                area.height as u32,
                FilterType::Triangle,
            );

            for y in 0..area.height {
                let mut spans = Vec::with_capacity(area.width as usize);
                for x in 0..area.width {
                    let pixel = resized.get_pixel(x as u32, y as u32).0;
                    if pixel[3] < LOGO_ALPHA_CUTOFF {
                        spans.push(Span::raw(" "));
                    } else {
                        spans.push(Span::styled(
                            "#",
                            Style::default().fg(Color::Rgb(pixel[0], pixel[1], pixel[2])),
                        ));
                    }
                }
                self.cached_lines.push(Line::from(spans));
            }
        }

        frame.render_widget(Paragraph::new(Text::from(self.cached_lines.clone())), area);
    }

    fn refresh_protocol_if_needed(&mut self, area: Rect) {
        let area_size = (area.width, area.height);
        if self.last_area_size == area_size {
            return;
        }
        self.last_area_size = area_size;

        if !matches!(self.renderer, Renderer::Protocol { .. }) {
            return;
        }

        let mut picker = match Picker::from_query_stdio() {
            Ok(picker) => picker,
            Err(_) => return,
        };
        picker.set_background_color(Some([0, 0, 0, 0]));
        let new_font_size = picker.font_size();
        let new_font_size = (new_font_size.width, new_font_size.height);
        let protocol_type = picker.protocol_type();

        if protocol_type == ProtocolType::Halfblocks {
            self.renderer = Renderer::Blocks;
            self.font_size = new_font_size;
            self.cached_size = (0, 0);
            return;
        }

        if self.font_size != new_font_size {
            self.font_size = new_font_size;
            self.renderer = Renderer::Protocol {
                protocol: Box::new(
                    picker.new_resize_protocol(image::DynamicImage::ImageRgba8(self.rgba.clone())),
                ),
                resize: Resize::Scale(Some(FilterType::Triangle)),
            };
        }
    }

    fn scaled_width(&self, width: u16) -> u16 {
        if width == 0 {
            return 0;
        }
        let scaled = (u32::from(width) * LOGO_SCALE_NUM + (LOGO_SCALE_DEN / 2)) / LOGO_SCALE_DEN;
        scaled.clamp(1, u16::MAX as u32) as u16
    }
}

impl HelixLogo {
    fn area_height_for_width(&self, width: u16, max_height: u16) -> u16 {
        if width == 0 || max_height == 0 {
            return 0;
        }
        let scaled_width = Self::scaled_width(width);
        let max_image_height = max_height.saturating_sub(LOGO_TEXT_GAP + 1);
        if max_image_height == 0 {
            return max_height.min(1);
        }
        let image_height = Self::rows_for_width(scaled_width).min(max_image_height);
        image_height + LOGO_TEXT_GAP + 1
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect, theme: &Theme) {
        if area.height == 0 || area.width == 0 {
            return;
        }

        let max_image_height = area.height.saturating_sub(LOGO_TEXT_GAP + 1);
        let (draw_width, draw_height) = Self::draw_size(area.width, max_image_height);
        if draw_width > 0 && draw_height > 0 {
            let image_x = area.x + area.width.saturating_sub(draw_width) / 2;
            let image_area = Rect::new(image_x, area.y, draw_width, draw_height);
            let elapsed = self.started_at.elapsed().as_secs_f32();
            let text = Text::from(self.render_lines(draw_width, draw_height, elapsed));
            frame.render_widget(
                Paragraph::new(text).alignment(Alignment::Center),
                image_area,
            );
        }

        let text_y = if draw_height > 0 {
            area.y + draw_height + LOGO_TEXT_GAP
        } else {
            area.y
        };
        if text_y < area.y + area.height {
            let text_area = Rect::new(area.x, text_y, area.width, 1);
            let label = Line::styled(
                format!("Open Genome v{}", env!("CARGO_PKG_VERSION")),
                Style::default().fg(theme.tab_color()).bold(),
            );
            frame.render_widget(
                Paragraph::new(label).alignment(Alignment::Center),
                text_area,
            );
        }
    }

    fn render_lines(&self, width: u16, height: u16, elapsed: f32) -> Vec<Line<'static>> {
        let w = usize::from(width);
        let h = usize::from(height);
        let mid = (h.saturating_sub(1)) as f32 / 2.0;
        let amplitude = (h as f32 * 0.34).max(1.0);
        let phase = elapsed * 3.0;
        let mut rows = vec![vec![Span::raw(" "); w]; h];

        for x in 0..w {
            let t = x as f32 / width.max(1) as f32 * std::f32::consts::TAU * 2.1 + phase;
            let a = (mid + amplitude * t.sin())
                .round()
                .clamp(0.0, (h - 1) as f32) as usize;
            let b = (mid + amplitude * (t + std::f32::consts::PI).sin())
                .round()
                .clamp(0.0, (h - 1) as f32) as usize;
            let cross = (a + b) / 2;
            let shade = ((t.cos() + 1.0) * 0.5 * 120.0) as u8;
            let color_a = Color::Rgb(82, 210, 255u8.saturating_sub(shade / 3));
            let color_b = Color::Rgb(255u8.saturating_sub(shade / 2), 132, 204);
            let color_cross = Color::Rgb(150, 170, 188);

            if x % 3 == 0 {
                Self::set_logo_cell(
                    &mut rows,
                    cross,
                    x,
                    Span::styled("|", Style::default().fg(color_cross)),
                );
            }
            Self::set_logo_cell(
                &mut rows,
                a,
                x,
                Span::styled("o", Style::default().fg(color_a).bold()),
            );
            Self::set_logo_cell(
                &mut rows,
                b,
                x,
                Span::styled("o", Style::default().fg(color_b).bold()),
            );
        }

        rows.into_iter().map(Line::from).collect()
    }

    fn set_logo_cell(rows: &mut [Vec<Span<'static>>], row: usize, col: usize, span: Span<'static>) {
        if let Some(cell) = rows.get_mut(row).and_then(|cells| cells.get_mut(col)) {
            *cell = span;
        }
    }

    fn scaled_width(width: u16) -> u16 {
        if width == 0 {
            return 0;
        }
        let scaled = (u32::from(width) * LOGO_SCALE_NUM + (LOGO_SCALE_DEN / 2)) / LOGO_SCALE_DEN;
        scaled.clamp(1, u16::MAX as u32) as u16
    }

    fn rows_for_width(width: u16) -> u16 {
        let (iw, ih) = HELIX_VIRTUAL_SIZE;
        let (fw, fh) = HELIX_FONT;
        if width == 0 || iw == 0 || fw == 0 || fh == 0 {
            return 0;
        }
        let pixel_width = u64::from(width) * u64::from(fw);
        let scaled_pixel_height = u64::from(ih) * pixel_width / u64::from(iw);
        let row_height = u64::from(fh);
        scaled_pixel_height
            .div_ceil(row_height)
            .min(u64::from(u16::MAX)) as u16
    }

    fn width_for_height(height: u16) -> u16 {
        let (iw, ih) = HELIX_VIRTUAL_SIZE;
        let (fw, fh) = HELIX_FONT;
        if height == 0 || ih == 0 || fw == 0 || fh == 0 {
            return 0;
        }
        let pixel_height = u64::from(height) * u64::from(fh);
        let scaled_pixel_width = u64::from(iw) * pixel_height / u64::from(ih);
        let col_width = u64::from(fw);
        scaled_pixel_width
            .div_ceil(col_width)
            .min(u64::from(u16::MAX)) as u16
    }

    fn draw_size(width: u16, max_height: u16) -> (u16, u16) {
        if width == 0 || max_height == 0 {
            return (0, 0);
        }
        let scaled_width = Self::scaled_width(width);
        let mut draw_width = scaled_width;
        let mut draw_height = Self::rows_for_width(draw_width);
        if draw_height > max_height {
            draw_height = max_height;
            draw_width = Self::width_for_height(draw_height).min(scaled_width);
        }
        (draw_width, draw_height)
    }
}
