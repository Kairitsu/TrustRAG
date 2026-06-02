use criterion::{criterion_group, criterion_main, BenchmarkId, Criterion};
use trustrag_backend::chunking::{chunk_markdown, ChunkConfig};

fn generate_markdown(target_bytes: usize) -> String {
    let mut buf = String::with_capacity(target_bytes + 1024);
    let mut section = 1;
    let mut subsection = 1;

    let paragraphs = [
        "这是一段较长的中文示例文本，用于模拟真实文档中的段落内容。在知识管理系统中，文档通常包含大量此类描述性文字，涵盖技术细节、业务逻辑和操作指南等多种类型。",
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.",
        "The retrieval-augmented generation (RAG) pipeline processes documents through several stages: parsing, chunking, embedding, and indexing. Each stage has its own performance characteristics and tuning parameters.",
        "代码示例和技术文档经常混合使用中英文。比如在讨论 API 设计时，我们需要考虑 RESTful 接口规范、JSON 数据格式、以及 HTTP 状态码的正确使用。",
    ];

    let code_block = "```python\ndef process_document(doc_path: str, config: dict) -> list:\n    \"\"\"Process a document and return chunks.\"\"\"\n    with open(doc_path, 'r') as f:\n        content = f.read()\n    chunks = split_text(content, config['chunk_size'])\n    return [embed(chunk) for chunk in chunks]\n```\n\n";

    while buf.len() < target_bytes {
        buf.push_str(&format!("# Chapter {} Overview\n\n", section));

        for p in &paragraphs {
            if buf.len() >= target_bytes { break; }
            buf.push_str(&format!("## {}.{} Details\n\n", section, subsection));
            buf.push_str(p);
            buf.push_str("\n\n");

            if subsection % 3 == 0 {
                buf.push_str(code_block);
            }

            buf.push_str("- Item one with description\n");
            buf.push_str("- Item two with more detail\n");
            buf.push_str("- Item three explaining further\n\n");

            subsection += 1;
        }
        section += 1;
        subsection = 1;
    }

    buf.truncate(target_bytes);
    buf
}

fn bench_chunk_markdown(c: &mut Criterion) {
    let config = ChunkConfig::default();

    let sizes: Vec<(&str, usize)> = vec![
        ("10KB", 10 * 1024),
        ("50KB", 50 * 1024),
        ("100KB", 100 * 1024),
        ("500KB", 500 * 1024),
        ("1MB", 1024 * 1024),
    ];

    let mut group = c.benchmark_group("chunk_markdown");
    for (label, size) in &sizes {
        let content = generate_markdown(*size);
        group.bench_with_input(
            BenchmarkId::new("default_config", label),
            &content,
            |b, content| {
                b.iter(|| chunk_markdown(content, &config));
            },
        );
    }
    group.finish();
}

fn bench_chunk_sizes(c: &mut Criterion) {
    let content = generate_markdown(100 * 1024);

    let configs: Vec<(&str, ChunkConfig)> = vec![
        ("512/50", ChunkConfig { target_chars: 512, overlap_chars: 50 }),
        ("1000/100", ChunkConfig { target_chars: 1000, overlap_chars: 100 }),
        ("1500/200", ChunkConfig { target_chars: 1500, overlap_chars: 200 }),
        ("3000/300", ChunkConfig { target_chars: 3000, overlap_chars: 300 }),
    ];

    let mut group = c.benchmark_group("chunk_config_comparison");
    for (label, cfg) in &configs {
        group.bench_with_input(
            BenchmarkId::new("100KB", label),
            &content,
            |b, content| {
                b.iter(|| chunk_markdown(content, cfg));
            },
        );
    }
    group.finish();
}

criterion_group!(benches, bench_chunk_markdown, bench_chunk_sizes);
criterion_main!(benches);
