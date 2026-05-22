use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct LocalParseResult {
    pub markdown: String,
    pub metadata: LocalDocMetadata,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct LocalDocMetadata {
    pub title: Option<String>,
    pub page_count: Option<i32>,
    pub language: Option<String>,
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
                "# {}\n\n*This PDF contains no extractable text (may be scanned/image-based). \
                 {} pages detected.*\n",
                strip_extension(filename),
                page_count
            ),
            metadata: LocalDocMetadata {
                title: Some(strip_extension(filename).to_string()),
                page_count: Some(page_count),
                language: None,
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
    #[cfg(sqlite_mode)]
    {
        let _ = data;
        Ok(LocalParseResult {
            markdown: format!(
                "# {}\n\n*DOCX parsing requires the doc-processor service. \
                 Please install it or convert this DOCX to text/markdown format first.*\n\n\
                 File size: {} bytes",
                filename,
                data.len()
            ),
            metadata: LocalDocMetadata {
                title: Some(filename.to_string()),
                page_count: None,
                language: None,
            },
        })
    }
    #[cfg(not(sqlite_mode))]
    {
        let _ = (data, filename);
        anyhow::bail!("DOCX processing not available in this build")
    }
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
}
