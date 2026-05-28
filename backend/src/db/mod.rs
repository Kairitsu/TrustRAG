pub mod compat;
pub mod models;

#[cfg(feature = "postgres")]
mod pg;
#[cfg(sqlite_mode)]
mod sqlite;

#[cfg(feature = "postgres")]
pub use pg::*;
#[cfg(sqlite_mode)]
pub use sqlite::*;

#[cfg(feature = "postgres")]
pub type DbPool = sqlx::PgPool;
#[cfg(sqlite_mode)]
pub type DbPool = sqlx::SqlitePool;

#[cfg(sqlite_mode)]
pub use sqlite::{
    CURRENT_SCHEMA_VERSION,
    get_schema_version,
    set_schema_version,
    run_migrations,
    validate_token_user,
    backup_database,
};
