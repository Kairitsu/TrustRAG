use std::collections::HashMap;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Instant;

use serde::{Deserialize, Serialize};
use tokio::process::{Child, Command};
use tokio::sync::Mutex;

pub const MAX_LOG_LINES: usize = 1000;
pub const STALL_THRESHOLD_SECS: u64 = 60;
pub const INSTALL_TIMEOUT_SECS: u64 = 600;

pub type OcrTaskStore = Arc<Mutex<HashMap<String, OcrInstallTask>>>;
pub type OcrChildStore = Arc<Mutex<HashMap<String, Arc<Mutex<Option<Child>>>>>>;

pub fn new_task_store() -> OcrTaskStore {
    Arc::new(Mutex::new(HashMap::new()))
}

pub fn new_child_store() -> OcrChildStore {
    Arc::new(Mutex::new(HashMap::new()))
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OcrInstallMethod {
    Choco,
    Apt,
    Brew,
    Winget,
    Pip,
    Manual,
    CustomPath,
    Portable,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OcrTaskStatus {
    Pending,
    Running,
    WaitingForUac,
    ElevationCancelled,
    Cancelling,
    Cancelled,
    CancelFailed,
    Success,
    Failed,
    Timeout,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OcrInstallStage {
    DetectingEnvironment,
    WaitingForUac,
    CheckingChocolatey,
    ExecutingInstall,
    WaitingForOutput,
    VerifyingTesseract,
    VerifyingLanguages,
    VerifyingPoppler,
    RefreshingConfig,
    Done,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OcrVerificationItem {
    pub name: String,
    pub passed: bool,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OcrVerificationResult {
    pub all_passed: bool,
    pub items: Vec<OcrVerificationItem>,
    pub path_refresh_needed: bool,
    pub partial_tesseract: bool,
    pub partial_poppler: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OcrTaskStatusFile {
    pub task_id: String,
    pub status: OcrTaskStatus,
    pub stage: OcrInstallStage,
    pub started_at: String,
    pub ended_at: Option<String>,
    pub command: String,
    pub elevated: bool,
    pub pid: Option<u32>,
    pub exit_code: Option<i32>,
    pub error_message: Option<String>,
    pub verification_result: Option<OcrVerificationResult>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OcrConfig {
    pub tesseract_path: Option<String>,
    pub tessdata_dir: Option<String>,
    pub poppler_bin_dir: Option<String>,
    pub default_language: String,
    pub ocr_enabled: bool,
    pub prefer_custom_paths: bool,
    pub allow_auto_install: bool,
    #[serde(default)]
    pub portable_runtime_dir: Option<String>,
}

impl Default for OcrConfig {
    fn default() -> Self {
        Self {
            tesseract_path: None,
            tessdata_dir: None,
            poppler_bin_dir: None,
            default_language: "eng+chi_sim".into(),
            ocr_enabled: true,
            prefer_custom_paths: false,
            allow_auto_install: true,
            portable_runtime_dir: None,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct OcrInstallTask {
    pub task_id: String,
    pub engine: String,
    pub install_method: OcrInstallMethod,
    pub status: OcrTaskStatus,
    pub stage: OcrInstallStage,
    pub requires_admin: bool,
    pub is_elevated: bool,
    pub command: String,
    pub started_at: String,
    pub finished_at: Option<String>,
    pub duration_ms: Option<u64>,
    pub exit_code: Option<i32>,
    pub log_lines: Vec<String>,
    pub message: Option<String>,
    pub error_message: Option<String>,
    pub pid: Option<u32>,
    pub log_file: Option<String>,
    pub status_file: Option<String>,
    pub cancel_flag_file: Option<String>,
    pub logs_dir: Option<String>,
    pub last_output_at: Option<String>,
    pub stall_warning: bool,
    pub suggestions: Vec<String>,
    pub verification: Option<OcrVerificationResult>,
    pub residual_pids: Vec<u32>,
    pub residual_command_lines: Vec<String>,
    #[serde(skip)]
    pub windows_helper_log: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct OcrPreflightItem {
    pub name: String,
    pub display_name: String,
    pub passed: bool,
    pub detail: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub suggestion: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct OcrPreflightResponse {
    pub items: Vec<OcrPreflightItem>,
    pub is_admin: bool,
    pub os_name: String,
    pub os_arch: String,
    pub path_preview: String,
    pub logs_dir: String,
    pub latest_install_log: Option<String>,
    pub trustrag_version: String,
    pub ocr_config: OcrConfig,
    pub overall_status: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct OcrOverallStatus {
    pub status: String,
    pub tesseract_path: Option<String>,
    pub poppler_path: Option<String>,
    pub tessdata_dir: Option<String>,
    pub pdf_ocr_ready: bool,
    pub any_available: bool,
    pub recommendation: String,
}

pub fn data_dir() -> PathBuf {
    crate::config::AppConfig::load()
        .map(|c| PathBuf::from(c.data_dir))
        .unwrap_or_else(|_| PathBuf::from("."))
}

pub fn ocr_config_path() -> PathBuf {
    data_dir().join("ocr-config.json")
}

pub fn load_ocr_config() -> OcrConfig {
    let path = ocr_config_path();
    if path.exists() {
        if let Ok(content) = std::fs::read_to_string(&path) {
            if let Ok(cfg) = serde_json::from_str(&content) {
                return cfg;
            }
        }
    }
    OcrConfig::default()
}

pub fn save_ocr_config(config: &OcrConfig) -> std::io::Result<()> {
    let path = ocr_config_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(config).unwrap_or_default();
    std::fs::write(path, json)
}

pub fn install_logs_dir() -> PathBuf {
    data_dir().join("logs").join("ocr-install")
}

pub fn task_log_path(task_id: &str) -> PathBuf {
    install_logs_dir().join(format!("{task_id}.log"))
}

pub fn task_status_path(task_id: &str) -> PathBuf {
    install_logs_dir().join(format!("{task_id}.status.json"))
}

pub fn task_cancel_flag_path(task_id: &str) -> PathBuf {
    install_logs_dir().join(format!("{task_id}.cancel"))
}

pub fn write_latest_task_pointer(task_id: &str) {
    let dir = install_logs_dir();
    let _ = std::fs::create_dir_all(&dir);
    let _ = std::fs::write(dir.join("latest-task.txt"), task_id);
}

pub fn read_latest_task_id() -> Option<String> {
    let pointer = install_logs_dir().join("latest-task.txt");
    std::fs::read_to_string(pointer)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

pub fn read_latest_log_path() -> Option<String> {
    if let Some(task_id) = read_latest_task_id() {
        let path = task_log_path(&task_id);
        if path.exists() {
            return Some(path.display().to_string());
        }
    }
    None
}

fn append_to_log_file(path: &Path, line: &str) {
    if let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        let _ = writeln!(file, "{line}");
    }
}

pub fn push_log_line(task: &mut OcrInstallTask, line: String, log_file: Option<&Path>) {
    task.last_output_at = Some(chrono::Utc::now().to_rfc3339());
    task.stall_warning = false;
    if let Some(path) = log_file {
        append_to_log_file(path, &line);
    }
    task.log_lines.push(line);
    if task.log_lines.len() > MAX_LOG_LINES {
        let overflow = task.log_lines.len() - MAX_LOG_LINES;
        task.log_lines.drain(0..overflow);
        task.log_lines.insert(
            0,
            format!("... ({overflow} earlier log lines truncated) ..."),
        );
    }
}

pub fn write_task_status_file(task: &OcrInstallTask) {
    let Some(status_file) = task.status_file.as_ref() else {
        return;
    };
    let status = OcrTaskStatusFile {
        task_id: task.task_id.clone(),
        status: task.status.clone(),
        stage: task.stage.clone(),
        started_at: task.started_at.clone(),
        ended_at: task.finished_at.clone(),
        command: task.command.clone(),
        elevated: task.is_elevated,
        pid: task.pid,
        exit_code: task.exit_code,
        error_message: task.error_message.clone(),
        verification_result: task.verification.clone(),
    };
    if let Ok(json) = serde_json::to_string_pretty(&status) {
        let _ = std::fs::write(status_file, json);
    }
}

pub async fn is_running_as_admin() -> bool {
    #[cfg(unix)]
    {
        unsafe { libc::geteuid() == 0 }
    }
    #[cfg(windows)]
    {
        Command::new("powershell")
            .args([
                "-NoProfile",
                "-Command",
                "([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)",
            ])
            .output()
            .await
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().eq_ignore_ascii_case("true"))
            .unwrap_or(false)
    }
    #[cfg(not(any(unix, windows)))]
    {
        false
    }
}

pub fn os_version_string() -> String {
    format!("{} {}", std::env::consts::OS, std::env::consts::ARCH)
}

async fn command_exists(cmd: &str) -> bool {
    which::which(cmd).is_ok()
}

async fn resolve_binary_path(cmd: &str) -> Option<String> {
    which::which(cmd).ok().map(|p| p.display().to_string())
}

async fn check_command_at(path: &str, args: &[&str]) -> (bool, String) {
    match Command::new(path).args(args).output().await {
        Ok(output) => {
            let text = format!(
                "{}\n{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
            let first = text
                .lines()
                .find(|l| !l.trim().is_empty())
                .unwrap_or("")
                .trim()
                .to_string();
            (output.status.success(), first)
        }
        Err(e) => (false, e.to_string()),
    }
}

async fn check_command_version(cmd: &str, args: &[&str]) -> (bool, String) {
    check_command_at(cmd, args).await
}

fn path_contains_dir(path_var: &str, dir: &str) -> bool {
    let dir_norm = dir.replace('\\', "/").to_lowercase();
    path_var
        .split(if cfg!(windows) { ';' } else { ':' })
        .any(|p| {
            let p_norm = p.replace('\\', "/").to_lowercase();
            p_norm == dir_norm || p_norm.starts_with(&format!("{dir_norm}/"))
        })
}

async fn detect_choco_processes() -> (bool, String) {
    #[cfg(windows)]
    {
        match Command::new("powershell")
            .args([
                "-NoProfile",
                "-Command",
                "Get-Process choco -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id",
            ])
            .output()
            .await
        {
            Ok(output) => {
                let pids: Vec<String> = String::from_utf8_lossy(&output.stdout)
                    .lines()
                    .map(|l| l.trim().to_string())
                    .filter(|l| !l.is_empty())
                    .collect();
                if pids.is_empty() {
                    (true, "无其他 choco 进程".into())
                } else {
                    (false, format!("检测到 choco 进程 PID: {}", pids.join(", ")))
                }
            }
            Err(e) => (true, format!("无法检测 choco 进程: {e}")),
        }
    }
    #[cfg(not(windows))]
    {
        let _ = ();
        (true, "非 Windows 平台".into())
    }
}

fn default_tesseract_search_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    #[cfg(windows)]
    {
        paths.push(PathBuf::from(r"C:\Program Files\Tesseract-OCR\tesseract.exe"));
        paths.push(PathBuf::from(r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe"));
    }
    #[cfg(target_os = "macos")]
    {
        paths.push(PathBuf::from("/usr/local/bin/tesseract"));
        paths.push(PathBuf::from("/opt/homebrew/bin/tesseract"));
    }
    #[cfg(target_os = "linux")]
    {
        paths.push(PathBuf::from("/usr/bin/tesseract"));
    }
    paths
}

fn default_poppler_search_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    #[cfg(windows)]
    {
        for base in [
            r"C:\Program Files\poppler\bin",
            r"C:\ProgramData\chocolatey\lib\poppler\tools\bin",
        ] {
            paths.push(PathBuf::from(base));
        }
    }
    #[cfg(target_os = "macos")]
    {
        paths.push(PathBuf::from("/usr/local/bin"));
        paths.push(PathBuf::from("/opt/homebrew/bin"));
    }
    #[cfg(target_os = "linux")]
    {
        paths.push(PathBuf::from("/usr/bin"));
    }
    paths
}

pub fn resolve_tesseract_executable(config: &OcrConfig) -> Option<String> {
    if config.prefer_custom_paths {
        if let Some(ref p) = config.tesseract_path {
            if Path::new(p).exists() {
                return Some(p.clone());
            }
        }
    }
    if let Ok(path) = which::which("tesseract") {
        return Some(path.display().to_string());
    }
    for p in default_tesseract_search_paths() {
        if p.exists() {
            return Some(p.display().to_string());
        }
    }
    config.tesseract_path.clone().filter(|p| Path::new(p).exists())
}

pub fn resolve_poppler_bin_dir(config: &OcrConfig) -> Option<String> {
    if config.prefer_custom_paths {
        if let Some(ref p) = config.poppler_bin_dir {
            if Path::new(p).is_dir() {
                return Some(p.clone());
            }
        }
    }
    for dir in default_poppler_search_paths() {
        let pdftoppm = dir.join(if cfg!(windows) { "pdftoppm.exe" } else { "pdftoppm" });
        if pdftoppm.exists() {
            return Some(dir.display().to_string());
        }
    }
    if let Ok(p) = which::which("pdftoppm") {
        if let Some(parent) = p.parent() {
            return Some(parent.display().to_string());
        }
    }
    config
        .poppler_bin_dir
        .clone()
        .filter(|p| Path::new(p).is_dir())
}

pub fn resolve_tessdata_dir(config: &OcrConfig) -> Option<String> {
    if let Some(ref p) = config.tessdata_dir {
        if Path::new(p).is_dir() {
            return Some(p.clone());
        }
    }
    std::env::var("TESSDATA_PREFIX").ok().filter(|s| !s.is_empty())
}

pub async fn run_comprehensive_preflight() -> OcrPreflightResponse {
    let config = load_ocr_config();
    let is_admin = is_running_as_admin().await;
    let path_preview = std::env::var("PATH").unwrap_or_default();
    let path_short = if path_preview.len() > 300 {
        format!("{}...", &path_preview[..300])
    } else {
        path_preview.clone()
    };

    let mut items = Vec::new();

    items.push(OcrPreflightItem {
        name: "os".into(),
        display_name: "操作系统".into(),
        passed: true,
        detail: os_version_string(),
        suggestion: None,
    });

    items.push(OcrPreflightItem {
        name: "admin".into(),
        display_name: "管理员权限".into(),
        passed: is_admin,
        detail: if is_admin {
            "当前进程以管理员权限运行".into()
        } else {
            "当前进程非管理员（自动安装需 UAC 提权）".into()
        },
        suggestion: if is_admin {
            None
        } else {
            Some("自动安装将弹出 UAC 确认窗口；也可使用手动路径配置绕过".into())
        },
    });

    let choco_path = resolve_binary_path("choco").await;
    let choco_ok = choco_path.is_some();
    let (choco_usable, choco_ver) = if let Some(ref p) = choco_path {
        check_command_at(p, &["--version"]).await
    } else {
        (false, String::new())
    };
    items.push(OcrPreflightItem {
        name: "choco".into(),
        display_name: "Chocolatey 已安装".into(),
        passed: choco_ok,
        detail: if let Some(p) = choco_path {
            format!("路径: {p}")
        } else {
            "未在 PATH 中找到 choco".into()
        },
        suggestion: if choco_ok {
            None
        } else {
            Some("请安装 Chocolatey: https://chocolatey.org/install 或使用手动安装/自定义路径".into())
        },
    });
    items.push(OcrPreflightItem {
        name: "choco_version".into(),
        display_name: "Chocolatey 版本".into(),
        passed: choco_usable,
        detail: if choco_usable {
            choco_ver.clone()
        } else if choco_ok {
            "choco 存在但执行失败".into()
        } else {
            "不可用".into()
        },
        suggestion: None,
    });

    let (choco_proc_ok, choco_proc_detail) = detect_choco_processes().await;
    items.push(OcrPreflightItem {
        name: "choco_lock".into(),
        display_name: "Chocolatey 进程锁".into(),
        passed: choco_proc_ok,
        detail: choco_proc_detail,
        suggestion: if choco_proc_ok {
            None
        } else {
            Some("请等待其他 choco 安装完成或结束相关进程后重试".into())
        },
    });

    let tess_exe = resolve_tesseract_executable(&config);
    let tess_exe_display = tess_exe.clone();
    let (tess_ok, tess_detail) = if let Some(ref p) = tess_exe {
        check_command_at(p, &["--version"]).await
    } else {
        (false, "未找到 tesseract.exe".into())
    };
    items.push(OcrPreflightItem {
        name: "tesseract".into(),
        display_name: "tesseract.exe".into(),
        passed: tess_ok,
        detail: if let Some(p) = tess_exe_display {
            format!("{p} — {tess_detail}")
        } else {
            "PATH 及常见目录均未找到 tesseract".into()
        },
        suggestion: if tess_ok {
            None
        } else {
            Some("请安装 Tesseract 或在下方配置自定义路径".into())
        },
    });

    if let Some(ref p) = tess_exe {
        if let Ok(output) = Command::new(p).args(["--list-langs"]).output().await {
            let langs: Vec<String> = String::from_utf8_lossy(&output.stdout)
                .lines()
                .skip(1)
                .map(|l| l.trim().to_string())
                .filter(|l| !l.is_empty())
                .collect();
            for (lang, label) in [("eng", "eng 语言包"), ("chi_sim", "chi_sim 语言包")] {
                let has = langs.iter().any(|l| l == lang);
                items.push(OcrPreflightItem {
                    name: lang.into(),
                    display_name: label.into(),
                    passed: has,
                    detail: if has {
                        format!("已安装 {lang}")
                    } else {
                        format!("未检测到 {lang}")
                    },
                    suggestion: if has {
                        None
                    } else {
                        Some(format!("请安装 Tesseract {lang} 语言包"))
                    },
                });
            }
        }
    }

    let tessdata = resolve_tessdata_dir(&config);
    let tessdata_env = std::env::var("TESSDATA_PREFIX").unwrap_or_default();
    items.push(OcrPreflightItem {
        name: "tessdata_prefix".into(),
        display_name: "TESSDATA_PREFIX".into(),
        passed: !tessdata_env.is_empty() || tessdata.is_some(),
        detail: if !tessdata_env.is_empty() {
            format!("环境变量: {tessdata_env}")
        } else {
            "未设置 TESSDATA_PREFIX".into()
        },
        suggestion: None,
    });
    items.push(OcrPreflightItem {
        name: "tessdata_dir".into(),
        display_name: "tessdata 目录".into(),
        passed: tessdata.is_some(),
        detail: tessdata
            .clone()
            .unwrap_or_else(|| "未检测到 tessdata 目录".into()),
        suggestion: if tessdata.is_some() {
            None
        } else {
            Some("可在配置中指定 tessdata 目录".into())
        },
    });

    let poppler_bin = resolve_poppler_bin_dir(&config);
    let pdftoppm_path = poppler_bin.as_ref().map(|d| {
        PathBuf::from(d).join(if cfg!(windows) { "pdftoppm.exe" } else { "pdftoppm" })
    });
    let pdfinfo_path = poppler_bin.as_ref().map(|d| {
        PathBuf::from(d).join(if cfg!(windows) { "pdfinfo.exe" } else { "pdfinfo" })
    });

    let (pdftoppm_ok, pdftoppm_detail) = if let Some(ref p) = pdftoppm_path {
        if p.exists() {
            check_command_at(p.to_str().unwrap_or("pdftoppm"), &["-v"]).await
        } else {
            (false, "pdftoppm 不存在".into())
        }
    } else {
        check_command_version("pdftoppm", &["-v"]).await
    };
    items.push(OcrPreflightItem {
        name: "pdftoppm".into(),
        display_name: "pdftoppm.exe (Poppler)".into(),
        passed: pdftoppm_ok,
        detail: if pdftoppm_ok {
            format!(
                "{} — {}",
                pdftoppm_path
                    .as_ref()
                    .map(|p| p.display().to_string())
                    .unwrap_or_else(|| "PATH".into()),
                pdftoppm_detail
            )
        } else {
            "未找到 pdftoppm".into()
        },
        suggestion: if pdftoppm_ok {
            None
        } else {
            Some("请安装 Poppler 或配置 poppler bin 目录".into())
        },
    });

    let (pdfinfo_ok, pdfinfo_detail) = if let Some(ref p) = pdfinfo_path {
        if p.exists() {
            check_command_at(p.to_str().unwrap_or("pdfinfo"), &["-v"]).await
        } else {
            (false, "pdfinfo 不存在".into())
        }
    } else {
        check_command_version("pdfinfo", &["-v"]).await
    };
    items.push(OcrPreflightItem {
        name: "pdfinfo".into(),
        display_name: "pdfinfo.exe (Poppler)".into(),
        passed: pdfinfo_ok,
        detail: if pdfinfo_ok {
            format!(
                "{} — {}",
                pdfinfo_path
                    .as_ref()
                    .map(|p| p.display().to_string())
                    .unwrap_or_else(|| "PATH".into()),
                pdfinfo_detail
            )
        } else {
            "未找到 pdfinfo".into()
        },
        suggestion: if pdfinfo_ok {
            None
        } else {
            Some("Poppler 安装后通常与 pdftoppm 同目录".into())
        },
    });

    if let Some(ref bin) = poppler_bin {
        items.push(OcrPreflightItem {
            name: "poppler_bin".into(),
            display_name: "Poppler bin 路径".into(),
            passed: true,
            detail: bin.clone(),
            suggestion: None,
        });
    }

    let path_has_tesseract = tess_exe
        .as_ref()
        .map(|p| path_contains_dir(&path_preview, Path::new(p).parent().unwrap_or(Path::new(p)).to_str().unwrap_or("")))
        .unwrap_or(false);
    items.push(OcrPreflightItem {
        name: "path_tesseract".into(),
        display_name: "PATH 包含 Tesseract".into(),
        passed: path_has_tesseract || tess_ok,
        detail: if path_has_tesseract {
            "PATH 中包含 Tesseract 目录".into()
        } else if tess_ok {
            "Tesseract 可用但可能不在 PATH（使用绝对路径）".into()
        } else {
            "PATH 中未包含 Tesseract".into()
        },
        suggestion: if path_has_tesseract || tess_ok {
            None
        } else {
            Some("安装后若 PATH 未刷新，请重启 TrustRAG 或手动配置路径".into())
        },
    });

    let path_has_poppler = poppler_bin
        .as_ref()
        .map(|d| path_contains_dir(&path_preview, d))
        .unwrap_or(false);
    items.push(OcrPreflightItem {
        name: "path_poppler".into(),
        display_name: "PATH 包含 Poppler".into(),
        passed: path_has_poppler || pdftoppm_ok,
        detail: if path_has_poppler {
            "PATH 中包含 Poppler bin".into()
        } else if pdftoppm_ok {
            "Poppler 可用但可能不在 PATH".into()
        } else {
            "PATH 中未包含 Poppler".into()
        },
        suggestion: None,
    });

    items.push(OcrPreflightItem {
        name: "trustrag_tesseract_config".into(),
        display_name: "TrustRAG Tesseract 配置".into(),
        passed: config.tesseract_path.is_some(),
        detail: config
            .tesseract_path
            .clone()
            .unwrap_or_else(|| "未配置（使用自动检测）".into()),
        suggestion: None,
    });
    items.push(OcrPreflightItem {
        name: "trustrag_poppler_config".into(),
        display_name: "TrustRAG Poppler 配置".into(),
        passed: config.poppler_bin_dir.is_some(),
        detail: config
            .poppler_bin_dir
            .clone()
            .unwrap_or_else(|| "未配置（使用自动检测）".into()),
        suggestion: None,
    });

    items.push(OcrPreflightItem {
        name: "latest_install_log".into(),
        display_name: "最近安装日志".into(),
        passed: read_latest_log_path().is_some(),
        detail: read_latest_log_path()
            .unwrap_or_else(|| "无历史安装日志".into()),
        suggestion: None,
    });

    let network_ok = tokio::time::timeout(
        std::time::Duration::from_secs(5),
        reqwest::Client::new()
            .get("https://community.chocolatey.org/api/v2/")
            .send(),
    )
    .await
    .map(|r| r.map(|resp| resp.status().is_success()).unwrap_or(false))
    .unwrap_or(false);
    items.push(OcrPreflightItem {
        name: "network".into(),
        display_name: "Chocolatey 包源网络".into(),
        passed: network_ok,
        detail: if network_ok {
            "可访问 Chocolatey 包源".into()
        } else {
            "无法访问 Chocolatey 包源".into()
        },
        suggestion: if network_ok {
            None
        } else {
            Some("请检查网络、代理或防火墙".into())
        },
    });

    let overall = compute_overall_status(&config).await;

    OcrPreflightResponse {
        items,
        is_admin,
        os_name: std::env::consts::OS.into(),
        os_arch: std::env::consts::ARCH.into(),
        path_preview: path_short,
        logs_dir: install_logs_dir().display().to_string(),
        latest_install_log: read_latest_log_path(),
        trustrag_version: env!("CARGO_PKG_VERSION").to_string(),
        ocr_config: config,
        overall_status: overall.status.clone(),
    }
}

pub async fn compute_overall_status(config: &OcrConfig) -> OcrOverallStatus {
    let tess_path = resolve_tesseract_executable(config);
    let poppler_path = resolve_poppler_bin_dir(config);
    let tessdata = resolve_tessdata_dir(config);

    let tess_ok = if let Some(ref p) = tess_path {
        check_command_at(p, &["--version"]).await.0
    } else {
        false
    };
    let pdftoppm_ok = if let Some(ref bin) = poppler_path {
        let exe = PathBuf::from(bin).join(if cfg!(windows) { "pdftoppm.exe" } else { "pdftoppm" });
        if exe.exists() {
            check_command_at(exe.to_str().unwrap_or("pdftoppm"), &["-v"]).await.0
        } else {
            false
        }
    } else {
        check_command_version("pdftoppm", &["-v"]).await.0
    };

    let any_available = tess_ok || command_exists("paddleocr").await;
    let pdf_ocr_ready = tess_ok && pdftoppm_ok;

    let status: String = if pdf_ocr_ready {
        "available".into()
    } else if tess_ok && !pdftoppm_ok {
        "partial_tesseract".into()
    } else if !tess_ok && pdftoppm_ok {
        "partial_poppler".into()
    } else if any_available {
        "partial".into()
    } else if config.tesseract_path.is_some() || config.poppler_bin_dir.is_some() {
        "config_error".into()
    } else {
        "not_installed".into()
    };

    let recommendation: String = match status.as_str() {
        "available" => "OCR 组件已就绪，可处理扫描版 PDF。".into(),
        "partial_tesseract" => "Tesseract 已就绪，请安装或配置 Poppler (pdftoppm)。".into(),
        "partial_poppler" => "Poppler 已就绪，请安装或配置 Tesseract。".into(),
        "config_error" => "已配置自定义路径但验证失败，请检查路径是否正确。".into(),
        "partial" => "OCR 部分可用，请补全缺失依赖。".into(),
        _ => "未检测到 OCR 组件。可选择自动安装、手动安装或配置已有路径。".into(),
    };

    OcrOverallStatus {
        status,
        tesseract_path: tess_path,
        poppler_path: poppler_path,
        tessdata_dir: tessdata,
        pdf_ocr_ready,
        any_available,
        recommendation,
    }
}

pub async fn verify_installation(engine: &str) -> OcrVerificationResult {
    let config = load_ocr_config();
    verify_with_config(engine, &config).await
}

pub async fn verify_with_config(engine: &str, config: &OcrConfig) -> OcrVerificationResult {
    let mut items = Vec::new();

    if engine == "paddleocr" {
        let (ok, detail) = check_command_version(
            "python3",
            &["-c", "import paddleocr; print(paddleocr.VERSION)"],
        )
        .await;
        items.push(OcrVerificationItem {
            name: "paddleocr".into(),
            passed: ok,
            detail,
        });
        return OcrVerificationResult {
            all_passed: ok,
            items,
            path_refresh_needed: !ok,
            partial_tesseract: false,
            partial_poppler: false,
        };
    }

    let tess_path = resolve_tesseract_executable(config);
    let poppler_bin = resolve_poppler_bin_dir(config);

    let (tess_ok, tess_ver) = if let Some(ref p) = tess_path {
        check_command_at(p, &["--version"]).await
    } else {
        (false, "未找到 tesseract".into())
    };
    items.push(OcrVerificationItem {
        name: "tesseract --version".into(),
        passed: tess_ok,
        detail: tess_ver,
    });

    let mut langs_ok = false;
    let mut langs_detail = "无法执行 tesseract --list-langs".into();
    if let Some(ref p) = tess_path {
        let mut cmd = Command::new(p);
        cmd.args(["--list-langs"]);
        if let Some(ref td) = resolve_tessdata_dir(config) {
            cmd.env("TESSDATA_PREFIX", td);
        }
        if let Ok(output) = cmd.output().await {
            let langs: Vec<String> = String::from_utf8_lossy(&output.stdout)
                .lines()
                .skip(1)
                .map(|l| l.trim().to_string())
                .filter(|l| !l.is_empty())
                .collect();
            let has_eng = langs.iter().any(|l| l == "eng");
            langs_ok = output.status.success() && has_eng;
            langs_detail = format!("语言包: {}", langs.join(", "));
        }
    }
    items.push(OcrVerificationItem {
        name: "tesseract --list-langs".into(),
        passed: langs_ok,
        detail: langs_detail,
    });

    let pdftoppm_exe = poppler_bin.as_ref().map(|d| {
        PathBuf::from(d).join(if cfg!(windows) { "pdftoppm.exe" } else { "pdftoppm" })
    });
    let (pdftoppm_ok, pdftoppm_ver) = if let Some(ref p) = pdftoppm_exe {
        if p.exists() {
            check_command_at(p.to_str().unwrap_or("pdftoppm"), &["-v"]).await
        } else {
            (false, "pdftoppm 不存在".into())
        }
    } else {
        check_command_version("pdftoppm", &["-v"]).await
    };
    items.push(OcrVerificationItem {
        name: "pdftoppm -v".into(),
        passed: pdftoppm_ok,
        detail: pdftoppm_ver,
    });

    let pdfinfo_exe = poppler_bin.as_ref().map(|d| {
        PathBuf::from(d).join(if cfg!(windows) { "pdfinfo.exe" } else { "pdfinfo" })
    });
    let (pdfinfo_ok, pdfinfo_ver) = if let Some(ref p) = pdfinfo_exe {
        if p.exists() {
            check_command_at(p.to_str().unwrap_or("pdfinfo"), &["-v"]).await
        } else {
            (false, "pdfinfo 不存在".into())
        }
    } else {
        check_command_version("pdfinfo", &["-v"]).await
    };
    items.push(OcrVerificationItem {
        name: "pdfinfo -v".into(),
        passed: pdfinfo_ok,
        detail: pdfinfo_ver,
    });

    let all_passed = tess_ok && langs_ok && pdftoppm_ok && pdfinfo_ok;
    OcrVerificationResult {
        all_passed,
        items,
        path_refresh_needed: (tess_ok || pdftoppm_ok) && !all_passed,
        partial_tesseract: tess_ok && !pdftoppm_ok,
        partial_poppler: !tess_ok && pdftoppm_ok,
    }
}

pub fn analyze_failure_suggestions(log: &str, exit_code: Option<i32>, pm: &str) -> Vec<String> {
    let lower = log.to_lowercase();
    let mut suggestions = Vec::new();

    if exit_code == Some(1223) {
        suggestions.push("用户取消了 UAC 管理员授权。可以「以管理员身份运行 TrustRAG」或使用手动安装。".into());
    }
    if lower.contains("choco") && (lower.contains("not recognized") || lower.contains("not found")) {
        suggestions.push("未安装 Chocolatey。请访问 https://chocolatey.org/install 或改用手动路径配置。".into());
    }
    if lower.contains("access is denied") || lower.contains("permission") || lower.contains("elevation") {
        suggestions.push("权限不足。请以管理员身份运行 TrustRAG 或手动以管理员执行安装命令。".into());
    }
    if lower.contains("being used by another process") || lower.contains("lock") || lower.contains("mutex") {
        suggestions.push("Chocolatey 可能被其他安装占用。请等待其他 choco 进程结束。".into());
    }
    if lower.contains("unable to connect") || lower.contains("network") || lower.contains("could not download") {
        suggestions.push("网络或包源访问失败。请检查网络、代理设置。".into());
    }
    if lower.contains("path") && lower.contains("not found") {
        suggestions.push("PATH 未生效。请重启 TrustRAG 或手动配置 Tesseract/Poppler 路径。".into());
    }
    if lower.contains("chi_sim") || lower.contains("language") || lower.contains("tessdata") {
        suggestions.push("Tesseract 语言包缺失。请安装 chi_sim / eng 语言包。".into());
    }
    if lower.contains("pdftoppm") || lower.contains("poppler") {
        suggestions.push("Poppler 未正确安装。请配置 Poppler bin 目录。".into());
    }
    if exit_code == Some(1) && pm == "choco" && suggestions.is_empty() {
        suggestions.push("Chocolatey 安装返回错误。请展开日志查看详细原因。".into());
    }
    suggestions
}

pub async fn kill_process_tree(pid: u32) -> bool {
    #[cfg(windows)]
    {
        Command::new("taskkill")
            .args(["/PID", &pid.to_string(), "/T", "/F"])
            .output()
            .await
            .map(|o| o.status.success())
            .unwrap_or(false)
    }
    #[cfg(unix)]
    {
        unsafe {
            libc::kill(pid as i32, libc::SIGTERM);
        }
        true
    }
}

#[cfg(windows)]
pub fn write_windows_elevated_install_script(
    task_id: &str,
    log_file: &Path,
    status_file: &Path,
    cancel_file: &Path,
    program: &str,
    args: &[String],
) -> std::io::Result<PathBuf> {
    let dir = install_logs_dir();
    std::fs::create_dir_all(&dir)?;
    let script_path = dir.join(format!("install_{task_id}.ps1"));

    let arg_str = args
        .iter()
        .map(|a| format!("'{}'", a.replace('\'', "''")))
        .collect::<Vec<_>>()
        .join(", ");

    let script = format!(
        r#"$ErrorActionPreference = 'Continue'
$logFile = '{}'
$statusFile = '{}'
$cancelFile = '{}'
function Update-Status($status, $stage, $exitCode, $err) {{
  $obj = @{{
    task_id = '{}'
    status = $status
    stage = $stage
    elevated = $true
    exit_code = $exitCode
    error_message = $err
    ended_at = (Get-Date).ToUniversalTime().ToString('o')
  }} | ConvertTo-Json
  Set-Content -Path $statusFile -Value $obj -Encoding UTF8
}}
Update-Status 'running' 'executing_install' $null $null
"@[info] Elevated installer started" | Out-File -FilePath $logFile -Encoding UTF8
$argList = @({})
$proc = Start-Process -FilePath '{}' -ArgumentList $argList -NoNewWindow -PassThru -RedirectStandardOutput ($logFile + '.stdout') -RedirectStandardError ($logFile + '.stderr')
while (-not $proc.HasExited) {{
  if (Test-Path $cancelFile) {{
    "@[info] Cancel flag detected, stopping..." | Out-File -FilePath $logFile -Append -Encoding UTF8
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Update-Status 'cancelled' 'done' 130 'User cancelled'
    exit 130
  }}
  Start-Sleep -Milliseconds 500
}}
if (Test-Path ($logFile + '.stdout')) {{ Get-Content ($logFile + '.stdout') | Out-File -FilePath $logFile -Append -Encoding UTF8 }}
if (Test-Path ($logFile + '.stderr')) {{ Get-Content ($logFile + '.stderr') | Out-File -FilePath $logFile -Append -Encoding UTF8 }}
$code = $proc.ExitCode
"@[info] Exit code: $code" | Out-File -FilePath $logFile -Append -Encoding UTF8
if ($code -eq 0) {{ Update-Status 'success' 'done' $code $null }}
else {{ Update-Status 'failed' 'done' $code "Install failed with exit code $code" }}
exit $code
"#,
        log_file.display().to_string().replace('\'', "''"),
        status_file.display().to_string().replace('\'', "''"),
        cancel_file.display().to_string().replace('\'', "''"),
        task_id,
        arg_str,
        program.replace('\'', "''"),
    );

    std::fs::write(&script_path, script)?;
    Ok(script_path)
}

#[cfg(windows)]
pub fn build_uac_launcher(script_path: &Path) -> (String, Vec<String>) {
    let script = script_path.display().to_string().replace('\'', "''");
    let ps = format!(
        "$p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','{script}') -Verb RunAs -Wait -PassThru; exit $p.ExitCode"
    );
    (
        "powershell".into(),
        vec![
            "-NoProfile".into(),
            "-ExecutionPolicy".into(),
            "Bypass".into(),
            "-Command".into(),
            ps,
        ],
    )
}

fn read_file_from_offset(path: &Path, offset: u64) -> std::io::Result<(String, u64)> {
    let mut file = std::fs::File::open(path)?;
    file.seek(SeekFrom::Start(offset))?;
    let mut buf = String::new();
    file.read_to_string(&mut buf)?;
    let new_offset = offset + buf.len() as u64;
    Ok((buf, new_offset))
}

async fn ingest_log_chunk(
    store: &OcrTaskStore,
    tid: &str,
    chunk: &str,
    prefix: &str,
    persist_log: Option<&Path>,
) {
    if chunk.is_empty() {
        return;
    }
    let mut tasks = store.lock().await;
    if let Some(t) = tasks.get_mut(tid) {
        for line in chunk.lines() {
            if line.trim().is_empty() {
                continue;
            }
            let tagged = if prefix.is_empty() {
                line.to_string()
            } else {
                format!("{prefix} {line}")
            };
            push_log_line(t, tagged, persist_log);
        }
        write_task_status_file(t);
    }
}

pub async fn poll_log_file(
    store: OcrTaskStore,
    tid: String,
    log_path: String,
    mut file_pos: u64,
) {
    loop {
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;

        let (should_stop, persist_log) = {
            let tasks = store.lock().await;
            let stop = tasks
                .get(&tid)
                .map(|t| {
                    !matches!(
                        t.status,
                        OcrTaskStatus::Running
                            | OcrTaskStatus::WaitingForUac
                            | OcrTaskStatus::Cancelling
                    )
                })
                .unwrap_or(true);
            let persist = tasks
                .get(&tid)
                .and_then(|t| t.log_file.clone())
                .map(PathBuf::from);
            (stop, persist)
        };

        let persist_ref = persist_log.as_deref();
        if let Ok((chunk, new_pos)) = read_file_from_offset(Path::new(&log_path), file_pos) {
            file_pos = new_pos;
            ingest_log_chunk(&store, &tid, &chunk, "", persist_ref).await;
        }

        update_stall_warning(&store, &tid).await;
        sync_status_from_file(&store, &tid).await;

        if should_stop {
            break;
        }
    }

    let persist_log = {
        let tasks = store.lock().await;
        tasks
            .get(&tid)
            .and_then(|t| t.log_file.clone())
            .map(PathBuf::from)
    };
    if let Ok((chunk, _)) = read_file_from_offset(Path::new(&log_path), file_pos) {
        ingest_log_chunk(&store, &tid, &chunk, "", persist_log.as_deref()).await;
    }
}

async fn sync_status_from_file(store: &OcrTaskStore, tid: &str) {
    let status_path = {
        let tasks = store.lock().await;
        tasks.get(tid).and_then(|t| t.status_file.clone())
    };
    let Some(path) = status_path else { return };
    if let Ok(content) = std::fs::read_to_string(&path) {
        if let Ok(file_status) = serde_json::from_str::<OcrTaskStatusFile>(&content) {
            let mut tasks = store.lock().await;
            if let Some(t) = tasks.get_mut(tid) {
                if file_status.status != OcrTaskStatus::Running || t.is_elevated {
                    t.status = file_status.status.clone();
                    t.stage = file_status.stage.clone();
                    t.exit_code = file_status.exit_code;
                    t.error_message = file_status.error_message.clone();
                    if file_status.ended_at.is_some() {
                        t.finished_at = file_status.ended_at.clone();
                    }
                }
            }
        }
    }
}

pub async fn update_stall_warning(store: &OcrTaskStore, tid: &str) {
    let mut tasks = store.lock().await;
    if let Some(t) = tasks.get_mut(tid) {
        if !matches!(
            t.status,
            OcrTaskStatus::Running | OcrTaskStatus::WaitingForUac
        ) {
            return;
        }
        if let Some(ref last) = t.last_output_at {
            if let Ok(last_dt) = chrono::DateTime::parse_from_rfc3339(last) {
                let elapsed =
                    chrono::Utc::now().signed_duration_since(last_dt.with_timezone(&chrono::Utc));
                if elapsed.num_seconds() >= STALL_THRESHOLD_SECS as i64 {
                    t.stall_warning = true;
                }
            }
        }
    }
}

pub fn write_install_log_header(path: &Path, preflight: &OcrPreflightResponse, command: &str) {
    let header = format!(
        "=== TrustRAG OCR Install Log ===\n\
         TrustRAG version: {}\n\
         OS: {} {}\n\
         Admin: {}\n\
         PATH: {}\n\
         Logs dir: {}\n\
         Command: {}\n\
         --- Preflight ---\n{}\n\
         --- Output ---\n",
        preflight.trustrag_version,
        preflight.os_name,
        preflight.os_arch,
        preflight.is_admin,
        preflight.path_preview,
        preflight.logs_dir,
        command,
        preflight
            .items
            .iter()
            .map(|i| format!(
                "[{}] {} — {} ({})",
                if i.passed { "OK" } else { "FAIL" },
                i.display_name,
                i.detail,
                i.suggestion.as_deref().unwrap_or("")
            ))
            .collect::<Vec<_>>()
            .join("\n"),
    );
    let _ = std::fs::write(path, header);
}

pub async fn perform_async_cancel(
    store: OcrTaskStore,
    children_store: OcrChildStore,
    task_id: String,
) {
    let (pid, cancel_flag, log_file) = {
        let tasks = store.lock().await;
        let t = match tasks.get(&task_id) {
            Some(t) => t,
            None => return,
        };
        (
            t.pid,
            t.cancel_flag_file.clone(),
            t.log_file.clone(),
        )
    };

    if let Some(ref flag) = cancel_flag {
        let _ = std::fs::write(flag, "cancel");
    }

    let mut killed = false;
    if let Some(p) = pid {
        killed = kill_process_tree(p).await;
    }

    if let Some(slot) = children_store.lock().await.get(&task_id).cloned() {
        let mut guard = slot.lock().await;
        if let Some(mut child) = guard.take() {
            let _ = child.kill().await;
            killed = true;
        }
    }

    let mut tasks = store.lock().await;
    if let Some(t) = tasks.get_mut(&task_id) {
        let log_path_buf = t.log_file.clone();
        let log_path = log_path_buf.as_deref().map(Path::new);
        if killed {
            t.status = OcrTaskStatus::Cancelled;
            t.stage = OcrInstallStage::Done;
            t.message = Some("安装已被用户取消。".into());
            push_log_line(t, "[info] 安装进程已终止".into(), log_path);
        } else {
            t.status = OcrTaskStatus::CancelFailed;
            t.message = Some("无法终止安装进程（可能是 elevated 进程）。请使用任务管理器手动结束。".into());
            if let Some(p) = pid {
                t.residual_pids.push(p);
                t.residual_command_lines
                    .push(format!("taskkill /PID {p} /T /F"));
            }
            t.suggestions.push(format!(
                "取消失败。残留 PID: {:?}。可手动执行: {}",
                t.residual_pids,
                t.residual_command_lines.join("; ")
            ));
            push_log_line(
                t,
                "[error] 取消失败，可能需要管理员权限终止 elevated 进程".into(),
                log_path,
            );
        }
        t.finished_at = Some(chrono::Utc::now().to_rfc3339());
        write_task_status_file(t);
    }

    children_store.lock().await.remove(&task_id);
    let _ = log_file;
}

pub fn read_task_logs(task_id: &str, since_line: usize) -> (Vec<String>, usize) {
    let path = task_log_path(task_id);
    if path.exists() {
        if let Ok(content) = std::fs::read_to_string(&path) {
            let lines: Vec<String> = content.lines().map(String::from).collect();
            let total = lines.len();
            let new_lines = if since_line < total {
                lines[since_line..].to_vec()
            } else {
                vec![]
            };
            return (new_lines, total);
        }
    }
    (vec![], 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_push_log_line_truncates_at_max() {
        let mut task = OcrInstallTask {
            task_id: "t".into(),
            engine: "tesseract".into(),
            install_method: OcrInstallMethod::Choco,
            status: OcrTaskStatus::Running,
            stage: OcrInstallStage::ExecutingInstall,
            requires_admin: true,
            is_elevated: false,
            command: "choco install".into(),
            started_at: chrono::Utc::now().to_rfc3339(),
            finished_at: None,
            duration_ms: None,
            exit_code: None,
            log_lines: vec![],
            message: None,
            error_message: None,
            pid: None,
            log_file: None,
            status_file: None,
            cancel_flag_file: None,
            logs_dir: None,
            last_output_at: None,
            stall_warning: false,
            suggestions: vec![],
            verification: None,
            residual_pids: vec![],
            residual_command_lines: vec![],
            windows_helper_log: None,
        };
        for i in 0..1100 {
            push_log_line(&mut task, format!("line {i}"), None);
        }
        assert!(task.log_lines.len() <= MAX_LOG_LINES + 1);
    }

    #[test]
    fn test_analyze_failure_uac_cancelled() {
        let suggestions = analyze_failure_suggestions("", Some(1223), "choco");
        assert!(suggestions.iter().any(|s| s.contains("UAC")));
    }

    #[test]
    fn test_analyze_failure_choco_not_found() {
        let suggestions = analyze_failure_suggestions(
            "choco is not recognized as an internal command",
            Some(1),
            "choco",
        );
        assert!(suggestions.iter().any(|s| s.contains("Chocolatey")));
    }

    #[test]
    fn test_read_file_from_offset_incremental() {
        let dir = std::env::temp_dir().join(format!("ocr_log_test_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("out.log");
        std::fs::write(&path, "line1\nline2\n").unwrap();

        let (chunk1, pos1) = read_file_from_offset(&path, 0).unwrap();
        assert_eq!(chunk1, "line1\nline2\n");

        std::fs::write(&path, "line1\nline2\nline3\n").unwrap();
        let (chunk2, pos2) = read_file_from_offset(&path, pos1).unwrap();
        assert_eq!(chunk2, "line3\n");
        assert!(pos2 > pos1);

        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn test_ocr_config_default() {
        let cfg = OcrConfig::default();
        assert!(cfg.ocr_enabled);
        assert_eq!(cfg.default_language, "eng+chi_sim");
    }

    #[tokio::test]
    async fn test_comprehensive_preflight_has_required_items() {
        let preflight = run_comprehensive_preflight().await;
        let names: Vec<_> = preflight.items.iter().map(|i| i.name.as_str()).collect();
        assert!(names.contains(&"os"));
        assert!(names.contains(&"admin"));
        assert!(names.contains(&"choco"));
        assert!(names.contains(&"tesseract"));
        assert!(names.contains(&"pdftoppm"));
        assert!(names.contains(&"pdfinfo"));
        assert!(names.contains(&"network"));
        assert!(names.contains(&"path_tesseract"));
        assert!(names.contains(&"latest_install_log"));
    }

    #[test]
    fn test_task_paths() {
        let tid = "abc-123";
        assert!(task_log_path(tid).to_string_lossy().contains("ocr-install"));
        assert!(task_status_path(tid).to_string_lossy().ends_with(".status.json"));
        assert!(task_cancel_flag_path(tid).to_string_lossy().ends_with(".cancel"));
    }
}