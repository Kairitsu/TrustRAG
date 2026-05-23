use anyhow::Result;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::services::retrieval_pipeline::AssembledSource;
use crate::traits::llm_provider::{LlmMessage, LlmProvider, LlmRequest};

/// A single claim extracted from an LLM response.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claim {
    pub text: String,
    pub start_offset: usize,
    pub end_offset: usize,
    pub cited_source_indices: Vec<usize>,
}

/// Verification status for a single claim.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EvidenceStatus {
    Supported,
    Contradicted,
    Unsupported,
    Partial,
}

/// Evidence verification result for a single claim.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClaimVerification {
    pub claim: Claim,
    pub status: EvidenceStatus,
    pub confidence: f64,
    pub supporting_source_indices: Vec<usize>,
    pub explanation: String,
}

/// Full verification report for an answer.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationReport {
    pub claims: Vec<ClaimVerification>,
    pub overall_trust_score: f64,
    pub supported_count: usize,
    pub unsupported_count: usize,
    pub contradicted_count: usize,
    pub partial_count: usize,
}

/// Split an LLM response into individual factual claims.
/// Uses sentence boundaries and citation markers.
pub fn extract_claims(answer_text: &str) -> Vec<Claim> {
    let mut claims = Vec::new();
    let mut offset = 0;

    for sentence in split_sentences(answer_text) {
        let trimmed = sentence.trim();
        if trimmed.is_empty() || trimmed.len() < 5 {
            offset += sentence.len();
            continue;
        }

        if is_filler_sentence(trimmed) {
            offset += sentence.len();
            continue;
        }

        let cited_indices = extract_source_indices(trimmed);
        let start = offset;
        let end = offset + sentence.len();

        claims.push(Claim {
            text: trimmed.to_string(),
            start_offset: start,
            end_offset: end,
            cited_source_indices: cited_indices,
        });

        offset = end;
    }

    claims
}

/// Verify a single claim against assembled sources using text overlap analysis.
/// This is a fast, non-LLM verification approach.
pub fn verify_claim_text(
    claim: &Claim,
    sources: &[AssembledSource],
) -> ClaimVerification {
    if sources.is_empty() || claim.cited_source_indices.is_empty() {
        return ClaimVerification {
            claim: claim.clone(),
            status: if claim.cited_source_indices.is_empty() {
                EvidenceStatus::Unsupported
            } else {
                EvidenceStatus::Unsupported
            },
            confidence: 0.3,
            supporting_source_indices: vec![],
            explanation: "No source evidence available for verification".to_string(),
        };
    }

    let claim_tokens = tokenize(&claim.text);
    let mut best_overlap = 0.0;
    let mut supporting_indices = Vec::new();

    for &idx in &claim.cited_source_indices {
        if let Some(source) = sources.iter().find(|s| s.index == idx) {
            let source_tokens = tokenize(&source.content);
            let overlap = jaccard_similarity(&claim_tokens, &source_tokens);
            if overlap > 0.1 {
                supporting_indices.push(idx);
                if overlap > best_overlap {
                    best_overlap = overlap;
                }
            }
        }
    }

    let (status, confidence) = if best_overlap > 0.3 {
        (EvidenceStatus::Supported, 0.7 + best_overlap * 0.3)
    } else if best_overlap > 0.15 {
        (EvidenceStatus::Partial, 0.4 + best_overlap)
    } else if !supporting_indices.is_empty() {
        (EvidenceStatus::Partial, 0.3)
    } else {
        (EvidenceStatus::Unsupported, 0.2)
    };

    ClaimVerification {
        claim: claim.clone(),
        status,
        confidence: confidence.min(1.0),
        supporting_source_indices: supporting_indices,
        explanation: format!("Text overlap score: {:.2}", best_overlap),
    }
}

