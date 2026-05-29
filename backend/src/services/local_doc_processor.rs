use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct LocalParseResult {
    pub markdown: String,
    pub metadata: LocalDocMetadata,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct LocalDocMetadata {
    pub title: Option<String>,
    pub page_count: Option<i32>,
    pub language: Option<String>,
    #[serde(default)]
    pub ocr_used: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ocr_backend: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ocr_pages: Option<usize>,
}

pub fn parse_local(data: &[u8], filename: &str, file_type: &str) -> anyhow::Result<LocalParseResult> {
    match file_type {
        "txt" | "md" => parse_text(data, filename),
        "html" => parse_html(data, filename),
        "pdf" => parse_pdf(data, filename),
        "docx" => parse_docx_fallback(data, filename),
        _ => anyhow::bail!("Unsupported file type for local processing: {}", file_type),
    }
}

/// Async version that can fallback to OCR for scanned PDFs
pub async fn parse_local_with_ocr(
    data: &[u8],
    filename: &str,
    file_type: &str,
    ocr_enabled: bool,
    ocr_lang: &str,
    max_ocr_pages: Option<usize>,
) -> anyhow::Result<LocalParseResult> {
    let mut result = parse_local(data, filename, file_type)?;

    if file_type == "pdf" && ocr_enabled && result.markdown.contains("无法提取文本内容") {
        tracing::info!(filename, "PDF text empty, attempting OCR fallback");

        let ocr_backend = super::ocr_executor::detect_available_ocr().await;
        if ocr_backend == super::ocr_executor::OcrBackend::None {
            tracing::warn!("OCR requested but no backend available");
            return Ok(result);
        }

        let temp_dir = tempfile::tempdir()?;
        let pdf_path = temp_dir.path().join("input.pdf");
        tokio::fs::write(&pdf_path, data).await?;

        match super::ocr_executor::ocr_pdf(&pdf_path, ocr_lang, max_ocr_pages).await {
            Ok(ocr_result) => {
                if !ocr_result.text.is_empty() {
                    let title = result.metadata.title.clone()
                        .unwrap_or_else(|| strip_extension(filename).to_string());
                    result.markdown = text_to_markdown(&ocr_result.text, &title);
                    result.metadata.ocr_used = true;
                    result.metadata.ocr_backend = Some(ocr_result.backend.to_string());
                    result.metadata.ocr_pages = Some(ocr_result.pages_processed);
                    tracing::info!(
                        filename,
                        backend = %ocr_result.backend,
                        pages = ocr_result.pages_processed,
                        "OCR fallback successful"
                    );
                } else {
                    tracing::warn!(filename, "OCR returned empty text");
                }
            }
            Err(e) => {
                tracing::warn!(filename, error = %e, "OCR fallback failed");
            }
        }
    }

    Ok(result)
}

fn parse_text(data: &[u8], filename: &str) -> anyhow::Result<LocalParseResult> {
    let text = String::from_utf8_lossy(data).to_string();
    let title = filename
        .rsplit('/')
        .next()
        .and_then(|f| f.rsplit('.').last())
        .unwrap_or(filename)
        .to_string();

    Ok(LocalParseResult {
        markdown: text,
        metadata: LocalDocMetadata {
            title: Some(title),
            page_count: Some(1),
            language: None,
            ..Default::default()
        },
    })
}

fn parse_html(data: &[u8], filename: &str) -> anyhow::Result<LocalParseResult> {
    let html = String::from_utf8_lossy(data);

    let re_tags = regex::Regex::new(r"<[^>]+>")?;
    let re_spaces = regex::Regex::new(r"\s+")?;

    let text = re_tags.replace_all(&html, " ");
    let text = re_spaces.replace_all(&text, " ").trim().to_string();

    let title_re = regex::Regex::new(r"<title>([^<]+)</title>")?;
    let title = title_re
        .captures(&html)
        .and_then(|c| c.get(1).map(|m| m.as_str().to_string()))
        .unwrap_or_else(|| filename.to_string());

    Ok(LocalParseResult {
        markdown: text,
        metadata: LocalDocMetadata {
            title: Some(title),
            page_count: Some(1),
            language: None,
            ..Default::default()
        },
    })
}

fn parse_pdf(data: &[u8], filename: &str) -> anyhow::Result<LocalParseResult> {
    #[cfg(feature = "local-pdf")]
    {
        parse_pdf_with_lopdf(data, filename)
    }
    #[cfg(not(feature = "local-pdf"))]
    {
        let _ = (data, filename);
        anyhow::bail!(
            "PDF parsing is not available in this build. \
             Use the desktop or mobile build, or the external doc-processor service."
        )
    }
}

#[cfg(feature = "local-pdf")]
fn parse_pdf_with_lopdf(data: &[u8], filename: &str) -> anyhow::Result<LocalParseResult> {
    use std::io::Cursor;

    let doc = lopdf::Document::load_from(Cursor::new(data))
        .map_err(|e| anyhow::anyhow!("Failed to load PDF: {}", e))?;

    let pages = doc.get_pages();
    let page_count = pages.len() as i32;

    let page_numbers: Vec<u32> = {
        let mut nums: Vec<u32> = pages.keys().copied().collect();
        nums.sort();
        nums
    };

    let raw_text = doc
        .extract_text(&page_numbers)
        .unwrap_or_default();

    if raw_text.trim().is_empty() {
        return Ok(LocalParseResult {
            markdown: format!(
                "# {}\n\n**此 PDF 无法提取文本内容**（可能是扫描版或纯图片 PDF）。\n\n\
                 - 检测到 {} 页\n\
                 - 如需解析此类文件，请在「设置 → OCR 组件管理」中安装并启用本地 OCR 工具\n\n\
                 *This PDF contains no extractable text (may be scanned/image-based). {} pages detected.*\n",
                strip_extension(filename),
                page_count,
                page_count
            ),
            metadata: LocalDocMetadata {
                title: Some(strip_extension(filename).to_string()),
                page_count: Some(page_count),
                language: None,
                ..Default::default()
            },
        });
    }

    let title = detect_title(&raw_text).unwrap_or_else(|| strip_extension(filename).to_string());
    let markdown = text_to_markdown(&raw_text, &title);

    Ok(LocalParseResult {
        markdown,
        metadata: LocalDocMetadata {
            title: Some(title),
            page_count: Some(page_count),
            language: None,
            ..Default::default()
        },
    })
}

/// Convert raw PDF text into a simple markdown structure.
fn text_to_markdown(raw: &str, title: &str) -> String {
    let mut md = String::with_capacity(raw.len() + 256);
    md.push_str(&format!("# {}\n\n", title));

    let lines: Vec<&str> = raw.lines().collect();
    let mut prev_blank = false;

    for line in &lines {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            if !prev_blank {
                md.push('\n');
                prev_blank = true;
            }
            continue;
        }
        prev_blank = false;

        if looks_like_heading(trimmed) {
            md.push_str(&format!("\n## {}\n\n", trimmed));
        } else {
            md.push_str(trimmed);
            md.push('\n');
        }
    }

    md
}

