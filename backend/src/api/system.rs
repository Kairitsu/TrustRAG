use axum::{
    extract::State,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};

use crate::auth::middleware::AuthUser;
use crate::error::AppError;

use super::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/system/db-info", get(db_info))
        .route("/system/backup-db", post(backup_db))
        .route("/system/reset-db", post(reset_db))
        .route("/system/validate-token", get(validate_token))
        .route("/system/ocr-status", get(ocr_status))
        .route("/system/ocr-install-options", get(ocr_install_options))
        .route("/system/ocr-install", post(ocr_install))
}

#[derive(Serialize)]
struct DbInfo {
    schema_version: i32,
    current_version: i32,
    needs_migration: bool,
    db_path: String,
}

async fn db_info(
    State(state): State<AppState>,
    _auth: AuthUser,
) -> Result<Json<DbInfo>, AppError> {
    let version = crate::db::get_schema_version(&state.pool).await
        .map_err(|e| AppError::Internal(e))?;

    let current = crate::db::CURRENT_SCHEMA_VERSION;

    let db_path = std::env::var("TRUSTRAG__DATABASE_URL")
        .unwrap_or_else(|_| "unknown".into());

    Ok(Json(DbInfo {
        schema_version: version,
        current_version: current,
        needs_migration: version < current,
        db_path,
    }))
}

#[derive(Serialize)]
struct BackupResult {
    success: bool,
    backup_path: Option<String>,
    message: String,
}

async fn backup_db(
    State(_state): State<AppState>,
    _auth: AuthUser,
) -> Result<Json<BackupResult>, AppError> {
    let data_dir = crate::config::AppConfig::load()
        .map(|c| c.data_dir)
        .unwrap_or_else(|_| ".".into());

    match crate::db::backup_database(&data_dir).await {
        Ok(path) => Ok(Json(BackupResult {
            success: true,
            backup_path: Some(path.clone()),
            message: format!("数据库已备份到: {}", path),
        })),
        Err(e) => Ok(Json(BackupResult {
            success: false,
            backup_path: None,
            message: format!("备份失败: {}", e),
        })),
    }
}

#[derive(Serialize)]
struct ResetResult {
    success: bool,
    message: String,
}

async fn reset_db(
    State(state): State<AppState>,
    _auth: AuthUser,
) -> Result<Json<ResetResult>, AppError> {
    let data_dir = crate::config::AppConfig::load()
        .map(|c| c.data_dir)
        .unwrap_or_else(|_| ".".into());

    match crate::db::backup_database(&data_dir).await {
        Ok(backup_path) => {
            tracing::info!(backup = %backup_path, "Database backed up before reset");
        }
        Err(e) => {
            tracing::warn!(error = %e, "Could not backup before reset, proceeding anyway");
        }
    }

    let tables = vec![
        "review_comments", "source_reviews", "review_tasks",
        "answer_reviews", "claim_reviews", "answer_versions",
        "retrieval_traces", "audit_trail", "document_metadata",
        "entity_relations", "entities",
        "review_records", "citations", "messages", "conversations",
        "embedding_configs", "model_configs",
        "document_chunks", "documents",
        "workspace_members", "workspaces", "users",
    ];

    for table in &tables {
        let sql = format!("DELETE FROM {}", table);
        match sqlx::query(&sql).execute(&state.pool).await {
            Ok(_) => tracing::debug!(table = table, "Table cleared"),
            Err(e) => tracing::warn!(table = table, error = %e, "Failed to clear table"),
        }
    }

    Ok(Json(ResetResult {
        success: true,
        message: "本地数据已重置，请重新注册账号".into(),
    }))
}

#[derive(Serialize)]
struct TokenValidation {
    valid: bool,
    user_exists: bool,
    message: String,
}