/// Verify claims using LLM for deeper semantic analysis.
pub async fn verify_claim_llm(
    claim: &Claim,
    sources: &[AssembledSource],
    llm_provider: &dyn LlmProvider,
) -> Result<ClaimVerification> {
    let relevant_sources: Vec<_> = claim.cited_source_indices.iter()
        .filter_map(|&idx| sources.iter().find(|s| s.index == idx))
        .collect();

    if relevant_sources.is_empty() {
        return Ok(ClaimVerification {
            claim: claim.clone(),
            status: EvidenceStatus::Unsupported,
            confidence: 0.5,
            supporting_source_indices: vec![],
            explanation: "No cited sources found".to_string(),
        });
    }

    let mut evidence_text = String::new();
    for (i, s) in relevant_sources.iter().enumerate() {
        let snippet: String = s.content.chars().take(500).collect();
        evidence_text.push_str(&format!("[Source {}] {}\n\n", i + 1, snippet));
    }

    let prompt = format!(
        "Verify whether the following claim is supported by the provided evidence.\n\n\
         Claim: \"{}\"\n\n\
         Evidence:\n{}\n\n\
         Respond with ONLY a JSON object:\n\
         {{\"status\": \"supported\"|\"contradicted\"|\"unsupported\"|\"partial\", \"confidence\": 0.0-1.0, \"explanation\": \"brief reason\"}}",
        claim.text, evidence_text
    );

    let req = LlmRequest {
        messages: vec![
            LlmMessage {
                role: "system".to_string(),
                content: "You are a fact-checking assistant. Verify claims against evidence. Be precise.".to_string(),
            },
            LlmMessage {
                role: "user".to_string(),
                content: prompt,
            },
        ],
        temperature: 0.0,
        max_tokens: 200,
        stream: false,
    };

    match llm_provider.generate(&req).await {
        Ok(resp) => parse_verification_response(&resp.content, claim, &relevant_sources),
        Err(e) => {
            tracing::warn!(error = %e, "LLM verification failed, falling back to text analysis");
            Ok(verify_claim_text(claim, sources))
        }
    }
}

fn parse_verification_response(
    content: &str,
    claim: &Claim,
    sources: &[&AssembledSource],
) -> Result<ClaimVerification> {
    let trimmed = content.trim();
    let json_str = if let Some(start) = trimmed.find('{') {
        if let Some(end) = trimmed.rfind('}') {
            &trimmed[start..=end]
        } else {
            trimmed
        }
    } else {
        trimmed
    };

    #[derive(Deserialize)]
    struct LlmVerification {
        status: String,
        confidence: f64,
        explanation: String,
    }

    match serde_json::from_str::<LlmVerification>(json_str) {
        Ok(v) => {
            let status = match v.status.to_lowercase().as_str() {
                "supported" => EvidenceStatus::Supported,
                "contradicted" => EvidenceStatus::Contradicted,
                "partial" => EvidenceStatus::Partial,
                _ => EvidenceStatus::Unsupported,
            };
            Ok(ClaimVerification {
                claim: claim.clone(),
                status,
                confidence: v.confidence.clamp(0.0, 1.0),
                supporting_source_indices: sources.iter().map(|s| s.index).collect(),
                explanation: v.explanation,
            })
        }
        Err(_) => Ok(verify_claim_text(claim, &[])),
    }
}

/// Build a full verification report for an answer.
pub fn build_report(verifications: &[ClaimVerification]) -> VerificationReport {
    let supported = verifications.iter().filter(|v| v.status == EvidenceStatus::Supported).count();
    let contradicted = verifications.iter().filter(|v| v.status == EvidenceStatus::Contradicted).count();
    let unsupported = verifications.iter().filter(|v| v.status == EvidenceStatus::Unsupported).count();
    let partial = verifications.iter().filter(|v| v.status == EvidenceStatus::Partial).count();

    let total = verifications.len().max(1);
    let trust_score = if total > 0 {
        let weighted = supported as f64 * 1.0
            + partial as f64 * 0.5
            + unsupported as f64 * 0.1
            + contradicted as f64 * 0.0;
        weighted / total as f64
    } else {
        0.0
    };

    VerificationReport {
        claims: verifications.to_vec(),
        overall_trust_score: trust_score,
        supported_count: supported,
        unsupported_count: unsupported,
        contradicted_count: contradicted,
        partial_count: partial,
    }
}

// ── Helpers ──

fn split_sentences(text: &str) -> Vec<String> {
    let mut sentences = Vec::new();
    let mut current = String::new();

    for ch in text.chars() {
        current.push(ch);
        if "。！？.!?\n".contains(ch) {
            sentences.push(std::mem::take(&mut current));
        }
    }
    if !current.is_empty() {
        sentences.push(current);
    }
    sentences
}

