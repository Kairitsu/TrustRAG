use anyhow::Result;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::DbPool;

/// Represents a single entry in the audit trail.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEntry {
    pub id: Uuid,
    pub workspace_id: Option<Uuid>,
    pub user_id: Option<Uuid>,
    pub action: String,
    pub entity_type: String,
    pub entity_id: Option<Uuid>,
    pub details: serde_json::Value,
    pub ip_address: Option<String>,
    pub created_at: String,
}

/// Common audit action types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AuditAction {
    DocumentUploaded,
    DocumentDeleted,
    DocumentMetadataExtracted,
    QueryExecuted,
    AnswerGenerated,
    CitationCreated,
    ReviewCreated,
    ReviewUpdated,
    EvidenceVerified,
    WorkspaceCreated,
    WorkspaceUpdated,
    DomainProfileUpdated,
    UserLogin,
    UserLogout,
    SettingsChanged,
}

impl AuditAction {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::DocumentUploaded => "document_uploaded",
            Self::DocumentDeleted => "document_deleted",
            Self::DocumentMetadataExtracted => "document_metadata_extracted",
            Self::QueryExecuted => "query_executed",
            Self::AnswerGenerated => "answer_generated",
            Self::CitationCreated => "citation_created",
            Self::ReviewCreated => "review_created",
            Self::ReviewUpdated => "review_updated",
            Self::EvidenceVerified => "evidence_verified",
            Self::WorkspaceCreated => "workspace_created",
            Self::WorkspaceUpdated => "workspace_updated",
            Self::DomainProfileUpdated => "domain_profile_updated",
            Self::UserLogin => "user_login",
            Self::UserLogout => "user_logout",
            Self::SettingsChanged => "settings_changed",
        }
    }
}

/// Common entity types referenced by audit entries.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EntityType {
    Document,
    Message,
    Citation,
    Review,
    Workspace,
    User,
    Conversation,
}

impl EntityType {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Document => "document",
            Self::Message => "message",
            Self::Citation => "citation",
            Self::Review => "review",
            Self::Workspace => "workspace",
            Self::User => "user",
            Self::Conversation => "conversation",
        }
    }
}

/// Record an audit entry.
pub async fn log(
    pool: &DbPool,
    workspace_id: Option<Uuid>,
    user_id: Option<Uuid>,
    action: AuditAction,
    entity_type: EntityType,
    entity_id: Option<Uuid>,
    details: serde_json::Value,
    ip_address: Option<&str>,
) -> Result<Uuid> {
    let id: String = sqlx::query_scalar(
        r#"INSERT INTO audit_trail (workspace_id, user_id, action, entity_type, entity_id, details, ip_address)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           RETURNING id"#,
    )
    .bind(workspace_id.map(|id| id.to_string()))
    .bind(user_id.map(|id| id.to_string()))
    .bind(action.as_str())
    .bind(entity_type.as_str())
    .bind(entity_id.map(|id| id.to_string()))
    .bind(&details)
    .bind(ip_address)
    .fetch_one(pool)
    .await?;

    Ok(id.parse()?)
}