/// Heuristic: a line looks like a section heading if it's short, mostly uppercase
/// or ends without punctuation and is surrounded by blank lines.
fn looks_like_heading(line: &str) -> bool {
    if line.len() > 120 || line.len() < 3 {
        return false;
    }
    let has_trailing_punct = line.ends_with('.') || line.ends_with(',') || line.ends_with(';');
    if has_trailing_punct {
        return false;
    }
    let upper_count = line.chars().filter(|c| c.is_uppercase()).count();
    let alpha_count = line.chars().filter(|c| c.is_alphabetic()).count();
    if alpha_count > 0 && upper_count as f64 / alpha_count as f64 > 0.6 {
        return true;
    }
    false
}

/// Try to detect the document title from the first few non-empty lines.
fn detect_title(text: &str) -> Option<String> {
    let candidates: Vec<&str> = text
        .lines()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty())
        .take(5)
        .collect();

    candidates.first().and_then(|first| {
        let line = *first;
        if line.len() >= 3 && line.len() <= 200 {
            Some(line.to_string())
        } else {
            None
        }
    })
}

fn strip_extension(filename: &str) -> &str {
    filename
        .rsplit('/')
        .next()
        .unwrap_or(filename)
        .rsplit_once('.')
        .map(|(name, _)| name)
        .unwrap_or(filename)
}

