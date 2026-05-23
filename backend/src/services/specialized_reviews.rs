use anyhow::Result;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use crate::db::DbPool;

// ─── Claim Reviews ──────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClaimVerdict {
    Supported,
    Unsupported,
    PartiallySupported,
    Unverifiable,
}

impl ClaimVerdict {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Supported => "supported",
            Self::Unsupported => "unsupported",
            Self::PartiallySupported => "partially_supported",
            Self::Unverifiable => "unverifiable",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "supported" => Some(Self::Supported),
            "unsupported" => Some(Self::Unsupported),
            "partially_supported" => Some(Self::PartiallySupported),
            "unverifiable" => Some(Self::Unverifiable),
            _ => None,
        }
    }

    pub fn all_variants() -> &'static [ClaimVerdict] {
        &[
            Self::Supported,
            Self::Unsupported,
            Self::PartiallySupported,
            Self::Unverifiable,
        ]
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct ClaimReview {
    pub id: Uuid,
    pub claim_id: Uuid,
    pub message_id: Uuid,
    pub reviewer_id: Uuid,
    pub verdict: String,
    pub confidence: Option<f64>,
    pub comment: Option<String>,
    pub evidence_references: serde_json::Value,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateClaimReviewInput {
    pub claim_id: Uuid,
    pub message_id: Uuid,
    pub verdict: String,
    pub confidence: Option<f64>,
    pub comment: Option<String>,
    pub evidence_references: Option<Vec<serde_json::Value>>,
}

pub async fn create_claim_review(
    pool: &DbPool,
    reviewer_id: Uuid,
    input: &CreateClaimReviewInput,
) -> Result<ClaimReview> {
    ClaimVerdict::from_str(&input.verdict)
        .ok_or_else(|| anyhow::anyhow!("Invalid claim verdict: {}", input.verdict))?;

    if let Some(conf) = input.confidence {
        anyhow::ensure!(
            (0.0..=1.0).contains(&conf),
            "Confidence must be between 0.0 and 1.0"
        );
    }

    let refs = serde_json::to_value(
        input.evidence_references.as_deref().unwrap_or(&[]),
    )?;

    let row = sqlx::query_as::<_, ClaimReview>(
        r#"
        INSERT INTO claim_reviews (claim_id, message_id, reviewer_id, verdict, confidence, comment, evidence_references)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING *
        "#,
    )
    .bind(input.claim_id)
    .bind(input.message_id)
    .bind(reviewer_id)
    .bind(&input.verdict)
    .bind(input.confidence)
    .bind(&input.comment)
    .bind(&refs)
    .fetch_one(pool)
    .await?;

    Ok(row)
}

pub async fn list_claim_reviews(pool: &DbPool, message_id: Uuid) -> Result<Vec<ClaimReview>> {
    let rows = sqlx::query_as::<_, ClaimReview>(
        "SELECT * FROM claim_reviews WHERE message_id = $1 ORDER BY created_at DESC",
    )
    .bind(message_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn get_claim_review(pool: &DbPool, review_id: Uuid) -> Result<Option<ClaimReview>> {
    let row = sqlx::query_as::<_, ClaimReview>(
        "SELECT * FROM claim_reviews WHERE id = $1",
    )
    .bind(review_id)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

// ─── Answer Reviews ─────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AnswerVerdict {
    Approved,
    Rejected,
    NeedsRevision,
    Escalated,
}

impl AnswerVerdict {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Approved => "approved",
            Self::Rejected => "rejected",
            Self::NeedsRevision => "needs_revision",
            Self::Escalated => "escalated",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "approved" => Some(Self::Approved),
            "rejected" => Some(Self::Rejected),
            "needs_revision" => Some(Self::NeedsRevision),
            "escalated" => Some(Self::Escalated),
            _ => None,
        }
    }

    pub fn all_variants() -> &'static [AnswerVerdict] {
        &[
            Self::Approved,
            Self::Rejected,
            Self::NeedsRevision,
            Self::Escalated,
        ]
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct AnswerReview {
    pub id: Uuid,
    pub message_id: Uuid,
    pub answer_version_id: Option<Uuid>,
    pub reviewer_id: Uuid,
    pub overall_verdict: String,
    pub accuracy_score: Option<f64>,
    pub completeness_score: Option<f64>,
    pub clarity_score: Option<f64>,
    pub comment: Option<String>,
    pub revision_instructions: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateAnswerReviewInput {
    pub message_id: Uuid,
    pub answer_version_id: Option<Uuid>,
    pub overall_verdict: String,
    pub accuracy_score: Option<f64>,
    pub completeness_score: Option<f64>,
    pub clarity_score: Option<f64>,
    pub comment: Option<String>,
    pub revision_instructions: Option<String>,
}

fn validate_score(name: &str, score: Option<f64>) -> Result<()> {
    if let Some(s) = score {
        anyhow::ensure!(
            (0.0..=1.0).contains(&s),
            "{} must be between 0.0 and 1.0, got {}",
            name,
            s
        );
    }
    Ok(())
}

pub async fn create_answer_review(
    pool: &DbPool,
    reviewer_id: Uuid,
    input: &CreateAnswerReviewInput,
) -> Result<AnswerReview> {
    AnswerVerdict::from_str(&input.overall_verdict)
        .ok_or_else(|| anyhow::anyhow!("Invalid answer verdict: {}", input.overall_verdict))?;

    validate_score("accuracy_score", input.accuracy_score)?;
    validate_score("completeness_score", input.completeness_score)?;
    validate_score("clarity_score", input.clarity_score)?;

    let row = sqlx::query_as::<_, AnswerReview>(
        r#"
        INSERT INTO answer_reviews
            (message_id, answer_version_id, reviewer_id, overall_verdict,
             accuracy_score, completeness_score, clarity_score, comment, revision_instructions)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING *
        "#,
    )
    .bind(input.message_id)
    .bind(input.answer_version_id)
    .bind(reviewer_id)
    .bind(&input.overall_verdict)
    .bind(input.accuracy_score)
    .bind(input.completeness_score)
    .bind(input.clarity_score)
    .bind(&input.comment)
    .bind(&input.revision_instructions)
    .fetch_one(pool)
    .await?;

    Ok(row)
}

pub async fn list_answer_reviews(pool: &DbPool, message_id: Uuid) -> Result<Vec<AnswerReview>> {
    let rows = sqlx::query_as::<_, AnswerReview>(
        "SELECT * FROM answer_reviews WHERE message_id = $1 ORDER BY created_at DESC",
    )
    .bind(message_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn get_answer_review(pool: &DbPool, review_id: Uuid) -> Result<Option<AnswerReview>> {
    let row = sqlx::query_as::<_, AnswerReview>(
        "SELECT * FROM answer_reviews WHERE id = $1",
    )
    .bind(review_id)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_claim_verdict_roundtrip() {
        for v in ClaimVerdict::all_variants() {
            let s = v.as_str();
            let parsed = ClaimVerdict::from_str(s).unwrap();
            assert_eq!(*v, parsed);
        }
    }

    #[test]
    fn test_claim_verdict_invalid() {
        assert!(ClaimVerdict::from_str("invalid").is_none());
        assert!(ClaimVerdict::from_str("").is_none());
    }

    #[test]
    fn test_claim_verdict_serde() {
        let v = ClaimVerdict::PartiallySupported;
        let json = serde_json::to_string(&v).unwrap();
        assert_eq!(json, "\"partially_supported\"");
        let deserialized: ClaimVerdict = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized, v);
    }

    #[test]
    fn test_answer_verdict_roundtrip() {
        for v in AnswerVerdict::all_variants() {
            let s = v.as_str();
            let parsed = AnswerVerdict::from_str(s).unwrap();
            assert_eq!(*v, parsed);
        }
    }

    #[test]
    fn test_answer_verdict_invalid() {
        assert!(AnswerVerdict::from_str("bad").is_none());
    }

    #[test]
    fn test_answer_verdict_serde() {
        let v = AnswerVerdict::NeedsRevision;
        let json = serde_json::to_string(&v).unwrap();
        assert_eq!(json, "\"needs_revision\"");
        let deserialized: AnswerVerdict = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized, v);
    }

    #[test]
    fn test_create_claim_review_input_deserialize() {
        let json = r#"{
            "claim_id": "550e8400-e29b-41d4-a716-446655440000",
            "message_id": "660e8400-e29b-41d4-a716-446655440001",
            "verdict": "supported",
            "confidence": 0.95,
            "comment": "Claim is well supported by the evidence"
        }"#;
        let input: CreateClaimReviewInput = serde_json::from_str(json).unwrap();
        assert_eq!(input.verdict, "supported");
        assert!((input.confidence.unwrap() - 0.95).abs() < 1e-10);
        assert!(input.evidence_references.is_none());
    }

    #[test]
    fn test_create_claim_review_input_minimal() {
        let json = r#"{
            "claim_id": "550e8400-e29b-41d4-a716-446655440000",
            "message_id": "660e8400-e29b-41d4-a716-446655440001",
            "verdict": "unsupported"
        }"#;
        let input: CreateClaimReviewInput = serde_json::from_str(json).unwrap();
        assert_eq!(input.verdict, "unsupported");
        assert!(input.confidence.is_none());
        assert!(input.comment.is_none());
    }

    #[test]
    fn test_create_answer_review_input_deserialize() {
        let json = r#"{
            "message_id": "550e8400-e29b-41d4-a716-446655440000",
            "overall_verdict": "approved",
            "accuracy_score": 0.9,
            "completeness_score": 0.85,
            "clarity_score": 0.95,
            "comment": "Excellent answer"
        }"#;
        let input: CreateAnswerReviewInput = serde_json::from_str(json).unwrap();
        assert_eq!(input.overall_verdict, "approved");
        assert!((input.accuracy_score.unwrap() - 0.9).abs() < 1e-10);
        assert!(input.revision_instructions.is_none());
    }

    #[test]
    fn test_create_answer_review_input_with_revision() {
        let json = r#"{
            "message_id": "550e8400-e29b-41d4-a716-446655440000",
            "overall_verdict": "needs_revision",
            "revision_instructions": "Please add more detail about section 3"
        }"#;
        let input: CreateAnswerReviewInput = serde_json::from_str(json).unwrap();
        assert_eq!(input.overall_verdict, "needs_revision");
        assert!(input.revision_instructions.is_some());
        assert!(input.accuracy_score.is_none());
    }

    #[test]
    fn test_validate_score_valid() {
        assert!(validate_score("test", Some(0.0)).is_ok());
        assert!(validate_score("test", Some(0.5)).is_ok());
        assert!(validate_score("test", Some(1.0)).is_ok());
        assert!(validate_score("test", None).is_ok());
    }

    #[test]
    fn test_validate_score_invalid() {
        assert!(validate_score("test", Some(-0.1)).is_err());
        assert!(validate_score("test", Some(1.1)).is_err());
        assert!(validate_score("test", Some(999.0)).is_err());
    }

    #[test]
    fn test_claim_review_serialization() {
        let review = ClaimReview {
            id: Uuid::new_v4(),
            claim_id: Uuid::new_v4(),
            message_id: Uuid::new_v4(),
            reviewer_id: Uuid::new_v4(),
            verdict: "supported".to_string(),
            confidence: Some(0.9),
            comment: Some("Well supported".to_string()),
            evidence_references: serde_json::json!([{"chunk_id": "abc", "score": 0.95}]),
            created_at: chrono::Utc::now(),
        };
        let json = serde_json::to_value(&review).unwrap();
        assert_eq!(json["verdict"], "supported");
        assert!(json["evidence_references"].is_array());
    }

    #[test]
    fn test_answer_review_serialization() {
        let review = AnswerReview {
            id: Uuid::new_v4(),
            message_id: Uuid::new_v4(),
            answer_version_id: Some(Uuid::new_v4()),
            reviewer_id: Uuid::new_v4(),
            overall_verdict: "approved".to_string(),
            accuracy_score: Some(0.9),
            completeness_score: Some(0.85),
            clarity_score: Some(0.95),
            comment: Some("Great answer".to_string()),
            revision_instructions: None,
            created_at: chrono::Utc::now(),
        };
        let json = serde_json::to_value(&review).unwrap();
        assert_eq!(json["overall_verdict"], "approved");
        assert_eq!(json["accuracy_score"], 0.9);
        assert!(json["revision_instructions"].is_null());
    }
}
