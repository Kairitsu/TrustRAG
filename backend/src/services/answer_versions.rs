use anyhow::Result;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use crate::db::DbPool;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct AnswerVersion {
    pub id: Uuid,
    pub message_id: Uuid,
    pub version_number: i32,
    pub content: String,
    pub answer_status: String,
    pub retrieval_trace_id: Option<Uuid>,
    pub reviewer_id: Option<Uuid>,
    pub review_comment: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateVersionInput {
    pub message_id: Uuid,
    pub content: String,
    pub answer_status: Option<String>,
    pub retrieval_trace_id: Option<Uuid>,
}

pub async fn create_version(pool: &DbPool, input: &CreateVersionInput) -> Result<AnswerVersion> {
    let next_version: (Option<i32>,) = sqlx::query_as(
        "SELECT MAX(version_number) FROM answer_versions WHERE message_id = $1",
    )
    .bind(input.message_id)
    .fetch_one(pool)
    .await?;

    let version_number = next_version.0.unwrap_or(0) + 1;
    let status = input.answer_status.as_deref().unwrap_or("draft");

    let row = sqlx::query_as::<_, AnswerVersion>(
        r#"
        INSERT INTO answer_versions (message_id, version_number, content, answer_status, retrieval_trace_id)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING *
        "#,
    )
    .bind(input.message_id)
    .bind(version_number)
    .bind(&input.content)
    .bind(status)
    .bind(input.retrieval_trace_id)
    .fetch_one(pool)
    .await?;

    tracing::info!(
        message_id = %input.message_id,
        version = version_number,
        "Answer version created"
    );

    Ok(row)
}

pub async fn get_version(pool: &DbPool, version_id: Uuid) -> Result<Option<AnswerVersion>> {
    let row = sqlx::query_as::<_, AnswerVersion>(
        "SELECT * FROM answer_versions WHERE id = $1",
    )
    .bind(version_id)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

pub async fn list_versions(pool: &DbPool, message_id: Uuid) -> Result<Vec<AnswerVersion>> {
    let rows = sqlx::query_as::<_, AnswerVersion>(
        "SELECT * FROM answer_versions WHERE message_id = $1 ORDER BY version_number DESC",
    )
    .bind(message_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn get_latest_version(pool: &DbPool, message_id: Uuid) -> Result<Option<AnswerVersion>> {
    let row = sqlx::query_as::<_, AnswerVersion>(
        "SELECT * FROM answer_versions WHERE message_id = $1 ORDER BY version_number DESC LIMIT 1",
    )
    .bind(message_id)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

pub async fn update_version_status(
    pool: &DbPool,
    version_id: Uuid,
    new_status: &str,
    reviewer_id: Option<Uuid>,
    review_comment: Option<&str>,
) -> Result<AnswerVersion> {
    let row = sqlx::query_as::<_, AnswerVersion>(
        r#"
        UPDATE answer_versions
        SET answer_status = $2, reviewer_id = $3, review_comment = $4
        WHERE id = $1
        RETURNING *
        "#,
    )
    .bind(version_id)
    .bind(new_status)
    .bind(reviewer_id)
    .bind(review_comment)
    .fetch_one(pool)
    .await?;

    tracing::info!(
        version_id = %version_id,
        new_status = new_status,
        "Answer version status updated"
    );

    Ok(row)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_version_input_deserialize() {
        let json = r#"{
            "message_id": "550e8400-e29b-41d4-a716-446655440000",
            "content": "This is the answer content.",
            "answer_status": "draft"
        }"#;
        let input: CreateVersionInput = serde_json::from_str(json).unwrap();
        assert_eq!(input.content, "This is the answer content.");
        assert_eq!(input.answer_status.as_deref(), Some("draft"));
        assert!(input.retrieval_trace_id.is_none());
    }

    #[test]
    fn test_create_version_input_minimal() {
        let json = r#"{
            "message_id": "550e8400-e29b-41d4-a716-446655440000",
            "content": "Answer text"
        }"#;
        let input: CreateVersionInput = serde_json::from_str(json).unwrap();
        assert!(input.answer_status.is_none());
        assert!(input.retrieval_trace_id.is_none());
    }

    #[test]
    fn test_create_version_input_with_trace() {
        let json = r#"{
            "message_id": "550e8400-e29b-41d4-a716-446655440000",
            "content": "Answer with trace",
            "retrieval_trace_id": "660e8400-e29b-41d4-a716-446655440001"
        }"#;
        let input: CreateVersionInput = serde_json::from_str(json).unwrap();
        assert!(input.retrieval_trace_id.is_some());
    }

    #[test]
    fn test_answer_version_serialization() {
        let version = AnswerVersion {
            id: Uuid::new_v4(),
            message_id: Uuid::new_v4(),
            version_number: 3,
            content: "Third version of the answer".to_string(),
            answer_status: "verified".to_string(),
            retrieval_trace_id: Some(Uuid::new_v4()),
            reviewer_id: Some(Uuid::new_v4()),
            review_comment: Some("Looks good".to_string()),
            created_at: chrono::Utc::now(),
        };
        let json = serde_json::to_value(&version).unwrap();
        assert_eq!(json["version_number"], 3);
        assert_eq!(json["answer_status"], "verified");
        assert_eq!(json["review_comment"], "Looks good");
    }

    #[test]
    fn test_answer_version_status_values() {
        let valid_statuses = ["draft", "needs_review", "verified", "rejected", "published"];
        for status in &valid_statuses {
            let version = AnswerVersion {
                id: Uuid::new_v4(),
                message_id: Uuid::new_v4(),
                version_number: 1,
                content: "test".to_string(),
                answer_status: status.to_string(),
                retrieval_trace_id: None,
                reviewer_id: None,
                review_comment: None,
                created_at: chrono::Utc::now(),
            };
            assert_eq!(version.answer_status, *status);
        }
    }

    #[test]
    fn test_answer_version_no_reviewer() {
        let version = AnswerVersion {
            id: Uuid::new_v4(),
            message_id: Uuid::new_v4(),
            version_number: 1,
            content: "draft answer".to_string(),
            answer_status: "draft".to_string(),
            retrieval_trace_id: None,
            reviewer_id: None,
            review_comment: None,
            created_at: chrono::Utc::now(),
        };
        assert!(version.reviewer_id.is_none());
        assert!(version.review_comment.is_none());
    }
}