fn parse_docx_fallback(data: &[u8], filename: &str) -> anyhow::Result<LocalParseResult> {
    use std::io::{Cursor, Read};

    let reader = Cursor::new(data);
    let mut archive = zip::ZipArchive::new(reader)
        .map_err(|e| anyhow::anyhow!("Failed to open DOCX as ZIP: {}", e))?;

    let mut xml_content = String::new();
    {
        let mut doc_file = archive
            .by_name("word/document.xml")
            .map_err(|e| anyhow::anyhow!("DOCX missing word/document.xml: {}", e))?;
        doc_file.read_to_string(&mut xml_content)
            .map_err(|e| anyhow::anyhow!("Failed to read document.xml: {}", e))?;
    }

    let text = extract_docx_text(&xml_content);

    if text.trim().is_empty() {
        return Ok(LocalParseResult {
            markdown: format!(
                "# {}\n\n**此 DOCX 文件无法提取文本内容。**\n\n\
                 *This DOCX file contains no extractable text.*\n",
                strip_extension(filename),
            ),
            metadata: LocalDocMetadata {
                title: Some(strip_extension(filename).to_string()),
                page_count: None,
                language: None,
                ..Default::default()
            },
        });
    }

    let title = detect_title(&text)
        .unwrap_or_else(|| strip_extension(filename).to_string());
    let markdown = docx_text_to_markdown(&text, &title);

    Ok(LocalParseResult {
        markdown,
        metadata: LocalDocMetadata {
            title: Some(title),
            page_count: None,
            language: None,
            ..Default::default()
        },
    })
}

fn extract_docx_text(xml: &str) -> String {
    let mut result = String::new();
    let mut in_paragraph = false;
    let mut in_text = false;
    let mut paragraph_text = String::new();

    let mut chars = xml.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '<' {
            let mut tag = String::new();
            for c in chars.by_ref() {
                if c == '>' {
                    break;
                }
                tag.push(c);
            }

            let tag_name = tag.split_whitespace().next().unwrap_or("");
            match tag_name {
                "w:p" => {
                    in_paragraph = true;
                    paragraph_text.clear();
                }
                "/w:p" => {
                    if in_paragraph && !paragraph_text.is_empty() {
                        result.push_str(&paragraph_text);
                        result.push('\n');
                    } else if in_paragraph {
                        result.push('\n');
                    }
                    in_paragraph = false;
                }
                "/w:t" => {
                    in_text = false;
                }
                "w:tab" | "w:tab/" => {
                    if in_paragraph {
                        paragraph_text.push('\t');
                    }
                }
                "w:br" | "w:br/" => {
                    if in_paragraph {
                        paragraph_text.push('\n');
                    }
                }
                t if t == "w:t" || t.starts_with("w:t ") => {
                    in_text = true;
                }
                _ => {}
            }
        } else if in_text && in_paragraph {
            paragraph_text.push(ch);
        }
    }

    result
}