async fn validate_token(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<Json<TokenValidation>, AppError> {
    let user_id = auth.id.to_string();
    let exists = crate::db::validate_token_user(&state.pool, &user_id).await
        .unwrap_or(false);

    if exists {
        Ok(Json(TokenValidation {
            valid: true,
            user_exists: true,
            message: "Token 有效且用户存在".into(),
        }))
    } else {
        Ok(Json(TokenValidation {
            valid: true,
            user_exists: false,
            message: "Token 有效但当前数据库中不存在对应用户，请重新登录".into(),
        }))
    }
}

#[derive(Serialize)]
struct OcrToolStatus {
    name: String,
    available: bool,
    version: Option<String>,
    path: Option<String>,
}

#[derive(Serialize)]
struct OcrStatus {
    any_available: bool,
    tools: Vec<OcrToolStatus>,
    recommendation: String,
}

async fn ocr_status(
    _auth: AuthUser,
) -> Result<Json<OcrStatus>, AppError> {
    let mut tools = Vec::new();

    for (name, commands) in [
        ("tesseract", vec!["tesseract", "--version"]),
        ("paddleocr", vec!["python3", "-c", "import paddleocr; print(paddleocr.VERSION)"]),
    ] {
        let try_commands = build_ocr_check_commands(name, &commands);
        let mut found = false;
        let mut found_ver = None;
        let mut found_path = None;

        for (prog, args) in &try_commands {
            let result = tokio::process::Command::new(prog)
                .args(args)
                .output()
                .await;
            if let Ok(output) = result {
                if output.status.success() {
                    let ver = String::from_utf8_lossy(&output.stdout)
                        .lines()
                        .next()
                        .unwrap_or("")
                        .trim()
                        .to_string();
                    found = true;
                    found_ver = Some(ver);
                    found_path = Some(prog.to_string());
                    break;
                }
            }
        }

        tools.push(OcrToolStatus { name: name.into(), available: found, version: found_ver, path: found_path });
    }

    let any = tools.iter().any(|t| t.available);
    let recommendation = if any {
        "已检测到 OCR 工具，可处理扫描版 PDF。".into()
    } else {
        "未检测到 OCR 工具。建议安装 Tesseract (推荐) 或 PaddleOCR:\n\
         • macOS: brew install tesseract tesseract-lang\n\
         • Ubuntu: sudo apt install tesseract-ocr tesseract-ocr-chi-sim\n\
         • Windows: 从 https://github.com/UB-Mannheim/tesseract/wiki 下载安装"
            .into()
    };

    Ok(Json(OcrStatus { any_available: any, tools, recommendation }))
}

fn build_ocr_check_commands(_name: &str, default_commands: &[&str]) -> Vec<(String, Vec<String>)> {
    let attempts = vec![(
        default_commands[0].to_string(),
        default_commands[1..].iter().map(|s| s.to_string()).collect(),
    )];

    #[cfg(target_os = "windows")]
    let attempts = {
        let mut a = attempts;
        if _name == "tesseract" {
            for dir in &[
                r"C:\Program Files\Tesseract-OCR",
                r"C:\Program Files (x86)\Tesseract-OCR",
            ] {
                let exe = format!(r"{}\tesseract.exe", dir);
                a.push((exe, vec!["--version".to_string()]));
            }
        }
        a
    };

    attempts
}

// ---------------------------------------------------------------------------
// 17.9.1  Platform detection & install options
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum OsPlatform {
    Linux,
    MacOs,
    Windows,
}

impl std::fmt::Display for OsPlatform {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Linux => write!(f, "linux"),
            Self::MacOs => write!(f, "macos"),
            Self::Windows => write!(f, "windows"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PackageManager {
    Apt,
    Brew,
    Choco,
    Winget,
    Pip,
    None,
}

impl std::fmt::Display for PackageManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Apt => write!(f, "apt"),
            Self::Brew => write!(f, "brew"),
            Self::Choco => write!(f, "choco"),
            Self::Winget => write!(f, "winget"),
            Self::Pip => write!(f, "pip"),
            Self::None => write!(f, "none"),
        }
    }
}

pub fn detect_platform() -> OsPlatform {
    if cfg!(target_os = "macos") {
        OsPlatform::MacOs
    } else if cfg!(target_os = "windows") {
        OsPlatform::Windows
    } else {
        OsPlatform::Linux
    }
}

pub async fn detect_package_managers() -> Vec<PackageManager> {
    let mut found = Vec::new();
    let candidates: &[(&str, PackageManager)] = &[
        ("apt", PackageManager::Apt),
        ("brew", PackageManager::Brew),
        ("choco", PackageManager::Choco),
        ("winget", PackageManager::Winget),
        ("pip3", PackageManager::Pip),
        ("pip", PackageManager::Pip),
    ];
    for &(bin, pm) in candidates {
        if which::which(bin).is_ok() && !found.contains(&pm) {
            found.push(pm);
        }
    }
    found
}

#[derive(Serialize)]
struct InstallMethod {
    package_manager: PackageManager,
    engine: String,
    command: String,
    needs_sudo: bool,
    description: String,
}

