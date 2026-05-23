use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::DbPool;

/// Answer lifecycle states for human-in-the-loop verification.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AnswerStatus {
    Draft,
    NeedsReview,
    Verified,
    Rejected,
    Published,
}

impl AnswerStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Draft => "draft",
            Self::NeedsReview => "needs_review",
            Self::Verified => "verified",
            Self::Rejected => "rejected",
            Self::Published => "published",
        }
    }

    pub fn from_str(s: &str) -> Result<Self> {
        match s {
            "draft" => Ok(Self::Draft),
            "needs_review" => Ok(Self::NeedsReview),
            "verified" => Ok(Self::Verified),
            "rejected" => Ok(Self::Rejected),
            "published" => Ok(Self::Published),
            _ => bail!("Invalid answer status: '{s}'"),
        }
    }

    /// Valid transitions enforced by the state machine:
    ///
    /// ```text
    /// draft ──► needs_review ──► verified ──► published
    ///               │                │
    ///               └──► rejected ◄──┘
    ///               │         │
    ///               │         └──► draft (rewrite cycle)
    ///               └──► draft (send back for editing)
    /// ```
    pub fn can_transition_to(&self, target: AnswerStatus) -> bool {
        matches!(
            (self, target),
            (Self::Draft, Self::NeedsReview)
                | (Self::NeedsReview, Self::Verified)
                | (Self::NeedsReview, Self::Rejected)
                | (Self::NeedsReview, Self::Draft)
                | (Self::Verified, Self::Published)
                | (Self::Verified, Self::Rejected)
                | (Self::Rejected, Self::Draft)
        )
    }

    /// All statuses reachable from the current one.
    pub fn allowed_transitions(&self) -> Vec<AnswerStatus> {
        let all = [
            Self::Draft,
            Self::NeedsReview,
            Self::Verified,
            Self::Rejected,
            Self::Published,
        ];
        all.iter()
            .copied()
            .filter(|t| self.can_transition_to(*t))
            .collect()
    }
}

impl Default for AnswerStatus {
    fn default() -> Self {
        Self::Draft
    }
}

impl std::fmt::Display for AnswerStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

#[derive(Debug, Deserialize)]
pub struct UpdateAnswerStatusInput {
    pub status: String,
    pub reason: Option<String>,
}

/// Transition a message's answer_status, enforcing the state machine.
pub async fn update_answer_status(
    pool: &DbPool,
    message_id: Uuid,
    new_status: &str,
) -> Result<AnswerStatus> {
    let target = AnswerStatus::from_str(new_status)?;

    let current_str: Option<String> = sqlx::query_scalar(
        "SELECT answer_status FROM messages WHERE id = $1",
    )
    .bind(message_id)
    .fetch_optional(pool)
    .await?;

    let current_str = current_str.ok_or_else(|| anyhow::anyhow!("Message not found: {message_id}"))?;
    let current = AnswerStatus::from_str(&current_str)?;

    if !current.can_transition_to(target) {
        let allowed: Vec<_> = current.allowed_transitions().iter().map(|s| s.as_str()).collect();
        bail!(
            "Cannot transition from '{}' to '{}'. Allowed: {:?}",
            current.as_str(),
            target.as_str(),
            allowed
        );
    }

    sqlx::query("UPDATE messages SET answer_status = $1 WHERE id = $2")
        .bind(target.as_str())
        .bind(message_id)
        .execute(pool)
        .await?;

    Ok(target)
}

