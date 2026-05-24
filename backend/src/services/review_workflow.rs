use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::DbPool;

// ── Review Task ──

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ReviewTaskStatus {
    Open,
    InProgress,
    NeedsRevision,
    Approved,
    Rejected,
    Closed,
}

impl Default for ReviewTaskStatus {
    fn default() -> Self {
        Self::Open
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ReviewTaskType {
    General,
    FactCheck,
    SourceVerification,
    ContentReview,
    SecurityAudit,
}

impl Default for ReviewTaskType {
    fn default() -> Self {
        Self::General
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewTask {
    pub id: Uuid,
    pub workspace_id: Uuid,
    pub message_id: Option<Uuid>,
    pub answer_version_id: Option<Uuid>,
    pub title: String,
    pub description: Option<String>,
    pub task_type: ReviewTaskType,
    pub priority: i32,
    pub status: ReviewTaskStatus,
    pub assigned_to: Option<Uuid>,
    pub created_by: Option<Uuid>,
    pub due_date: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
    pub tags: Vec<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateReviewTask {
    pub workspace_id: Uuid,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub answer_version_id: Option<Uuid>,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default)]
    pub task_type: ReviewTaskType,
    #[serde(default = "default_priority")]
    pub priority: i32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub assigned_to: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub created_by: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub due_date: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<String>,
}

fn default_priority() -> i32 {
    3
}

// ── Review Comment ──

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum CommentType {
    Comment,
    Suggestion,
    Approval,
    Rejection,
    Question,
    Resolution,
}

impl Default for CommentType {
    fn default() -> Self {
        Self::Comment
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewComment {
    pub id: Uuid,
    pub review_task_id: Uuid,
    pub parent_comment_id: Option<Uuid>,
    pub author_id: Option<Uuid>,
    pub content: String,
    pub comment_type: CommentType,
    pub resolved: bool,
    pub resolved_at: Option<DateTime<Utc>>,
    pub resolved_by: Option<Uuid>,
    #[serde(default)]
    pub metadata: serde_json::Value,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateReviewComment {
    pub review_task_id: Uuid,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_comment_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub author_id: Option<Uuid>,
    pub content: String,
    #[serde(default)]
    pub comment_type: CommentType,
}

// ── Source Review ──

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum SourceVerdict {
    Pending,
    Trusted,
    Questionable,
    Unreliable,
    Flagged,
}

impl Default for SourceVerdict {
    fn default() -> Self {
        Self::Pending
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceReview {
    pub id: Uuid,
    pub workspace_id: Uuid,
    pub document_id: Uuid,
    pub chunk_id: Option<Uuid>,
    pub review_task_id: Option<Uuid>,
    pub reviewer_id: Option<Uuid>,
    pub verdict: SourceVerdict,
    pub relevance_score: Option<f64>,
    pub accuracy_score: Option<f64>,
    pub freshness_score: Option<f64>,
    pub authority_score: Option<f64>,
    pub overall_score: Option<f64>,
    pub notes: Option<String>,
    pub is_trusted: Option<bool>,
    pub flagged_issues: Vec<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateSourceReview {
    pub workspace_id: Uuid,
    pub document_id: Uuid,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub chunk_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub review_task_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reviewer_id: Option<Uuid>,
    #[serde(default)]
    pub verdict: SourceVerdict,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub relevance_score: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub accuracy_score: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub freshness_score: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub authority_score: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub overall_score: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub flagged_issues: Vec<String>,
}

pub fn validate_score(score: Option<f64>) -> anyhow::Result<()> {
    if let Some(s) = score {
        if !(0.0..=1.0).contains(&s) {
            anyhow::bail!("Score must be between 0.0 and 1.0, got {}", s);
        }
    }
    Ok(())
}

// ── Database operations (PostgreSQL) ──

#[cfg(feature = "postgres")]
pub async fn create_review_task(
    pool: &DbPool,
    input: &CreateReviewTask,
) -> anyhow::Result<Uuid> {
    let task_type = serde_json::to_value(&input.task_type)?
        .as_str()
        .unwrap_or("general")
        .to_string();

    let row: (Uuid,) = sqlx::query_as(
        r#"
        INSERT INTO review_tasks
            (workspace_id, message_id, answer_version_id, title, description,
             task_type, priority, assigned_to, created_by, due_date, tags)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        RETURNING id
        "#,
    )
    .bind(input.workspace_id)
    .bind(input.message_id)
    .bind(input.answer_version_id)
    .bind(&input.title)
    .bind(&input.description)
    .bind(&task_type)
    .bind(input.priority)
    .bind(input.assigned_to)
    .bind(input.created_by)
    .bind(input.due_date)
    .bind(&input.tags)
    .fetch_one(pool)
    .await?;

    Ok(row.0)
}

#[cfg(feature = "postgres")]
pub async fn create_review_comment(
    pool: &DbPool,
    input: &CreateReviewComment,
) -> anyhow::Result<Uuid> {
    let comment_type = serde_json::to_value(&input.comment_type)?
        .as_str()
        .unwrap_or("comment")
        .to_string();

    let row: (Uuid,) = sqlx::query_as(
        r#"
        INSERT INTO review_comments
            (review_task_id, parent_comment_id, author_id, content, comment_type)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id
        "#,
    )
    .bind(input.review_task_id)
    .bind(input.parent_comment_id)
    .bind(input.author_id)
    .bind(&input.content)
    .bind(&comment_type)
    .fetch_one(pool)
    .await?;

    Ok(row.0)
}

#[cfg(feature = "postgres")]
pub async fn create_source_review(
    pool: &DbPool,
    input: &CreateSourceReview,
) -> anyhow::Result<Uuid> {
    validate_score(input.relevance_score)?;
    validate_score(input.accuracy_score)?;
    validate_score(input.freshness_score)?;
    validate_score(input.authority_score)?;
    validate_score(input.overall_score)?;

    let verdict = serde_json::to_value(&input.verdict)?
        .as_str()
        .unwrap_or("pending")
        .to_string();

    let row: (Uuid,) = sqlx::query_as(
        r#"
        INSERT INTO source_reviews
            (workspace_id, document_id, chunk_id, review_task_id, reviewer_id,
             verdict, relevance_score, accuracy_score, freshness_score,
             authority_score, overall_score, notes, flagged_issues)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
        RETURNING id
        "#,
    )
    .bind(input.workspace_id)
    .bind(input.document_id)
    .bind(input.chunk_id)
    .bind(input.review_task_id)
    .bind(input.reviewer_id)
    .bind(&verdict)
    .bind(input.relevance_score)
    .bind(input.accuracy_score)
    .bind(input.freshness_score)
    .bind(input.authority_score)
    .bind(input.overall_score)
    .bind(&input.notes)
    .bind(&input.flagged_issues)
    .fetch_one(pool)
    .await?;

    Ok(row.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_review_task_status_serde() {
        let statuses = vec![
            ReviewTaskStatus::Open,
            ReviewTaskStatus::InProgress,
            ReviewTaskStatus::NeedsRevision,
            ReviewTaskStatus::Approved,
            ReviewTaskStatus::Rejected,
            ReviewTaskStatus::Closed,
        ];
        for s in statuses {
            let json = serde_json::to_string(&s).unwrap();
            let back: ReviewTaskStatus = serde_json::from_str(&json).unwrap();
            assert_eq!(back, s);
        }
    }

    #[test]
    fn test_review_task_type_serde() {
        let types = vec![
            ReviewTaskType::General,
            ReviewTaskType::FactCheck,
            ReviewTaskType::SourceVerification,
            ReviewTaskType::ContentReview,
            ReviewTaskType::SecurityAudit,
        ];
        for t in types {
            let json = serde_json::to_string(&t).unwrap();
            let back: ReviewTaskType = serde_json::from_str(&json).unwrap();
            assert_eq!(back, t);
        }
    }

    #[test]
    fn test_comment_type_serde() {
        let types = vec![
            CommentType::Comment,
            CommentType::Suggestion,
            CommentType::Approval,
            CommentType::Rejection,
            CommentType::Question,
            CommentType::Resolution,
        ];
        for t in types {
            let json = serde_json::to_string(&t).unwrap();
            let back: CommentType = serde_json::from_str(&json).unwrap();
            assert_eq!(back, t);
        }
    }

    #[test]
    fn test_source_verdict_serde() {
        let verdicts = vec![
            SourceVerdict::Pending,
            SourceVerdict::Trusted,
            SourceVerdict::Questionable,
            SourceVerdict::Unreliable,
            SourceVerdict::Flagged,
        ];
        for v in verdicts {
            let json = serde_json::to_string(&v).unwrap();
            let back: SourceVerdict = serde_json::from_str(&json).unwrap();
            assert_eq!(back, v);
        }
    }

    #[test]
    fn test_create_review_task_deserialize() {
        let json = r#"{
            "workspace_id": "00000000-0000-0000-0000-000000000001",
            "title": "Review AI answer for accuracy",
            "task_type": "fact_check",
            "priority": 1
        }"#;
        let task: CreateReviewTask = serde_json::from_str(json).unwrap();
        assert_eq!(task.title, "Review AI answer for accuracy");
        assert_eq!(task.task_type, ReviewTaskType::FactCheck);
        assert_eq!(task.priority, 1);
        assert!(task.message_id.is_none());
    }

    #[test]
    fn test_create_review_task_defaults() {
        let json = r#"{
            "workspace_id": "00000000-0000-0000-0000-000000000001",
            "title": "Basic review"
        }"#;
        let task: CreateReviewTask = serde_json::from_str(json).unwrap();
        assert_eq!(task.task_type, ReviewTaskType::General);
        assert_eq!(task.priority, 3);
        assert!(task.tags.is_empty());
    }

    #[test]
    fn test_create_review_comment_deserialize() {
        let json = r#"{
            "review_task_id": "00000000-0000-0000-0000-000000000001",
            "content": "This source seems outdated",
            "comment_type": "suggestion"
        }"#;
        let comment: CreateReviewComment = serde_json::from_str(json).unwrap();
        assert_eq!(comment.content, "This source seems outdated");
        assert_eq!(comment.comment_type, CommentType::Suggestion);
    }

    #[test]
    fn test_create_source_review_deserialize() {
        let json = r#"{
            "workspace_id": "00000000-0000-0000-0000-000000000001",
            "document_id": "00000000-0000-0000-0000-000000000002",
            "verdict": "trusted",
            "relevance_score": 0.9,
            "accuracy_score": 0.85,
            "notes": "High quality peer-reviewed source"
        }"#;
        let review: CreateSourceReview = serde_json::from_str(json).unwrap();
        assert_eq!(review.verdict, SourceVerdict::Trusted);
        assert_eq!(review.relevance_score, Some(0.9));
        assert_eq!(review.notes.as_deref(), Some("High quality peer-reviewed source"));
    }

    #[test]
    fn test_validate_score_valid() {
        assert!(validate_score(None).is_ok());
        assert!(validate_score(Some(0.0)).is_ok());
        assert!(validate_score(Some(0.5)).is_ok());
        assert!(validate_score(Some(1.0)).is_ok());
    }

    #[test]
    fn test_validate_score_invalid() {
        assert!(validate_score(Some(-0.1)).is_err());
        assert!(validate_score(Some(1.1)).is_err());
        assert!(validate_score(Some(2.0)).is_err());
    }

    #[test]
    fn test_source_review_with_flagged_issues() {
        let json = r#"{
            "workspace_id": "00000000-0000-0000-0000-000000000001",
            "document_id": "00000000-0000-0000-0000-000000000002",
            "verdict": "flagged",
            "flagged_issues": ["outdated_data", "missing_citations", "potential_bias"]
        }"#;
        let review: CreateSourceReview = serde_json::from_str(json).unwrap();
        assert_eq!(review.verdict, SourceVerdict::Flagged);
        assert_eq!(review.flagged_issues.len(), 3);
    }

    #[test]
    fn test_review_task_with_tags() {
        let json = r#"{
            "workspace_id": "00000000-0000-0000-0000-000000000001",
            "title": "Security audit",
            "task_type": "security_audit",
            "tags": ["critical", "production", "pii"]
        }"#;
        let task: CreateReviewTask = serde_json::from_str(json).unwrap();
        assert_eq!(task.task_type, ReviewTaskType::SecurityAudit);
        assert_eq!(task.tags.len(), 3);
    }

    #[test]
    fn test_threaded_comment_structure() {
        let parent_id = Uuid::new_v4();
        let json = format!(
            r#"{{
                "review_task_id": "00000000-0000-0000-0000-000000000001",
                "parent_comment_id": "{}",
                "content": "Reply to parent comment",
                "comment_type": "resolution"
            }}"#,
            parent_id
        );
        let comment: CreateReviewComment = serde_json::from_str(&json).unwrap();
        assert_eq!(comment.parent_comment_id, Some(parent_id));
        assert_eq!(comment.comment_type, CommentType::Resolution);
    }
}