#[derive(Serialize)]
struct OcrInstallOptions {
    platform: OsPlatform,
    available_package_managers: Vec<PackageManager>,
    methods: Vec<InstallMethod>,
    recommended: Option<String>,
}

async fn ocr_install_options(
    _auth: AuthUser,
) -> Result<Json<OcrInstallOptions>, AppError> {
    let platform = detect_platform();
    let managers = detect_package_managers().await;

    let mut methods = Vec::new();

    match platform {
        OsPlatform::Linux => {
            if managers.contains(&PackageManager::Apt) {
                methods.push(InstallMethod {
                    package_manager: PackageManager::Apt,
                    engine: "tesseract".into(),
                    command: "sudo apt install -y tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-eng poppler-utils".into(),
                    needs_sudo: true,
                    description: "通过 apt 安装 Tesseract OCR 及中英文语言包".into(),
                });
            }
            if managers.contains(&PackageManager::Brew) {
                methods.push(InstallMethod {
                    package_manager: PackageManager::Brew,
                    engine: "tesseract".into(),
                    command: "brew install tesseract tesseract-lang poppler".into(),
                    needs_sudo: false,
                    description: "通过 Homebrew 安装 Tesseract OCR (Linuxbrew)".into(),
                });
            }
        }
        OsPlatform::MacOs => {
            if managers.contains(&PackageManager::Brew) {
                methods.push(InstallMethod {
                    package_manager: PackageManager::Brew,
                    engine: "tesseract".into(),
                    command: "brew install tesseract tesseract-lang poppler".into(),
                    needs_sudo: false,
                    description: "通过 Homebrew 安装 Tesseract OCR 及全部语言包".into(),
                });
            }
        }
        OsPlatform::Windows => {
            if managers.contains(&PackageManager::Choco) {
                methods.push(InstallMethod {
                    package_manager: PackageManager::Choco,
                    engine: "tesseract".into(),
                    command: "choco install tesseract -y".into(),
                    needs_sudo: true,
                    description: "通过 Chocolatey 安装 Tesseract OCR".into(),
                });
            }
            if managers.contains(&PackageManager::Winget) {
                methods.push(InstallMethod {
                    package_manager: PackageManager::Winget,
                    engine: "tesseract".into(),
                    command: "winget install UB-Mannheim.TesseractOCR".into(),
                    needs_sudo: false,
                    description: "通过 winget 安装 Tesseract OCR".into(),
                });
            }
        }
    }

    if managers.contains(&PackageManager::Pip) {
        methods.push(InstallMethod {
            package_manager: PackageManager::Pip,
            engine: "paddleocr".into(),
            command: "pip3 install paddleocr paddlepaddle".into(),
            needs_sudo: false,
            description: "通过 pip 安装 PaddleOCR (中文效果优秀)".into(),
        });
    }

    let recommended = methods.first().map(|m| m.engine.clone());

    Ok(Json(OcrInstallOptions {
        platform,
        available_package_managers: managers,
        methods,
        recommended,
    }))
}

// ---------------------------------------------------------------------------
// 17.9.2  OCR install execution
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct OcrInstallRequest {
    engine: String,
    package_manager: String,
}

#[derive(Serialize)]
struct OcrInstallResponse {
    success: bool,
    engine: String,
    package_manager: String,
    output: String,
    message: String,
}

