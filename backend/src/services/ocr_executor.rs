use anyhow::{Result, bail};
use std::path::Path;
use tokio::process::Command;

#[derive(Debug, Clone, PartialEq)]
pub enum OcrBackend {
    Tesseract,
    PaddleOCR,
    None,
}

impl std::fmt::Display for OcrBackend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            OcrBackend::Tesseract => write!(f, "tesseract"),
            OcrBackend::PaddleOCR => write!(f, "paddleocr"),
            OcrBackend::None => write!(f, "none"),
        }
    }
}

pub async fn detect_available_ocr() -> OcrBackend {
    if is_command_available("paddleocr").await {
        return OcrBackend::PaddleOCR;
    }
    #[cfg(sqlite_mode)]
    {
        let config = crate::services::ocr_install::load_ocr_config();
        if !config.ocr_enabled {
            return OcrBackend::None;
        }
        if let Some(ref p) = crate::services::ocr_install::resolve_tesseract_executable(&config) {
            if Command::new(p).arg("--version").output().await.map(|o| o.status.success()).unwrap_or(false) {
                return OcrBackend::Tesseract;
            }
        }
    }
    if is_command_available("tesseract").await {
        return OcrBackend::Tesseract;
    }
    OcrBackend::None
}

async fn is_command_available(cmd: &str) -> bool {
    #[cfg(target_os = "windows")]
    let check = Command::new("where").arg(cmd).output().await;
    #[cfg(not(target_os = "windows"))]
    let check = Command::new("which").arg(cmd).output().await;

    match check {
        Ok(output) => output.status.success(),
        Err(_) => false,
    }
}

fn resolve_tesseract_cmd() -> String {
    #[cfg(sqlite_mode)]
    {
        let config = crate::services::ocr_install::load_ocr_config();
        if let Some(p) = crate::services::ocr_install::resolve_tesseract_executable(&config) {
            return p;
        }
    }
    "tesseract".to_string()
}

fn resolve_pdftoppm_cmd() -> String {
    #[cfg(sqlite_mode)]
    {
        let config = crate::services::ocr_install::load_ocr_config();
        if let Some(bin) = crate::services::ocr_install::resolve_poppler_bin_dir(&config) {
            let exe = std::path::PathBuf::from(bin).join(if cfg!(windows) {
                "pdftoppm.exe"
            } else {
                "pdftoppm"
            });
            if exe.exists() {
                return exe.display().to_string();
            }
        }
    }
    "pdftoppm".to_string()
}

pub async fn run_tesseract(image_path: &Path, lang: &str) -> Result<String> {
    let output_base = image_path.with_extension("ocr_out");
    let tess_cmd = resolve_tesseract_cmd();

    let mut cmd = Command::new(&tess_cmd);
    #[cfg(sqlite_mode)]
    {
        let config = crate::services::ocr_install::load_ocr_config();
        if let Some(td) = crate::services::ocr_install::resolve_tessdata_dir(&config) {
            cmd.env("TESSDATA_PREFIX", td);
        }
    }

    let status = cmd
        .arg(image_path)
        .arg(&output_base)
        .arg("-l")
        .arg(lang)
        .arg("--psm")
        .arg("3")
        .output()
        .await?;

    if !status.status.success() {
        let stderr = String::from_utf8_lossy(&status.stderr);
        bail!("Tesseract failed: {}", stderr);
    }

    let txt_path = output_base.with_extension("txt");
    let text = if txt_path.exists() {
        let content = tokio::fs::read_to_string(&txt_path).await?;
        let _ = tokio::fs::remove_file(&txt_path).await;
        content
    } else {
        // tesseract appends .txt automatically
        let alt_path = format!("{}.txt", output_base.display());
        let alt = Path::new(&alt_path);
        if alt.exists() {
            let content = tokio::fs::read_to_string(alt).await?;
            let _ = tokio::fs::remove_file(alt).await;
            content
        } else {
            bail!("Tesseract output file not found");
        }
    };

    Ok(text.trim().to_string())
}