fn docx_text_to_markdown(text: &str, title: &str) -> String {
    let mut md = String::with_capacity(text.len() + 256);
    md.push_str(&format!("# {}\n\n", title));

    let mut prev_blank = false;
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            if !prev_blank {
                md.push('\n');
                prev_blank = true;
            }
            continue;
        }
        prev_blank = false;

        if looks_like_heading(trimmed) {
            md.push_str(&format!("\n## {}\n\n", trimmed));
        } else {
            md.push_str(trimmed);
            md.push('\n');
        }
    }
    md
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_text() {
        let data = b"Hello, world!\nThis is a test document.";
        let result = parse_local(data, "test.txt", "txt").unwrap();
        assert!(result.markdown.contains("Hello, world!"));
        assert_eq!(result.metadata.page_count, Some(1));
    }

    #[test]
    fn test_parse_markdown() {
        let data = b"# Title\n\nSome content here.";
        let result = parse_local(data, "readme.md", "md").unwrap();
        assert!(result.markdown.contains("# Title"));
    }

    #[test]
    fn test_parse_html() {
        let data = b"<html><head><title>Test Page</title></head><body><h1>Hello</h1><p>World</p></body></html>";
        let result = parse_local(data, "page.html", "html").unwrap();
        assert!(result.markdown.contains("Hello"));
        assert!(result.markdown.contains("World"));
        assert_eq!(result.metadata.title, Some("Test Page".to_string()));
    }

    #[test]
    fn test_unsupported_type() {
        let result = parse_local(b"data", "file.xyz", "xyz");
        assert!(result.is_err());
    }

    #[test]
    fn test_strip_extension() {
        assert_eq!(strip_extension("document.pdf"), "document");
        assert_eq!(strip_extension("path/to/file.txt"), "file");
        assert_eq!(strip_extension("noext"), "noext");
        assert_eq!(strip_extension("my.report.pdf"), "my.report");
    }

    #[test]
    fn test_detect_title() {
        assert_eq!(
            detect_title("My Document Title\n\nSome content here."),
            Some("My Document Title".to_string())
        );
        assert_eq!(detect_title(""), None);
        assert_eq!(detect_title("\n\n\n"), None);
        assert_eq!(detect_title("Hi"), None); // too short (< 3)
    }

    #[test]
    fn test_looks_like_heading() {
        assert!(looks_like_heading("INTRODUCTION"));
        assert!(looks_like_heading("CHAPTER 1"));
        assert!(!looks_like_heading("This is a regular sentence."));
        assert!(!looks_like_heading("ab")); // too short
        assert!(!looks_like_heading(&"x".repeat(121))); // too long
    }

    #[test]
    fn test_text_to_markdown() {
        let text = "Some Title\nFirst paragraph of content.\n\nSecond paragraph.";
        let md = text_to_markdown(text, "Test Doc");
        assert!(md.starts_with("# Test Doc\n\n"));
        assert!(md.contains("First paragraph"));
        assert!(md.contains("Second paragraph"));
    }

    #[cfg(feature = "local-pdf")]
    #[test]
    fn test_parse_pdf_invalid_data() {
        let result = parse_pdf(b"not a valid pdf", "bad.pdf");
        assert!(result.is_err());
    }

    #[cfg(feature = "local-pdf")]
    #[test]
    fn test_parse_pdf_minimal() {
        use lopdf::{Document, Dictionary, Object, Stream, content::{Content, Operation}};

        let mut doc = Document::with_version("1.4");
        let pages_id = doc.new_object_id();

        let mut font_dict = Dictionary::new();
        font_dict.set("Type", Object::Name(b"Font".to_vec()));
        font_dict.set("Subtype", Object::Name(b"Type1".to_vec()));
        font_dict.set("BaseFont", Object::Name(b"Helvetica".to_vec()));
        let font_id = doc.add_object(font_dict);

        let content = Content {
            operations: vec![
                Operation::new("BT", vec![]),
                Operation::new("Tf", vec![Object::Name(b"F1".to_vec()), Object::Integer(12)]),
                Operation::new("Td", vec![Object::Integer(100), Object::Integer(700)]),
                Operation::new("Tj", vec![Object::string_literal("Hello PDF World")]),
                Operation::new("ET", vec![]),
            ],
        };
        let content_stream = Stream::new(Dictionary::new(), content.encode().unwrap());
        let content_id = doc.add_object(content_stream);

        let mut font_res = Dictionary::new();
        font_res.set("F1", font_id);
        let mut resources = Dictionary::new();
        resources.set("Font", Object::Dictionary(font_res));

        let mut page_dict = Dictionary::new();
        page_dict.set("Type", Object::Name(b"Page".to_vec()));
        page_dict.set("Parent", Object::Reference(pages_id));
        page_dict.set("Contents", Object::Reference(content_id));
        page_dict.set("Resources", Object::Dictionary(resources));
        page_dict.set("MediaBox", Object::Array(vec![
            0.into(), 0.into(), 612.into(), 792.into(),
        ]));
        let page_id = doc.add_object(page_dict);

        let mut pages_dict = Dictionary::new();
        pages_dict.set("Type", Object::Name(b"Pages".to_vec()));
        pages_dict.set("Kids", Object::Array(vec![Object::Reference(page_id)]));
        pages_dict.set("Count", Object::Integer(1));
        doc.objects.insert(pages_id, Object::Dictionary(pages_dict));

        let mut catalog = Dictionary::new();
        catalog.set("Type", Object::Name(b"Catalog".to_vec()));
        catalog.set("Pages", Object::Reference(pages_id));
        let catalog_id = doc.add_object(catalog);
        doc.trailer.set("Root", catalog_id);

        let mut buf = Vec::new();
        doc.save_to(&mut buf).unwrap();

        let result = parse_pdf(&buf, "test.pdf").unwrap();
        assert_eq!(result.metadata.page_count, Some(1));
        assert!(
            result.markdown.contains("Hello PDF World") || result.markdown.contains("test"),
            "Markdown should contain extracted text or filename: {}",
            result.markdown
        );
    }

    #[cfg(feature = "local-pdf")]
    #[test]
    fn test_parse_local_pdf_entry_point() {
        use lopdf::{Document, Dictionary, Object, Stream, content::{Content, Operation}};

        let mut doc = Document::with_version("1.4");
        let pages_id = doc.new_object_id();

        let mut font_dict = Dictionary::new();
        font_dict.set("Type", Object::Name(b"Font".to_vec()));
        font_dict.set("Subtype", Object::Name(b"Type1".to_vec()));
        font_dict.set("BaseFont", Object::Name(b"Helvetica".to_vec()));
        let font_id = doc.add_object(font_dict);

        let content = Content {
            operations: vec![
                Operation::new("BT", vec![]),
                Operation::new("Tf", vec![Object::Name(b"F1".to_vec()), Object::Integer(12)]),
                Operation::new("Td", vec![Object::Integer(100), Object::Integer(700)]),
                Operation::new("Tj", vec![Object::string_literal("Integration test content for PDF chunking")]),
                Operation::new("ET", vec![]),
            ],
        };
        let content_stream = Stream::new(Dictionary::new(), content.encode().unwrap());
        let content_id = doc.add_object(content_stream);

        let mut font_res = Dictionary::new();
        font_res.set("F1", font_id);
        let mut resources = Dictionary::new();
        resources.set("Font", Object::Dictionary(font_res));

        let mut page_dict = Dictionary::new();
        page_dict.set("Type", Object::Name(b"Page".to_vec()));
        page_dict.set("Parent", Object::Reference(pages_id));
        page_dict.set("Contents", Object::Reference(content_id));
        page_dict.set("Resources", Object::Dictionary(resources));
        page_dict.set("MediaBox", Object::Array(vec![0.into(), 0.into(), 612.into(), 792.into()]));
        let page_id = doc.add_object(page_dict);

        let mut pages_dict = Dictionary::new();
        pages_dict.set("Type", Object::Name(b"Pages".to_vec()));
        pages_dict.set("Kids", Object::Array(vec![Object::Reference(page_id)]));
        pages_dict.set("Count", Object::Integer(1));
        doc.objects.insert(pages_id, Object::Dictionary(pages_dict));

        let mut catalog = Dictionary::new();
        catalog.set("Type", Object::Name(b"Catalog".to_vec()));
        catalog.set("Pages", Object::Reference(pages_id));
        let catalog_id = doc.add_object(catalog);
        doc.trailer.set("Root", catalog_id);

        let mut buf = Vec::new();
        doc.save_to(&mut buf).unwrap();

        let result = parse_local(&buf, "report.pdf", "pdf").unwrap();
        assert_eq!(result.metadata.page_count, Some(1));
        assert!(result.metadata.title.is_some());

        let chunks = crate::services::chunking::chunk_markdown(
            &result.markdown,
            &crate::services::chunking::ChunkConfig::default(),
        );
        assert!(!chunks.is_empty(), "PDF markdown should produce at least one chunk");
        assert!(!chunks[0].content.is_empty());
    }

    #[test]
    fn test_extract_docx_text() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Hello World</w:t></w:r></w:p>
    <w:p><w:r><w:t xml:space="preserve">Second paragraph with spaces</w:t></w:r></w:p>
    <w:p></w:p>
    <w:p><w:r><w:t>Third paragraph</w:t></w:r></w:p>
  </w:body>