/// Query audit trail with filters.
pub async fn query(
    pool: &DbPool,
    workspace_id: Option<Uuid>,
    user_id: Option<Uuid>,
    action_filter: Option<&str>,
    limit: i64,
    offset: i64,
) -> Result<Vec<AuditEntry>> {
    type AuditRow = (String, Option<String>, Option<String>, String, String, Option<String>, serde_json::Value, Option<String>, String);

    let rows = if let Some(ws_id) = workspace_id {
        if let Some(action) = action_filter {
            sqlx::query_as::<_, AuditRow>(
                r#"SELECT id, workspace_id, user_id, action, entity_type, entity_id, details, ip_address, CAST(created_at AS TEXT)
                   FROM audit_trail WHERE workspace_id = $1 AND action = $2
                   ORDER BY created_at DESC LIMIT $3 OFFSET $4"#,
            )
            .bind(ws_id.to_string())
            .bind(action)
            .bind(limit)
            .bind(offset)
            .fetch_all(pool)
            .await?
        } else {
            sqlx::query_as::<_, AuditRow>(
                r#"SELECT id, workspace_id, user_id, action, entity_type, entity_id, details, ip_address, CAST(created_at AS TEXT)
                   FROM audit_trail WHERE workspace_id = $1
                   ORDER BY created_at DESC LIMIT $3 OFFSET $4"#,
            )
            .bind(ws_id.to_string())
            .bind(limit)
            .bind(offset)
            .fetch_all(pool)
            .await?
        }
    } else if let Some(u_id) = user_id {
        sqlx::query_as::<_, AuditRow>(
            r#"SELECT id, workspace_id, user_id, action, entity_type, entity_id, details, ip_address, CAST(created_at AS TEXT)
               FROM audit_trail WHERE user_id = $1
               ORDER BY created_at DESC LIMIT $2 OFFSET $3"#,
        )
        .bind(u_id.to_string())
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query_as::<_, AuditRow>(
            r#"SELECT id, workspace_id, user_id, action, entity_type, entity_id, details, ip_address, CAST(created_at AS TEXT)
               FROM audit_trail
               ORDER BY created_at DESC LIMIT $1 OFFSET $2"#,
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await?
    };

    Ok(rows.into_iter().map(|r| AuditEntry {
        id: r.0.parse().unwrap_or_default(),
        workspace_id: r.1.and_then(|s| s.parse().ok()),
        user_id: r.2.and_then(|s| s.parse().ok()),
        action: r.3,
        entity_type: r.4,
        entity_id: r.5.and_then(|s| s.parse().ok()),
        details: r.6,
        ip_address: r.7,
        created_at: r.8,
    }).collect())
}

/// Count audit entries matching filters.
pub async fn count(
    pool: &DbPool,
    workspace_id: Option<Uuid>,
    action_filter: Option<&str>,
) -> Result<i64> {
    let count: i64 = if let Some(ws_id) = workspace_id {
        if let Some(action) = action_filter {
            sqlx::query_scalar(
                "SELECT COUNT(*) FROM audit_trail WHERE workspace_id = $1 AND action = $2"
            )
            .bind(ws_id.to_string())
            .bind(action)
            .fetch_one(pool)
            .await?
        } else {
            sqlx::query_scalar(
                "SELECT COUNT(*) FROM audit_trail WHERE workspace_id = $1"
            )
            .bind(ws_id.to_string())
            .fetch_one(pool)
            .await?
        }
    } else {
        sqlx::query_scalar("SELECT COUNT(*) FROM audit_trail")
            .fetch_one(pool)
            .await?
    };

    Ok(count)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_audit_action_as_str() {
        assert_eq!(AuditAction::DocumentUploaded.as_str(), "document_uploaded");
        assert_eq!(AuditAction::ReviewCreated.as_str(), "review_created");
        assert_eq!(AuditAction::EvidenceVerified.as_str(), "evidence_verified");
    }

    #[test]
    fn test_entity_type_as_str() {
        assert_eq!(EntityType::Document.as_str(), "document");
        assert_eq!(EntityType::Citation.as_str(), "citation");
        assert_eq!(EntityType::Review.as_str(), "review");
    }

    #[test]
    fn test_audit_action_serde_roundtrip() {
        let action = AuditAction::AnswerGenerated;
        let json = serde_json::to_string(&action).unwrap();
        let deserialized: AuditAction = serde_json::from_str(&json).unwrap();
        assert_eq!(action, deserialized);
    }

    #[test]
    fn test_audit_entry_serde() {
        let entry = AuditEntry {
            id: Uuid::new_v4(),
            workspace_id: Some(Uuid::new_v4()),
            user_id: Some(Uuid::new_v4()),
            action: "document_uploaded".to_string(),
            entity_type: "document".to_string(),
            entity_id: Some(Uuid::new_v4()),
            details: serde_json::json!({"filename": "test.pdf", "size": 1024}),
            ip_address: Some("192.168.1.1".to_string()),
            created_at: "2026-05-22 06:00:00".to_string(),
        };
        let json = serde_json::to_string(&entry).unwrap();
        let deserialized: AuditEntry = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.action, "document_uploaded");
    }

    #[test]
    fn test_all_audit_actions_have_str() {
        let actions = vec![
            AuditAction::DocumentUploaded,
            AuditAction::DocumentDeleted,
            AuditAction::DocumentMetadataExtracted,
            AuditAction::QueryExecuted,
            AuditAction::AnswerGenerated,
            AuditAction::CitationCreated,
            AuditAction::ReviewCreated,
            AuditAction::ReviewUpdated,
            AuditAction::EvidenceVerified,
            AuditAction::WorkspaceCreated,
            AuditAction::WorkspaceUpdated,
            AuditAction::DomainProfileUpdated,
            AuditAction::UserLogin,
            AuditAction::UserLogout,
            AuditAction::SettingsChanged,
        ];
        for action in actions {
            assert!(!action.as_str().is_empty());
        }
    }
}