fn is_filler_sentence(s: &str) -> bool {
    let lower = s.to_lowercase();
    let fillers = [
        "根据提供的资料", "根据上述", "综上所述", "总的来说",
        "based on the provided", "in summary", "to summarize",
        "以下是", "让我来",
    ];
    fillers.iter().any(|f| lower.starts_with(f))
}

fn extract_source_indices(text: &str) -> Vec<usize> {
    use std::sync::LazyLock;
    use regex::Regex;
    static RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\[(\d+)\]").unwrap());

    RE.captures_iter(text)
        .filter_map(|cap| cap[1].parse::<usize>().ok())
        .filter(|&i| i > 0)
        .collect()
}

fn tokenize(text: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current_word = String::new();

    for ch in text.chars() {
        if ch.is_whitespace() || "，。！？、；：\"'()（）【】{}[]「」【】".contains(ch) {
            if current_word.len() > 1 {
                tokens.push(std::mem::take(&mut current_word).to_lowercase());
            } else {
                current_word.clear();
            }
        } else if is_cjk(ch) {
            if current_word.len() > 1 {
                tokens.push(std::mem::take(&mut current_word).to_lowercase());
            } else {
                current_word.clear();
            }
            tokens.push(ch.to_string());
        } else {
            current_word.push(ch);
        }
    }
    if current_word.len() > 1 {
        tokens.push(current_word.to_lowercase());
    }
    tokens
}

fn is_cjk(c: char) -> bool {
    matches!(c,
        '\u{4E00}'..='\u{9FFF}' | '\u{3400}'..='\u{4DBF}' |
        '\u{F900}'..='\u{FAFF}' | '\u{3040}'..='\u{309F}' |
        '\u{30A0}'..='\u{30FF}' | '\u{AC00}'..='\u{D7AF}'
    )
}