async fn ocr_install(
    _auth: AuthUser,
    Json(req): Json<OcrInstallRequest>,
) -> Result<Json<OcrInstallResponse>, AppError> {
    let platform = detect_platform();
    let pm = req.package_manager.as_str();
    let engine = req.engine.as_str();

    let (program, args): (&str, Vec<&str>) = match (engine, pm, platform) {
        ("tesseract", "apt", OsPlatform::Linux) => (
            "sudo",
            vec!["apt", "install", "-y", "tesseract-ocr", "tesseract-ocr-chi-sim", "tesseract-ocr-eng", "poppler-utils"],
        ),
        ("tesseract", "brew", _) => (
            "brew",
            vec!["install", "tesseract", "tesseract-lang", "poppler"],
        ),
        ("tesseract", "choco", OsPlatform::Windows) => (
            "choco",
            vec!["install", "tesseract", "-y"],
        ),
        ("tesseract", "winget", OsPlatform::Windows) => (
            "winget",
            vec!["install", "--accept-source-agreements", "--accept-package-agreements", "UB-Mannheim.TesseractOCR"],
        ),
        ("paddleocr", "pip", _) => (
            "pip3",
            vec!["install", "paddleocr", "paddlepaddle"],
        ),
        _ => {
            return Ok(Json(OcrInstallResponse {
                success: false,
                engine: engine.into(),
                package_manager: pm.into(),
                output: String::new(),
                message: format!("不支持的安装组合: engine={}, pm={}, platform={}", engine, pm, platform),
            }));
        }
    };

    tracing::info!(engine, package_manager = pm, %platform, "Starting OCR install");

    let result = tokio::process::Command::new(program)
        .args(&args)
        .output()
        .await;

    match result {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            let combined = format!("{}\n{}", stdout, stderr).trim().to_string();
            let lower = combined.to_lowercase();

            let already_installed = lower.contains("no available upgrade")
                || lower.contains("already installed")
                || lower.contains("找不到可用的升级")
                || lower.contains("已安装");
            let success = output.status.success() || already_installed;

            if success {
                tracing::info!(engine, already_installed, "OCR install completed successfully");
            } else {
                tracing::warn!(engine, exit_code = ?output.status.code(), "OCR install failed");
            }

            let message = if already_installed {
                format!("{} 已安装（最新版本），无需更新。", engine)
            } else if success {
                format!("{} 安装成功！请刷新页面确认状态。", engine)
            } else {
                format!("{} 安装失败，请查看输出日志或手动安装。", engine)
            };

            Ok(Json(OcrInstallResponse {
                success,
                engine: engine.into(),
                package_manager: pm.into(),
                output: combined,
                message,
            }))
        }
        Err(e) => Ok(Json(OcrInstallResponse {
            success: false,
            engine: engine.into(),
            package_manager: pm.into(),
            output: e.to_string(),
            message: format!("执行安装命令失败: {}。请检查 {} 是否已正确安装。", e, pm),
        })),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_platform() {
        let p = detect_platform();
        if cfg!(target_os = "macos") {
            assert_eq!(p, OsPlatform::MacOs);
        } else if cfg!(target_os = "windows") {
            assert_eq!(p, OsPlatform::Windows);
        } else {
            assert_eq!(p, OsPlatform::Linux);
        }
    }

    #[test]
    fn test_os_platform_display() {
        assert_eq!(OsPlatform::Linux.to_string(), "linux");
        assert_eq!(OsPlatform::MacOs.to_string(), "macos");
        assert_eq!(OsPlatform::Windows.to_string(), "windows");
    }

    #[test]
    fn test_package_manager_display() {
        assert_eq!(PackageManager::Apt.to_string(), "apt");
        assert_eq!(PackageManager::Brew.to_string(), "brew");
        assert_eq!(PackageManager::Choco.to_string(), "choco");
        assert_eq!(PackageManager::Winget.to_string(), "winget");
        assert_eq!(PackageManager::Pip.to_string(), "pip");
        assert_eq!(PackageManager::None.to_string(), "none");
    }

    #[tokio::test]
    async fn test_detect_package_managers() {
        let managers = detect_package_managers().await;
        // Should not contain duplicates
        let mut deduped = managers.clone();
        deduped.dedup();
        assert_eq!(managers.len(), deduped.len());
    }

    #[test]
    fn test_ocr_install_request_deser() {
        let json = r#"{"engine":"tesseract","package_manager":"apt"}"#;
        let req: OcrInstallRequest = serde_json::from_str(json).unwrap();
        assert_eq!(req.engine, "tesseract");
        assert_eq!(req.package_manager, "apt");
    }

    #[test]
    fn test_ocr_install_options_serialization() {
        let opts = OcrInstallOptions {
            platform: OsPlatform::Linux,
            available_package_managers: vec![PackageManager::Apt, PackageManager::Pip],
            methods: vec![InstallMethod {
                package_manager: PackageManager::Apt,
                engine: "tesseract".into(),
                command: "sudo apt install -y tesseract-ocr".into(),
                needs_sudo: true,
                description: "Install via apt".into(),
            }],
            recommended: Some("tesseract".into()),
        };
        let json = serde_json::to_value(&opts).unwrap();
        assert_eq!(json["platform"], "linux");
        assert!(json["methods"].is_array());
        assert_eq!(json["methods"][0]["engine"], "tesseract");
        assert_eq!(json["methods"][0]["needs_sudo"], true);
        assert_eq!(json["recommended"], "tesseract");
    }
}