</w:document>"#;
        let text = extract_docx_text(xml);
        assert!(text.contains("Hello World"), "Should extract text: {}", text);
        assert!(text.contains("Second paragraph"), "Should extract second paragraph: {}", text);
        assert!(text.contains("Third paragraph"), "Should extract third paragraph: {}", text);
    }

    #[test]
    fn test_extract_docx_text_with_tabs_and_breaks() {
        let xml = r#"<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Before tab</w:t><w:tab/><w:t>After tab</w:t></w:r></w:p>
    <w:p><w:r><w:t>Line one</w:t><w:br/><w:t>Line two</w:t></w:r></w:p>
  </w:body>
</w:document>"#;
        let text = extract_docx_text(xml);
        assert!(text.contains("Before tab"), "Should have text before tab: {}", text);
        assert!(text.contains("After tab"), "Should have text after tab: {}", text);
        assert!(text.contains("Line one"), "Should have line one: {}", text);
        assert!(text.contains("Line two"), "Should have line two: {}", text);
    }

    #[test]
    fn test_parse_docx_with_real_zip() {
        use std::io::Write;
        let mut buf = Vec::new();
        {
            let cursor = std::io::Cursor::new(&mut buf);
            let mut zip_writer = zip::ZipWriter::new(cursor);
            let options = zip::write::SimpleFileOptions::default()
                .compression_method(zip::CompressionMethod::Deflated);
            zip_writer.start_file("word/document.xml", options).unwrap();
            write!(zip_writer, r#"<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Test DOCX Content</w:t></w:r></w:p>
    <w:p><w:r><w:t>Second Paragraph</w:t></w:r></w:p>
  </w:body>
</w:document>"#).unwrap();
            zip_writer.finish().unwrap();
        }

        let result = parse_local(&buf, "test.docx", "docx").unwrap();
        assert!(result.markdown.contains("Test DOCX Content"), "Markdown: {}", result.markdown);
        assert!(result.markdown.contains("Second Paragraph"), "Markdown: {}", result.markdown);
        assert!(result.metadata.title.is_some());
    }

    #[test]
    fn test_docx_text_to_markdown() {
        let text = "Document Title\nFirst paragraph of content.\n\nSecond paragraph.";
        let md = docx_text_to_markdown(text, "My Doc");
        assert!(md.starts_with("# My Doc\n\n"));
        assert!(md.contains("First paragraph"));
        assert!(md.contains("Second paragraph"));
    }
}