fn jaccard_similarity(a: &[String], b: &[String]) -> f64 {
    use std::collections::HashSet;
    let set_a: HashSet<&str> = a.iter().map(|s| s.as_str()).collect();
    let set_b: HashSet<&str> = b.iter().map(|s| s.as_str()).collect();
    let intersection = set_a.intersection(&set_b).count();
    let union = set_a.union(&set_b).count();
    if union == 0 { 0.0 } else { intersection as f64 / union as f64 }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_claims_basic() {
        let text = "Rust是一种系统编程语言 [1]。它注重安全性和性能 [2]。";
        let claims = extract_claims(text);
        assert_eq!(claims.len(), 2);
        assert_eq!(claims[0].cited_source_indices, vec![1]);
        assert_eq!(claims[1].cited_source_indices, vec![2]);
    }

    #[test]
    fn test_extract_claims_no_citations() {
        let text = "这是一个普通的陈述句，没有引用任何来源。";
        let claims = extract_claims(text);
        assert_eq!(claims.len(), 1);
        assert!(claims[0].cited_source_indices.is_empty());
    }

    #[test]
    fn test_extract_claims_multiple_citations() {
        let text = "根据多个来源 [1][3]，这个结论是可靠的。";
        let claims = extract_claims(text);
        assert_eq!(claims.len(), 1);
        assert!(claims[0].cited_source_indices.contains(&1));
        assert!(claims[0].cited_source_indices.contains(&3));
    }

    #[test]
    fn test_extract_claims_filters_filler() {
        let text = "根据提供的资料，以下是答案。Rust很快 [1]。Go也很好 [2]。";
        let claims = extract_claims(text);
        assert!(claims.iter().all(|c| !c.text.starts_with("根据提供的资料")));
    }

    #[test]
    fn test_split_sentences() {
        let text = "第一句。第二句！第三句？";
        let sentences = split_sentences(text);
        assert_eq!(sentences.len(), 3);
    }

    #[test]
    fn test_tokenize() {
        let tokens = tokenize("Hello World，你好世界");
        assert!(tokens.contains(&"hello".to_string()));
        assert!(tokens.contains(&"world".to_string()));
    }

    #[test]
    fn test_jaccard_similarity_identical() {
        let a = vec!["hello".to_string(), "world".to_string()];
        let sim = jaccard_similarity(&a, &a);
        assert!((sim - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_jaccard_similarity_disjoint() {
        let a = vec!["hello".to_string()];
        let b = vec!["world".to_string()];
        let sim = jaccard_similarity(&a, &b);
        assert!((sim - 0.0).abs() < 1e-10);
    }

    #[test]
    fn test_verify_claim_text_with_overlap() {
        let claim = Claim {
            text: "Rust是一种注重安全性的系统编程语言".to_string(),
            start_offset: 0,
            end_offset: 30,
            cited_source_indices: vec![1],
        };
        let sources = vec![
            AssembledSource {
                index: 1,
                chunk_id: Uuid::new_v4(),
                document_id: Uuid::new_v4(),
                heading_path: None,
                page_start: None,
                page_end: None,
                content: "Rust是一种系统编程语言，它非常注重内存安全性和性能优化".to_string(),
                score: 0.9,
            },
        ];
        let result = verify_claim_text(&claim, &sources);
        assert!(result.status == EvidenceStatus::Supported || result.status == EvidenceStatus::Partial);
    }

    #[test]
    fn test_verify_claim_text_no_sources() {
        let claim = Claim {
            text: "Some claim".to_string(),
            start_offset: 0,
            end_offset: 10,
            cited_source_indices: vec![1],
        };
        let result = verify_claim_text(&claim, &[]);
        assert_eq!(result.status, EvidenceStatus::Unsupported);
    }

    #[test]
    fn test_build_report_all_supported() {
        let verifications = vec![
            ClaimVerification {
                claim: Claim { text: "a".into(), start_offset: 0, end_offset: 1, cited_source_indices: vec![1] },
                status: EvidenceStatus::Supported,
                confidence: 0.9,
                supporting_source_indices: vec![1],
                explanation: "ok".into(),
            },
            ClaimVerification {
                claim: Claim { text: "b".into(), start_offset: 2, end_offset: 3, cited_source_indices: vec![2] },
                status: EvidenceStatus::Supported,
                confidence: 0.85,
                supporting_source_indices: vec![2],
                explanation: "ok".into(),
            },
        ];
        let report = build_report(&verifications);
        assert_eq!(report.supported_count, 2);
        assert_eq!(report.unsupported_count, 0);
        assert!((report.overall_trust_score - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_build_report_mixed() {
        let verifications = vec![
            ClaimVerification {
                claim: Claim { text: "a".into(), start_offset: 0, end_offset: 1, cited_source_indices: vec![1] },
                status: EvidenceStatus::Supported,
                confidence: 0.9,
                supporting_source_indices: vec![1],
                explanation: "ok".into(),
            },
            ClaimVerification {
                claim: Claim { text: "b".into(), start_offset: 2, end_offset: 3, cited_source_indices: vec![] },
                status: EvidenceStatus::Unsupported,
                confidence: 0.3,
                supporting_source_indices: vec![],
                explanation: "no evidence".into(),
            },
        ];
        let report = build_report(&verifications);
        assert_eq!(report.supported_count, 1);
        assert_eq!(report.unsupported_count, 1);
        assert!(report.overall_trust_score > 0.0);
        assert!(report.overall_trust_score < 1.0);
    }

    #[test]
    fn test_evidence_status_serde() {
        let statuses = vec![
            EvidenceStatus::Supported,
            EvidenceStatus::Contradicted,
            EvidenceStatus::Unsupported,
            EvidenceStatus::Partial,
        ];
        for status in statuses {
            let json = serde_json::to_string(&status).unwrap();
            let deserialized: EvidenceStatus = serde_json::from_str(&json).unwrap();
            assert_eq!(status, deserialized);
        }
    }

    #[test]
    fn test_is_filler_sentence() {
        assert!(is_filler_sentence("根据提供的资料，这里是答案"));
        assert!(is_filler_sentence("Based on the provided documents..."));
        assert!(!is_filler_sentence("Rust很快 [1]"));
    }

    #[test]
    fn test_extract_source_indices() {
        let indices = extract_source_indices("参考 [1] 和 [3] 的内容");
        assert_eq!(indices, vec![1, 3]);
    }
}