/// Get the current answer status for a message.
pub async fn get_answer_status(
    pool: &DbPool,
    message_id: Uuid,
) -> Result<AnswerStatus> {
    let status_str: Option<String> = sqlx::query_scalar(
        "SELECT answer_status FROM messages WHERE id = $1",
    )
    .bind(message_id)
    .fetch_optional(pool)
    .await?;

    let status_str = status_str.ok_or_else(|| anyhow::anyhow!("Message not found: {message_id}"))?;
    AnswerStatus::from_str(&status_str)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_answer_status_from_str() {
        assert_eq!(AnswerStatus::from_str("draft").unwrap(), AnswerStatus::Draft);
        assert_eq!(AnswerStatus::from_str("needs_review").unwrap(), AnswerStatus::NeedsReview);
        assert_eq!(AnswerStatus::from_str("verified").unwrap(), AnswerStatus::Verified);
        assert_eq!(AnswerStatus::from_str("rejected").unwrap(), AnswerStatus::Rejected);
        assert_eq!(AnswerStatus::from_str("published").unwrap(), AnswerStatus::Published);
        assert!(AnswerStatus::from_str("invalid").is_err());
    }

    #[test]
    fn test_answer_status_as_str() {
        assert_eq!(AnswerStatus::Draft.as_str(), "draft");
        assert_eq!(AnswerStatus::NeedsReview.as_str(), "needs_review");
        assert_eq!(AnswerStatus::Verified.as_str(), "verified");
        assert_eq!(AnswerStatus::Rejected.as_str(), "rejected");
        assert_eq!(AnswerStatus::Published.as_str(), "published");
    }

    #[test]
    fn test_valid_transitions() {
        assert!(AnswerStatus::Draft.can_transition_to(AnswerStatus::NeedsReview));
        assert!(AnswerStatus::NeedsReview.can_transition_to(AnswerStatus::Verified));
        assert!(AnswerStatus::NeedsReview.can_transition_to(AnswerStatus::Rejected));
        assert!(AnswerStatus::NeedsReview.can_transition_to(AnswerStatus::Draft));
        assert!(AnswerStatus::Verified.can_transition_to(AnswerStatus::Published));
        assert!(AnswerStatus::Verified.can_transition_to(AnswerStatus::Rejected));
        assert!(AnswerStatus::Rejected.can_transition_to(AnswerStatus::Draft));
    }

    #[test]
    fn test_invalid_transitions() {
        assert!(!AnswerStatus::Draft.can_transition_to(AnswerStatus::Verified));
        assert!(!AnswerStatus::Draft.can_transition_to(AnswerStatus::Published));
        assert!(!AnswerStatus::Draft.can_transition_to(AnswerStatus::Rejected));
        assert!(!AnswerStatus::Draft.can_transition_to(AnswerStatus::Draft));
        assert!(!AnswerStatus::NeedsReview.can_transition_to(AnswerStatus::Published));
        assert!(!AnswerStatus::Published.can_transition_to(AnswerStatus::Draft));
        assert!(!AnswerStatus::Published.can_transition_to(AnswerStatus::NeedsReview));
        assert!(!AnswerStatus::Rejected.can_transition_to(AnswerStatus::Verified));
        assert!(!AnswerStatus::Rejected.can_transition_to(AnswerStatus::Published));
    }

    #[test]
    fn test_allowed_transitions() {
        assert_eq!(
            AnswerStatus::Draft.allowed_transitions(),
            vec![AnswerStatus::NeedsReview]
        );
        assert_eq!(
            AnswerStatus::NeedsReview.allowed_transitions(),
            vec![AnswerStatus::Draft, AnswerStatus::Verified, AnswerStatus::Rejected]
        );
        assert_eq!(
            AnswerStatus::Verified.allowed_transitions(),
            vec![AnswerStatus::Rejected, AnswerStatus::Published]
        );
        assert_eq!(
            AnswerStatus::Rejected.allowed_transitions(),
            vec![AnswerStatus::Draft]
        );
        assert!(AnswerStatus::Published.allowed_transitions().is_empty());
    }

    #[test]
    fn test_serde_roundtrip() {
        let statuses = vec![
            AnswerStatus::Draft,
            AnswerStatus::NeedsReview,
            AnswerStatus::Verified,
            AnswerStatus::Rejected,
            AnswerStatus::Published,
        ];
        for status in statuses {
            let json = serde_json::to_string(&status).unwrap();
            let deserialized: AnswerStatus = serde_json::from_str(&json).unwrap();
            assert_eq!(status, deserialized);
        }
    }

    #[test]
    fn test_serde_values() {
        assert_eq!(serde_json::to_string(&AnswerStatus::Draft).unwrap(), "\"draft\"");
        assert_eq!(serde_json::to_string(&AnswerStatus::NeedsReview).unwrap(), "\"needs_review\"");
        assert_eq!(serde_json::to_string(&AnswerStatus::Published).unwrap(), "\"published\"");
    }

    #[test]
    fn test_default_is_draft() {
        assert_eq!(AnswerStatus::default(), AnswerStatus::Draft);
    }

    #[test]
    fn test_display() {
        assert_eq!(format!("{}", AnswerStatus::Draft), "draft");
        assert_eq!(format!("{}", AnswerStatus::NeedsReview), "needs_review");
        assert_eq!(format!("{}", AnswerStatus::Published), "published");
    }

    #[test]
    fn test_full_lifecycle() {
        let mut status = AnswerStatus::Draft;

        assert!(status.can_transition_to(AnswerStatus::NeedsReview));
        status = AnswerStatus::NeedsReview;

        assert!(status.can_transition_to(AnswerStatus::Verified));
        status = AnswerStatus::Verified;

        assert!(status.can_transition_to(AnswerStatus::Published));
        status = AnswerStatus::Published;

        assert!(status.allowed_transitions().is_empty());
    }

    #[test]
    fn test_rejection_rewrite_cycle() {
        let mut status = AnswerStatus::Draft;

        status = AnswerStatus::NeedsReview;
        assert!(status.can_transition_to(AnswerStatus::Rejected));
        status = AnswerStatus::Rejected;

        assert!(status.can_transition_to(AnswerStatus::Draft));
        status = AnswerStatus::Draft;

        assert!(status.can_transition_to(AnswerStatus::NeedsReview));
        let _ = status;
    }
}