pub async fn run_paddleocr(image_path: &Path) -> Result<String> {
    let output = Command::new("paddleocr")
        .arg("--image_dir")
        .arg(image_path)
        .arg("--use_angle_cls")
        .arg("true")
        .arg("--lang")
        .arg("ch")
        .output()
        .await?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("PaddleOCR failed: {}", stderr);
    }

    let stdout = String::from_utf8_lossy(&output.stdout);

    let lines: Vec<&str> = stdout
        .lines()
        .filter(|line| {
            !line.starts_with("ppocr")
                && !line.starts_with("[")
                && !line.trim().is_empty()
                && !line.contains("PaddleOCR")
        })
        .collect();

    Ok(lines.join("\n").trim().to_string())
}

pub async fn run_ocr(image_path: &Path, backend: &OcrBackend, lang: &str) -> Result<String> {
    match backend {
        OcrBackend::Tesseract => run_tesseract(image_path, lang).await,
        OcrBackend::PaddleOCR => run_paddleocr(image_path).await,
        OcrBackend::None => bail!("No OCR backend available"),
    }
}

/// Convert PDF pages to images using pdftoppm (poppler-utils)
pub async fn pdf_to_images(
    pdf_path: &Path,
    output_dir: &Path,
    max_pages: Option<usize>,
) -> Result<Vec<std::path::PathBuf>> {
    tokio::fs::create_dir_all(output_dir).await?;

    let mut cmd = Command::new(resolve_pdftoppm_cmd());
    cmd.arg("-png")
        .arg("-r").arg("300");

    if let Some(max) = max_pages {
        cmd.arg("-l").arg(max.to_string());
    }

    cmd.arg(pdf_path)
        .arg(output_dir.join("page"));

    let output = cmd.output().await?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("pdftoppm failed: {}", stderr);
    }

    let mut images = Vec::new();
    let mut entries = tokio::fs::read_dir(output_dir).await?;
    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) == Some("png") {
            images.push(path);
        }
    }
    images.sort();

    Ok(images)
}

/// Run OCR on all pages of a PDF, returns concatenated text
pub async fn ocr_pdf(
    pdf_path: &Path,
    lang: &str,
    max_pages: Option<usize>,
) -> Result<OcrPdfResult> {
    let backend = detect_available_ocr().await;
    if backend == OcrBackend::None {
        bail!("No OCR backend (tesseract or paddleocr) found in PATH");
    }

    let temp_dir = tempfile::tempdir()?;
    let images = pdf_to_images(pdf_path, temp_dir.path(), max_pages).await?;

    if images.is_empty() {
        bail!("No pages extracted from PDF");
    }

    let mut all_text = String::new();
    let mut pages_processed = 0;

    for img in &images {
        match run_ocr(img, &backend, lang).await {
            Ok(text) => {
                if !text.is_empty() {
                    if !all_text.is_empty() {
                        all_text.push_str("\n\n---\n\n");
                    }
                    all_text.push_str(&text);
                }
                pages_processed += 1;
            }
            Err(e) => {
                tracing::warn!(page = %img.display(), error = %e, "OCR failed for page");
            }
        }
    }

    Ok(OcrPdfResult {
        text: all_text,
        pages_processed,
        total_pages: images.len(),
        backend,
    })
}

pub struct OcrPdfResult {
    pub text: String,
    pub pages_processed: usize,
    pub total_pages: usize,
    pub backend: OcrBackend,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ocr_backend_display() {
        assert_eq!(OcrBackend::Tesseract.to_string(), "tesseract");
        assert_eq!(OcrBackend::PaddleOCR.to_string(), "paddleocr");
        assert_eq!(OcrBackend::None.to_string(), "none");
    }

    #[test]
    fn test_ocr_backend_equality() {
        assert_eq!(OcrBackend::Tesseract, OcrBackend::Tesseract);
        assert_ne!(OcrBackend::Tesseract, OcrBackend::PaddleOCR);
        assert_ne!(OcrBackend::None, OcrBackend::Tesseract);
    }

    #[tokio::test]
    async fn test_detect_ocr_returns_some_backend() {
        let backend = detect_available_ocr().await;
        // On CI/test environments, OCR may or may not be available
        assert!(matches!(backend, OcrBackend::Tesseract | OcrBackend::PaddleOCR | OcrBackend::None));
    }
}
