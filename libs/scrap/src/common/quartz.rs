use crate::{quartz, Frame, Pixfmt};
use std::marker::PhantomData;
use std::sync::{Arc, Mutex, TryLockError};
use std::{fs, io, mem};

const UNILINK_WINDOW_CAPTURE_RECT_PATH: &str = "/tmp/unilink_control_window_capture_rect";

#[derive(Clone, Copy, Debug)]
pub struct UniLinkWindowCaptureRect {
    pub x: i32,
    pub y: i32,
    pub width: usize,
    pub height: usize,
}

pub fn unilink_window_capture_rect() -> Option<UniLinkWindowCaptureRect> {
    let text = fs::read_to_string(UNILINK_WINDOW_CAPTURE_RECT_PATH).ok()?;
    let parts = text
        .split(|c: char| c.is_ascii_whitespace() || c == ',')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>();
    if parts.len() < 4 {
        return None;
    }
    let x = parts[0].parse::<i32>().ok()?;
    let y = parts[1].parse::<i32>().ok()?;
    let width = parts[2].parse::<usize>().ok()?;
    let height = parts[3].parse::<usize>().ok()?;
    if width <= 1 || height <= 1 {
        return None;
    }
    Some(UniLinkWindowCaptureRect {
        x,
        y,
        width,
        height,
    })
}

pub struct Capturer {
    inner: quartz::Capturer,
    frame: Arc<Mutex<Option<quartz::Frame>>>,
    saved_raw_data: Vec<u8>, // for faster compare and copy
}

impl Capturer {
    pub fn new(display: Display) -> io::Result<Capturer> {
        let frame = Arc::new(Mutex::new(None));

        let f = frame.clone();
        let inner = quartz::Capturer::new(
            display.0,
            display.width(),
            display.height(),
            quartz::PixelFormat::Argb8888,
            Default::default(),
            move |inner| {
                if let Ok(mut f) = f.lock() {
                    *f = Some(inner);
                }
            },
        )
        .map_err(|_| io::Error::from(io::ErrorKind::Other))?;

        Ok(Capturer {
            inner,
            frame,
            saved_raw_data: Vec::new(),
        })
    }

    pub fn width(&self) -> usize {
        self.inner.width()
    }

    pub fn height(&self) -> usize {
        self.inner.height()
    }
}

impl crate::TraitCapturer for Capturer {
    fn frame<'a>(&'a mut self, _timeout_ms: std::time::Duration) -> io::Result<Frame<'a>> {
        match self.frame.try_lock() {
            Ok(mut handle) => {
                let mut frame = None;
                mem::swap(&mut frame, &mut handle);

                match frame {
                    Some(mut frame) => {
                        crate::would_block_if_equal(&mut self.saved_raw_data, frame.inner())?;
                        frame.surface_to_bgra(self.height());
                        if let Some(rect) = unilink_window_capture_rect() {
                            if let Some(buffer) = self.crop_frame_to_window(&frame, rect) {
                                return Ok(Frame::PixelBuffer(buffer));
                            }
                        }
                        Ok(Frame::PixelBuffer(PixelBuffer {
                            kind: PixelBufferKind::Surface {
                                frame,
                                data: PhantomData,
                            },
                            width: self.width(),
                            height: self.height(),
                            stride: self.width() * 4,
                        }))
                    }

                    None => Err(io::ErrorKind::WouldBlock.into()),
                }
            }

            Err(TryLockError::WouldBlock) => Err(io::ErrorKind::WouldBlock.into()),

            Err(TryLockError::Poisoned(..)) => Err(io::ErrorKind::Other.into()),
        }
    }
}

impl Capturer {
    fn crop_frame_to_window<'a>(
        &self,
        frame: &quartz::Frame,
        rect: UniLinkWindowCaptureRect,
    ) -> Option<PixelBuffer<'a>> {
        let bounds = self.inner.display().bounds();
        let origin_x = bounds.origin.x.round() as i32;
        let origin_y = bounds.origin.y.round() as i32;
        let full_width = self.width();
        let full_height = self.height();
        let left = (rect.x - origin_x).max(0) as usize;
        let top = (rect.y - origin_y).max(0) as usize;
        if left >= full_width || top >= full_height {
            return None;
        }
        let width = rect.width.min(full_width - left);
        let height = rect.height.min(full_height - top);
        if width <= 1 || height <= 1 {
            return None;
        }
        let src_stride = frame.stride();
        let src = &**frame;
        let dst_stride = width * 4;
        let mut data = vec![0; dst_stride * height];
        for row in 0..height {
            let src_start = (top + row) * src_stride + left * 4;
            let src_end = src_start + dst_stride;
            let dst_start = row * dst_stride;
            let dst_end = dst_start + dst_stride;
            if src_end > src.len() || dst_end > data.len() {
                return None;
            }
            data[dst_start..dst_end].copy_from_slice(&src[src_start..src_end]);
        }
        Some(PixelBuffer {
            kind: PixelBufferKind::Owned { data },
            width,
            height,
            stride: dst_stride,
        })
    }
}

pub struct PixelBuffer<'a> {
    kind: PixelBufferKind<'a>,
    width: usize,
    height: usize,
    stride: usize,
}

enum PixelBufferKind<'a> {
    Surface {
        frame: quartz::Frame,
        data: PhantomData<&'a [u8]>,
    },
    Owned {
        data: Vec<u8>,
    },
}

impl<'a> crate::TraitPixelBuffer for PixelBuffer<'a> {
    fn data(&self) -> &[u8] {
        match &self.kind {
            PixelBufferKind::Surface { frame, .. } => &*frame,
            PixelBufferKind::Owned { data } => data,
        }
    }

    fn width(&self) -> usize {
        self.width
    }

    fn height(&self) -> usize {
        self.height
    }

    fn stride(&self) -> Vec<usize> {
        let mut v = Vec::new();
        v.push(self.stride);
        v
    }

    fn pixfmt(&self) -> Pixfmt {
        Pixfmt::BGRA
    }
}

pub struct Display(quartz::Display);

impl Display {
    pub fn primary() -> io::Result<Display> {
        Ok(Display(quartz::Display::primary()))
    }

    pub fn all() -> io::Result<Vec<Display>> {
        Ok(quartz::Display::online()
            .map_err(|_| io::Error::from(io::ErrorKind::Other))?
            .into_iter()
            .map(Display)
            .collect())
    }

    pub fn width(&self) -> usize {
        self.0.width()
    }

    pub fn height(&self) -> usize {
        self.0.height()
    }

    pub fn scale(&self) -> f64 {
        self.0.scale()
    }

    pub fn name(&self) -> String {
        self.0.id().to_string()
    }

    pub fn is_online(&self) -> bool {
        self.0.is_online()
    }

    pub fn origin(&self) -> (i32, i32) {
        let o = self.0.bounds().origin;
        (o.x as _, o.y as _)
    }

    pub fn is_primary(&self) -> bool {
        self.0.is_primary()
    }
}
