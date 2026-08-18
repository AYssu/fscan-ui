mod handlers;

use futures_util::{SinkExt, StreamExt};
use log::{error, info, warn, debug};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::broadcast;
use tokio_tungstenite::accept_async;

/// 消息类型
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum MessageType {
    Heartbeat,
    HeartbeatAck,
    Command,
    Response,
    Stream,
    Error,
}

/// WebSocket 消息
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct WsMessage {
    #[serde(rename = "type")]
    pub msg_type: MessageType,
    pub id: Option<String>,
    pub data: Option<serde_json::Value>,
}

impl WsMessage {
    pub fn heartbeat() -> Self {
        Self {
            msg_type: MessageType::Heartbeat,
            id: None,
            data: None,
        }
    }

    pub fn heartbeat_ack() -> Self {
        Self {
            msg_type: MessageType::HeartbeatAck,
            id: None,
            data: Some(serde_json::json!({
                "timestamp": std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs(),
            })),
        }
    }

    pub fn response(id: Option<String>, data: serde_json::Value) -> Self {
        Self {
            msg_type: MessageType::Response,
            id,
            data: Some(data),
        }
    }

    pub fn error(id: Option<String>, message: &str) -> Self {
        Self {
            msg_type: MessageType::Error,
            id,
            data: Some(serde_json::json!({ "message": message })),
        }
    }

    pub fn stream(id: Option<String>, line: &str) -> Self {
        Self {
            msg_type: MessageType::Stream,
            id,
            data: Some(serde_json::json!({ "line": line })),
        }
    }

    pub fn encode(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }

    pub fn decode(s: &str) -> Option<Self> {
        serde_json::from_str(s).ok()
    }
}

/// 命令执行器枚举
enum CommandHandler {
    Ping,
    Status,
    Login,
    GetApps,
    GetAppInfo,
    GetModules,
    GetNextFile,
    GetFiles,
    StartScan,
    ReaderTest,
    Compare,
    CompareNorm,
    ToOut,
    FilterListTargets,
    CheckFileExists,
    KamiInfo,
    Trace,
}

impl CommandHandler {
    async fn execute(&self, id: Option<String>, params: Option<&serde_json::Value>) -> WsMessage {
        match self {
            Self::Ping => {
                info!("  ├─ Processing: ping");
                WsMessage::response(id, serde_json::json!({ "pong": true }))
            }
            Self::Status => {
                info!("  ├─ Processing: status");
                WsMessage::response(
                    id,
                    serde_json::json!({
                        "status": "running",
                        "version": "1.0.0",
                        "uptime": std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_secs(),
                    }),
                )
            }
            Self::Login => {
                let account = params
                    .and_then(|p| p.get("account"))
                    .and_then(|a| a.as_str())
                    .unwrap_or("");
                let password = params
                    .and_then(|p| p.get("password"))
                    .and_then(|p| p.as_str())
                    .unwrap_or("");

                info!("  ├─ Processing: login account={}", account);

                if account == "2997036064" && !password.is_empty() {
                    info!("  ├─ Login success");
                    WsMessage::response(
                        id,
                        serde_json::json!({
                            "success": true,
                            "account": account,
                            "email": format!("{}@qq.com", account),
                            "expireTime": "2027-12-31T23:59:59",
                            "nickname": "FScan用户",
                        }),
                    )
                } else {
                    info!("  ├─ Login failed: invalid credentials");
                    WsMessage::error(id, "账号或密码错误")
                }
            }
            Self::GetApps => {
                info!("  ├─ Processing: get_apps");
                match handlers::get_running_apps() {
                    Ok(apps) => {
                        let apps_json: Vec<_> = apps
                            .iter()
                            .map(|app| {
                                serde_json::json!({
                                    "packageName": app.package_name,
                                    "pid": app.pid,
                                    "arch": app.arch
                                })
                            })
                            .collect();
                        WsMessage::response(
                            id,
                            serde_json::json!({
                                "success": true,
                                "apps": apps_json,
                                "count": apps.len()
                            }),
                        )
                    }
                    Err(e) => {
                        info!("  ├─ Get apps failed: {}", e);
                        WsMessage::error(id, &format!("Failed to get apps: {}", e))
                    }
                }
            }
            Self::GetAppInfo => {
                let package_name = params
                    .and_then(|p| p.get("packageName"))
                    .and_then(|p| p.as_str())
                    .unwrap_or("");

                info!("  ├─ Processing: get_app_info package={}", package_name);

                match handlers::get_app_info(package_name) {
                    Ok(app_info) => {
                        WsMessage::response(
                            id,
                            serde_json::json!({
                                "success": true,
                                "packageName": app_info.package_name,
                                "pid": app_info.pid,
                                "arch": app_info.arch
                            }),
                        )
                    }
                    Err(e) => {
                        info!("  ├─ Get app info failed: {}", e);
                        WsMessage::error(id, &format!("Failed to get app info: {}", e))
                    }
                }
            }
            Self::GetNextFile => {
                let dir = params
                    .and_then(|p| p.get("dir"))
                    .and_then(|d| d.as_str())
                    .unwrap_or("/sdcard/fscan");
                let extension = params
                    .and_then(|p| p.get("extension"))
                    .and_then(|e| e.as_str())
                    .unwrap_or("out");

                info!("  ├─ Processing: get_next_file dir={} ext={}", dir, extension);

                match handlers::get_next_file_path(dir, extension) {
                    Ok(path) => {
                        WsMessage::response(
                            id,
                            serde_json::json!({
                                "success": true,
                                "path": path
                            }),
                        )
                    }
                    Err(e) => {
                        info!("  ├─ Get next file failed: {}", e);
                        WsMessage::error(id, &format!("Failed to get next file: {}", e))
                    }
                }
            }
            Self::GetFiles => {
                let dir = params
                    .and_then(|p| p.get("dir"))
                    .and_then(|d| d.as_str())
                    .unwrap_or("/sdcard/fscan");
                let extensions = params
                    .and_then(|p| p.get("extensions"))
                    .and_then(|e| e.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| v.as_str().map(String::from))
                            .collect::<Vec<String>>()
                    })
                    .unwrap_or_else(|| vec!["out".to_string()]);

                info!("  ├─ Processing: get_files dir={} exts={:?}", dir, extensions);

                match handlers::get_files_in_dir(dir, &extensions) {
                    Ok(files) => {
                        WsMessage::response(
                            id,
                            serde_json::json!({
                                "success": true,
                                "files": files
                            }),
                        )
                    }
                    Err(e) => {
                        info!("  ├─ Get files failed: {}", e);
                        WsMessage::error(id, &format!("Failed to get files: {}", e))
                    }
                }
            }
            Self::GetModules => {
                let package_name = params
                    .and_then(|p| p.get("packageName"))
                    .and_then(|p| p.as_str())
                    .unwrap_or("");

                info!("  ├─ Processing: get_modules package={}", package_name);

                match handlers::get_process_modules(package_name) {
                    Ok(modules) => {
                        let modules_json: Vec<_> = modules
                            .iter()
                            .map(|m| {
                                serde_json::json!({
                                    "name": m.name,
                                    "index": m.index,
                                    "type": m.mem_type,
                                    "startAddress": m.start_address,
                                    "endAddress": m.end_address
                                })
                            })
                            .collect();
                        WsMessage::response(
                            id,
                            serde_json::json!({
                                "success": true,
                                "packageName": package_name,
                                "modules": modules_json
                            }),
                        )
                    }
                    Err(e) => {
                        info!("  ├─ Get modules failed: {}", e);
                        WsMessage::error(id, &format!("Failed to get modules: {}", e))
                    }
                }
            }
            Self::StartScan => {
                // StartScan 在 Service::handle_message 中特殊处理
                WsMessage::error(id, "StartScan should be handled by Service")
            }
            Self::ReaderTest => {
                let reader_type = params
                    .and_then(|p| p.get("reader"))
                    .and_then(|r| r.as_str())
                    .unwrap_or("");

                info!("  ├─ Processing: reader-test reader={}", reader_type);

                match handlers::reader_test(reader_type) {
                    Ok(output) => {
                        WsMessage::response(
                            id,
                            serde_json::json!({
                                "success": true,
                                "output": output
                            }),
                        )
                    }
                    Err(e) => {
                        info!("  ├─ Reader test failed: {}", e);
                        WsMessage::error(id, &format!("Reader test failed: {}", e))
                    }
                }
            }
            Self::Compare => {
                // Compare 在 Service::handle_message 中特殊处理
                WsMessage::error(id, "Compare should be handled by Service")
            }
            Self::CompareNorm => {
                // CompareNorm 在 Service::handle_message 中特殊处理
                WsMessage::error(id, "CompareNorm should be handled by Service")
            }
            Self::ToOut => {
                // ToOut 在 Service::handle_message 中特殊处理
                WsMessage::error(id, "ToOut should be handled by Service")
            }
            Self::FilterListTargets => {
                let input = params
                    .and_then(|p| p.get("input"))
                    .and_then(|i| i.as_str())
                    .unwrap_or("");
                let mode = params
                    .and_then(|p| p.get("mode"))
                    .and_then(|m| m.as_str())
                    .unwrap_or("bin");
                let bit = params
                    .and_then(|p| p.get("bit"))
                    .and_then(|b| b.as_i64())
                    .unwrap_or(64) as i32;
                let value_type = params
                    .and_then(|p| p.get("valueType"))
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0) as i32;
                let pid = params
                    .and_then(|p| p.get("pid"))
                    .and_then(|p| p.as_i64())
                    .unwrap_or(0) as i32;
                let reader = params
                    .and_then(|p| p.get("reader"))
                    .and_then(|r| r.as_str());
                let kami_key = params
                    .and_then(|p| p.get("kamiKey"))
                    .and_then(|k| k.as_str());

                info!("  ├─ Processing: filter_list_targets input={} mode={} bit={} pid={}", input, mode, bit, pid);

                match handlers::filter_list_targets(input, mode, bit, value_type, pid, reader, kami_key) {
                    Ok(result) => {
                        WsMessage::response(id, result)
                    }
                    Err(e) => {
                        info!("  ├─ Filter list targets failed: {}", e);
                        WsMessage::error(id, &format!("Filter list targets failed: {}", e))
                    }
                }
            }
            Self::Trace => {
                let package = params
                    .and_then(|p| p.get("packageName"))
                    .and_then(|p| p.as_str());
                let pid = params
                    .and_then(|p| p.get("pid"))
                    .and_then(|p| p.as_i64())
                    .unwrap_or(0) as i32;
                let bit = params
                    .and_then(|p| p.get("bit"))
                    .and_then(|b| b.as_i64())
                    .unwrap_or(64) as i32;
                let chains: Vec<String> = params
                    .and_then(|p| p.get("chains"))
                    .and_then(|c| c.as_array())
                    .map(|arr| arr.iter().filter_map(|v| v.as_str().map(String::from)).collect())
                    .unwrap_or_default();
                let reader = params
                    .and_then(|p| p.get("reader"))
                    .and_then(|r| r.as_str());
                let kami_key = params
                    .and_then(|p| p.get("kamiKey"))
                    .and_then(|k| k.as_str());

                info!("  ├─ Processing: trace chains={} bit={}", chains.len(), bit);

                let binary = handlers::get_scan_binary();
                let mut cmd = std::process::Command::new(&binary);
                cmd.arg("trace");

                if let Some(pkg) = package {
                    if !pkg.is_empty() {
                        cmd.arg("-p").arg(pkg);
                    }
                }
                if pid > 0 {
                    cmd.arg("--pid").arg(pid.to_string());
                }
                cmd.arg("-b").arg(bit.to_string());
                for chain in &chains {
                    cmd.arg("-c").arg(chain);
                }
                if let Some(r) = reader {
                    if !r.is_empty() {
                        cmd.arg("--reader").arg(r);
                    }
                }
                if let Some(k) = kami_key {
                    if !k.is_empty() {
                        cmd.arg("-k").arg(k);
                    }
                }

                match cmd.stdout(std::process::Stdio::piped())
                    .stderr(std::process::Stdio::piped())
                    .output()
                {
                    Ok(output) => {
                        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
                        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
                        info!("  ├─ Trace output: {} bytes", stdout.len());
                        if !stderr.is_empty() {
                            info!("  ├─ Trace stderr: {}", stderr);
                        }
                        match serde_json::from_str::<serde_json::Value>(&stdout) {
                            Ok(json) => WsMessage::response(id, json),
                            Err(e) => {
                                info!("  ├─ Trace parse failed: {}", e);
                                WsMessage::error(id, &format!("解析trace输出失败: {}", e))
                            }
                        }
                    }
                    Err(e) => {
                        info!("  ├─ Trace failed: {}", e);
                        WsMessage::error(id, &format!("trace执行失败: {}", e))
                    }
                }
            }
            Self::CheckFileExists => {
                let path = params
                    .and_then(|p| p.get("path"))
                    .and_then(|p| p.as_str())
                    .unwrap_or("");

                info!("  ├─ Processing: check_file_exists path={}", path);

                match handlers::check_file_exists(path) {
                    Ok(exists) => {
                        WsMessage::response(
                            id,
                            serde_json::json!({
                                "success": true,
                                "exists": exists
                            }),
                        )
                    }
                    Err(e) => {
                        info!("  ├─ Check file exists failed: {}", e);
                        WsMessage::error(id, &format!("Check file exists failed: {}", e))
                    }
                }
            }
            Self::KamiInfo => {
                let kami_key = params
                    .and_then(|p| p.get("kamiKey"))
                    .and_then(|k| k.as_str())
                    .unwrap_or("");

                info!("  ├─ Processing: kami_info key={}", kami_key);

                if kami_key.is_empty() {
                    return WsMessage::error(id, "卡密不能为空");
                }

                let binary = handlers::get_scan_binary();

                match tokio::process::Command::new(&binary)
                    .arg("kami-info")
                    .arg("-k")
                    .arg(kami_key)
                    .stdout(std::process::Stdio::piped())
                    .stderr(std::process::Stdio::piped())
                    .output()
                    .await
                {
                    Ok(output) => {
                        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
                        info!("  ├─ Kami info output: {}", stdout);

                        // 尝试解析JSON输出
                        match serde_json::from_str::<serde_json::Value>(&stdout) {
                            Ok(json) => WsMessage::response(id, json),
                            Err(_) => {
                                // 如果不是JSON，包装成带输出的响应
                                WsMessage::response(
                                    id,
                                    serde_json::json!({
                                        "success": true,
                                        "output": stdout.trim()
                                    }),
                                )
                            }
                        }
                    }
                    Err(e) => {
                        info!("  ├─ Kami info failed: {}", e);
                        WsMessage::error(id, &format!("查询卡密信息失败: {}", e))
                    }
                }
            }
        }
    }
}

/// 服务核心 - 命令执行器
pub struct Service {
    handlers: HashMap<String, CommandHandler>,
    /// 扫描输出广播通道
    scan_output_tx: broadcast::Sender<String>,
}

impl Service {
    pub fn new() -> Self {
        let mut handlers: HashMap<String, CommandHandler> = HashMap::new();

        // 注册所有命令处理器
        handlers.insert("ping".to_string(), CommandHandler::Ping);
        handlers.insert("status".to_string(), CommandHandler::Status);
        handlers.insert("login".to_string(), CommandHandler::Login);
        handlers.insert("get_apps".to_string(), CommandHandler::GetApps);
        handlers.insert("get_app_info".to_string(), CommandHandler::GetAppInfo);
        handlers.insert("get_modules".to_string(), CommandHandler::GetModules);
        handlers.insert("get_next_file".to_string(), CommandHandler::GetNextFile);
        handlers.insert("get_files".to_string(), CommandHandler::GetFiles);
        handlers.insert("start_scan".to_string(), CommandHandler::StartScan);
        handlers.insert("compare".to_string(), CommandHandler::Compare);
        handlers.insert("compare_norm".to_string(), CommandHandler::CompareNorm);
        handlers.insert("to_out".to_string(), CommandHandler::ToOut);
        handlers.insert("reader_test".to_string(), CommandHandler::ReaderTest);
        handlers.insert("filter_list_targets".to_string(), CommandHandler::FilterListTargets);
        handlers.insert("check_file_exists".to_string(), CommandHandler::CheckFileExists);
        handlers.insert("kami_info".to_string(), CommandHandler::KamiInfo);
        handlers.insert("trace".to_string(), CommandHandler::Trace);

        // 创建扫描输出广播通道
        let (scan_output_tx, _) = broadcast::channel(1000);

        Self {
            handlers,
            scan_output_tx,
        }
    }

    pub fn get_scan_output_rx(&self) -> broadcast::Receiver<String> {
        self.scan_output_tx.subscribe()
    }

    pub async fn handle_message(&self, msg: WsMessage, _broadcast_tx: broadcast::Sender<String>) -> Option<WsMessage> {
        match msg.msg_type {
            MessageType::Heartbeat => {
                debug!("♥ Heartbeat received, sending ack");
                Some(WsMessage::heartbeat_ack())
            }
            MessageType::Command => {
                let command = msg
                    .data
                    .as_ref()
                    .and_then(|d| d.get("command"))
                    .and_then(|c| c.as_str())
                    .unwrap_or("unknown");

                let params = msg.data.as_ref().and_then(|d| d.get("params"));

                info!("⚡ Command: {}", command);

                // 特殊处理start_scan命令
                if command == "start_scan" {
                    let task_id = uuid::Uuid::new_v4().to_string();
                    info!("  ├─ Starting scan task: {}", task_id);

                    // 立即返回任务ID
                    let response = WsMessage::response(
                        msg.id.clone(),
                        serde_json::json!({
                            "success": true,
                            "taskId": task_id,
                            "message": "扫描任务已启动"
                        }),
                    );

                    // 启动后台扫描任务
                    let scan_tx = self.scan_output_tx.clone();
                    let params = params.cloned().unwrap_or(serde_json::json!({}));
                    let task_id_clone = task_id.clone();

                    tokio::spawn(async move {
                        Self::run_scan_task(task_id_clone, params, scan_tx).await;
                    });

                    return Some(response);
                }

                // 特殊处理compare命令
                if command == "compare" {
                    let task_id = uuid::Uuid::new_v4().to_string();
                    info!("  ├─ Starting compare task: {}", task_id);

                    // 立即返回任务ID
                    let response = WsMessage::response(
                        msg.id.clone(),
                        serde_json::json!({
                            "success": true,
                            "taskId": task_id,
                            "message": "对比任务已启动"
                        }),
                    );

                    // 启动后台对比任务
                    let scan_tx = self.scan_output_tx.clone();
                    let params = params.cloned().unwrap_or(serde_json::json!({}));
                    let task_id_clone = task_id.clone();

                    tokio::spawn(async move {
                        Self::run_compare_task(task_id_clone, params, scan_tx).await;
                    });

                    return Some(response);
                }

                // 特殊处理compare_norm命令
                if command == "compare_norm" {
                    let task_id = uuid::Uuid::new_v4().to_string();
                    info!("  ├─ Starting compare-norm task: {}", task_id);

                    // 立即返回任务ID
                    let response = WsMessage::response(
                        msg.id.clone(),
                        serde_json::json!({
                            "success": true,
                            "taskId": task_id,
                            "message": "暴力对比任务已启动"
                        }),
                    );

                    // 启动后台对比任务
                    let scan_tx = self.scan_output_tx.clone();
                    let params = params.cloned().unwrap_or(serde_json::json!({}));
                    let task_id_clone = task_id.clone();

                    tokio::spawn(async move {
                        Self::run_compare_norm_task(task_id_clone, params, scan_tx).await;
                    });

                    return Some(response);
                }

                // 特殊处理to_out命令 - 直接执行并返回结果
                if command == "to_out" {
                    let params_val = params.cloned().unwrap_or(serde_json::json!({}));
                    info!("  ├─ Processing: to_out");

                    let result = Self::execute_to_out(&params_val).await;
                    return Some(WsMessage::response(msg.id.clone(), result));
                }

                // 特殊处理filter_run命令
                if command == "filter_run" {
                    let task_id = uuid::Uuid::new_v4().to_string();
                    info!("  ├─ Starting filter task: {}", task_id);

                    // 立即返回任务ID
                    let response = WsMessage::response(
                        msg.id.clone(),
                        serde_json::json!({
                            "success": true,
                            "taskId": task_id,
                            "message": "过滤任务已启动"
                        }),
                    );

                    // 启动后台过滤任务
                    let scan_tx = self.scan_output_tx.clone();
                    let params = params.cloned().unwrap_or(serde_json::json!({}));
                    let task_id_clone = task_id.clone();

                    tokio::spawn(async move {
                        Self::run_filter_task(task_id_clone, params, scan_tx).await;
                    });

                    return Some(response);
                }

                // 特殊处理convert_format命令
                if command == "convert_format" {
                    let task_id = uuid::Uuid::new_v4().to_string();
                    info!("  ├─ Starting convert_format task: {}", task_id);

                    // 计算输出路径
                    let params_val = params.cloned().unwrap_or(serde_json::json!({}));
                    let output_path = if let Some(o) = params_val.get("outputPath").and_then(|v| v.as_str()) {
                        o.to_string()
                    } else if let Some(input) = params_val.get("filePath").and_then(|v| v.as_str()) {
                        let folder = params_val.get("folder").and_then(|v| v.as_bool()).unwrap_or(false);
                        if folder {
                            // 文件夹模式：保持原文件名，不加后缀
                            input.to_string()
                        } else {
                            // 非文件夹模式：替换后缀为 .txt
                            if input.ends_with(".out") {
                                input.replace(".out", ".txt")
                            } else if input.ends_with(".bin") {
                                input.replace(".bin", ".txt")
                            } else {
                                format!("{}.txt", input)
                            }
                        }
                    } else {
                        String::new()
                    };

                    // 立即返回任务ID和输出路径
                    let response = WsMessage::response(
                        msg.id.clone(),
                        serde_json::json!({
                            "success": true,
                            "taskId": task_id,
                            "outputPath": output_path,
                            "message": "格式转换任务已启动"
                        }),
                    );

                    // 启动后台格式转换任务
                    let scan_tx = self.scan_output_tx.clone();
                    let task_id_clone = task_id.clone();

                    tokio::spawn(async move {
                        Self::run_convert_format_task(task_id_clone, params_val, scan_tx).await;
                    });

                    return Some(response);
                }

                if let Some(handler) = self.handlers.get(command) {
                    Some(handler.execute(msg.id.clone(), params).await)
                } else {
                    warn!("❓ Unknown command: {}", command);
                    Some(WsMessage::error(
                        msg.id.clone(),
                        &format!("Unknown command: {}", command),
                    ))
                }
            }
            _ => {
                warn!("❓ Unknown message type: {:?}", msg.msg_type);
                None
            }
        }
    }

    /// 运行扫描任务
    async fn run_scan_task(task_id: String, params: serde_json::Value, scan_tx: broadcast::Sender<String>) {
        use tokio::process::Command;
        use tokio::io::{AsyncBufReadExt, BufReader};

        let binary = handlers::get_scan_binary();

        // 构建命令参数
        let mut cmd = Command::new(&binary);
        cmd.arg("scan");

        if let Some(package) = params.get("packageName").and_then(|p| p.as_str()) {
            cmd.arg("-p").arg(package);
        } else if let Some(pid) = params.get("pid").and_then(|p| p.as_i64()) {
            cmd.arg("--pid").arg(pid.to_string());
        }

        if let Some(addrs) = params.get("addresses").and_then(|a| a.as_array()) {
            for addr in addrs {
                if let Some(addr_str) = addr.as_str() {
                    cmd.arg("-a").arg(addr_str);
                }
            }
        }

        if let Some(depth) = params.get("depth").and_then(|d| d.as_i64()) {
            cmd.arg("-d").arg(depth.to_string());
        }

        if let Some(offset) = params.get("offset").and_then(|o| o.as_i64()) {
            cmd.arg("-o").arg(offset.to_string());
        }

        if let Some(count) = params.get("count").and_then(|c| c.as_i64()) {
            cmd.arg("--count").arg(count.to_string());
        }

        if let Some(size) = params.get("size").and_then(|s| s.as_i64()) {
            cmd.arg("--size").arg(size.to_string());
        }

        if let Some(ranges) = params.get("ranges").and_then(|r| r.as_array()) {
            for range in ranges {
                if let Some(range_str) = range.as_str() {
                    cmd.arg("-r").arg(range_str);
                }
            }
        }

        if let Some(modules) = params.get("modules").and_then(|m| m.as_array()) {
            for module in modules {
                if let Some(module_str) = module.as_str() {
                    cmd.arg("-m").arg(module_str);
                }
            }
        }

        // 数据格式处理：通用格式用 -f，暴力格式用 --norm
        let is_brutal = params.get("brutalMode").and_then(|b| b.as_bool()).unwrap_or(false);
        if is_brutal {
            // 暴力格式：使用 --norm 参数输出归一化文件
            if let Some(norm_file) = params.get("normFile").and_then(|n| n.as_str()) {
                cmd.arg("--norm").arg(norm_file);
            }
        } else {
            // 通用格式：使用 -f 参数输出文件
            if let Some(outfile) = params.get("outputFile").and_then(|f| f.as_str()) {
                cmd.arg("-f").arg(outfile);
            }
        }

        if let Some(page_fault) = params.get("pageFault").and_then(|p| p.as_bool()) {
            if page_fault {
                cmd.arg("--page-fault");
            }
        }

        if let Some(byte_filter) = params.get("byteFilter").and_then(|b| b.as_bool()) {
            if byte_filter {
                cmd.arg("--byte-filter");
            }
        }

        if let Some(align_read) = params.get("alignRead").and_then(|b| b.as_bool()) {
            if align_read {
                cmd.arg("--align-read");
            }
        }

        if let Some(allow_negative) = params.get("allowNegative").and_then(|b| b.as_bool()) {
            if allow_negative {
                cmd.arg("--allow-negative");
            }
        }

        if let Some(allow_nonread) = params.get("allowNonread").and_then(|b| b.as_bool()) {
            if allow_nonread {
                cmd.arg("--allow-nonread");
            }
        }

        if let Some(reader) = params.get("reader").and_then(|r| r.as_str()) {
            cmd.arg("--reader").arg(reader);
        }

        // 卡密参数
        if let Some(kami_key) = params.get("kamiKey").and_then(|k| k.as_str()) {
            if !kami_key.is_empty() {
                cmd.arg("-k").arg(kami_key);
            }
        }

        info!("  ├─ Executing scan command");

        // 发送开始消息 - 包装成WsMessage格式
        let start_msg = WsMessage {
            msg_type: MessageType::Stream,
            id: Some(task_id.clone()),
            data: Some(serde_json::json!({
                "taskId": task_id,
                "type": "start",
                "message": "扫描开始"
            })),
        };
        let _ = scan_tx.send(start_msg.encode());

        // 执行命令并获取输出
        match cmd.stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).spawn() {
            Ok(mut child) => {
                let stdout = child.stdout.take().unwrap();
                let stderr = child.stderr.take().unwrap();

                // 读取stdout
                let stdout_task_id = task_id.clone();
                let stdout_tx = scan_tx.clone();
                let stdout_handle = tokio::spawn(async move {
                    let reader = BufReader::new(stdout);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        info!("  ├─ [stdout] {}", line);
                        let stream_msg = WsMessage {
                            msg_type: MessageType::Stream,
                            id: Some(stdout_task_id.clone()),
                            data: Some(serde_json::json!({
                                "taskId": stdout_task_id,
                                "type": "stdout",
                                "line": line
                            })),
                        };
                        let _ = stdout_tx.send(stream_msg.encode());
                    }
                    info!("  ├─ [stdout] 读取完成");
                });

                // 读取stderr
                let stderr_task_id = task_id.clone();
                let stderr_tx = scan_tx.clone();
                let stderr_handle = tokio::spawn(async move {
                    let reader = BufReader::new(stderr);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        info!("  ├─ [stderr] {}", line);
                        let stream_msg = WsMessage {
                            msg_type: MessageType::Stream,
                            id: Some(stderr_task_id.clone()),
                            data: Some(serde_json::json!({
                                "taskId": stderr_task_id,
                                "type": "stderr",
                                "line": line
                            })),
                        };
                        let _ = stderr_tx.send(stream_msg.encode());
                    }
                    info!("  ├─ [stderr] 读取完成");
                });

                // 等待任务完成
                info!("  ├─ 等待子进程完成...");
                let status = child.wait().await;
                info!("  ├─ 等待stdout读取完成...");
                let _ = stdout_handle.await;
                info!("  ├─ 等待stderr读取完成...");
                let _ = stderr_handle.await;
                info!("  ├─ 所有任务完成");

                // 发送完成消息 - 包装成WsMessage格式
                let exit_code = status.map(|s| s.code()).unwrap_or(None);
                let complete_msg = WsMessage {
                    msg_type: MessageType::Stream,
                    id: Some(task_id.clone()),
                    data: Some(serde_json::json!({
                        "taskId": task_id,
                        "type": "complete",
                        "exitCode": exit_code,
                        "success": exit_code == Some(0)
                    })),
                };
                info!("  ├─ 发送完成消息");
                let _ = scan_tx.send(complete_msg.encode());

                info!("  ├─ Scan task completed: {} exit_code={:?}", task_id, exit_code);
            }
            Err(e) => {
                error!("  ├─ Failed to start scan: {}", e);
                let error_msg = WsMessage {
                    msg_type: MessageType::Stream,
                    id: Some(task_id.clone()),
                    data: Some(serde_json::json!({
                        "taskId": task_id,
                        "type": "error",
                        "message": format!("启动扫描失败: {}", e)
                    })),
                };
                let _ = scan_tx.send(error_msg.encode());
            }
        }
    }

    /// 运行对比任务（基础对比/极速对比）
    async fn run_compare_task(task_id: String, params: serde_json::Value, scan_tx: broadcast::Sender<String>) {
        use tokio::process::Command;
        use tokio::io::{AsyncBufReadExt, BufReader};

        let binary = handlers::get_scan_binary();

        // 构建命令参数
        let mut cmd = Command::new(&binary);
        cmd.arg("compare");

        // 输入文件
        if let Some(files) = params.get("inputFiles").and_then(|f| f.as_array()) {
            for file in files {
                if let Some(file_str) = file.as_str() {
                    cmd.arg("-i").arg(file_str);
                }
            }
        }

        // 输出文件
        if let Some(output) = params.get("outputFile").and_then(|o| o.as_str()) {
            cmd.arg("-o").arg(output);
        }

        // 输出模式
        if let Some(mode) = params.get("mode").and_then(|m| m.as_str()) {
            cmd.arg("-m").arg(mode);
        }

        // 进程位数
        if let Some(bit) = params.get("bit").and_then(|b| b.as_i64()) {
            cmd.arg("-b").arg(bit.to_string());
        }

        // 限制数量
        if let Some(limit) = params.get("limit").and_then(|l| l.as_i64()) {
            cmd.arg("--limit").arg(limit.to_string());
        }

        // 层级限制
        if let Some(level_min) = params.get("levelMin").and_then(|l| l.as_i64()) {
            cmd.arg("--level-min").arg(level_min.to_string());
        }

        if let Some(level_max) = params.get("levelMax").and_then(|l| l.as_i64()) {
            cmd.arg("--level-max").arg(level_max.to_string());
        }

        // 卡密参数
        if let Some(kami_key) = params.get("kamiKey").and_then(|k| k.as_str()) {
            if !kami_key.is_empty() {
                cmd.arg("-k").arg(kami_key);
            }
        }

        info!("  ├─ Executing: {:?}", cmd);

        // 发送开始消息
        let start_msg = WsMessage {
            msg_type: MessageType::Stream,
            id: Some(task_id.clone()),
            data: Some(serde_json::json!({
                "taskId": task_id,
                "type": "start",
                "message": "对比开始"
            })),
        };
        let _ = scan_tx.send(start_msg.encode());

        // 执行命令并获取输出
        match cmd.stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).spawn() {
            Ok(mut child) => {
                let stdout = child.stdout.take().unwrap();
                let stderr = child.stderr.take().unwrap();

                // 读取stdout
                let stdout_task_id = task_id.clone();
                let stdout_tx = scan_tx.clone();
                let stdout_handle = tokio::spawn(async move {
                    let reader = BufReader::new(stdout);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        info!("  ├─ [stdout] {}", line);
                        let stream_msg = WsMessage {
                            msg_type: MessageType::Stream,
                            id: Some(stdout_task_id.clone()),
                            data: Some(serde_json::json!({
                                "taskId": stdout_task_id,
                                "type": "stdout",
                                "line": line
                            })),
                        };
                        let _ = stdout_tx.send(stream_msg.encode());
                    }
                    info!("  ├─ [stdout] 读取完成");
                });

                // 读取stderr
                let stderr_task_id = task_id.clone();
                let stderr_tx = scan_tx.clone();
                let stderr_handle = tokio::spawn(async move {
                    let reader = BufReader::new(stderr);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        info!("  ├─ [stderr] {}", line);
                        let stream_msg = WsMessage {
                            msg_type: MessageType::Stream,
                            id: Some(stderr_task_id.clone()),
                            data: Some(serde_json::json!({
                                "taskId": stderr_task_id,
                                "type": "stderr",
                                "line": line
                            })),
                        };
                        let _ = stderr_tx.send(stream_msg.encode());
                    }
                    info!("  ├─ [stderr] 读取完成");
                });

                // 等待任务完成
                info!("  ├─ 等待子进程完成...");
                let status = child.wait().await;
                info!("  ├─ 等待stdout读取完成...");
                let _ = stdout_handle.await;
                info!("  ├─ 等待stderr读取完成...");
                let _ = stderr_handle.await;
                info!("  ├─ 所有任务完成");

                // 发送完成消息
                let exit_code = status.map(|s| s.code()).unwrap_or(None);
                let complete_msg = WsMessage {
                    msg_type: MessageType::Stream,
                    id: Some(task_id.clone()),
                    data: Some(serde_json::json!({
                        "taskId": task_id,
                        "type": "complete",
                        "exitCode": exit_code,
                        "success": exit_code == Some(0)
                    })),
                };
                info!("  ├─ 发送完成消息");
                let _ = scan_tx.send(complete_msg.encode());

                info!("  ├─ Compare task completed: {} exit_code={:?}", task_id, exit_code);
            }
            Err(e) => {
                error!("  ├─ Failed to start compare: {}", e);
                let error_msg = WsMessage {
                    msg_type: MessageType::Stream,
                    id: Some(task_id.clone()),
                    data: Some(serde_json::json!({
                        "taskId": task_id,
                        "type": "error",
                        "message": format!("启动对比失败: {}", e)
                    })),
                };
                let _ = scan_tx.send(error_msg.encode());
            }
        }
    }

    /// 运行暴力对比任务（compare-norm）
    async fn run_compare_norm_task(task_id: String, params: serde_json::Value, scan_tx: broadcast::Sender<String>) {
        use tokio::process::Command;
        use tokio::io::{AsyncBufReadExt, BufReader};

        let binary = handlers::get_scan_binary();

        // 构建命令参数
        let mut cmd = Command::new(&binary);
        cmd.arg("compare-norm");

        // 输入文件
        if let Some(files) = params.get("inputFiles").and_then(|f| f.as_array()) {
            for file in files {
                if let Some(file_str) = file.as_str() {
                    cmd.arg("-i").arg(file_str);
                }
            }
        }

        // 输出文件
        if let Some(output) = params.get("outputFile").and_then(|o| o.as_str()) {
            cmd.arg("-o").arg(output);
        }

        // 层级限制
        if let Some(min_level) = params.get("minLevel").and_then(|l| l.as_i64()) {
            cmd.arg("--min-level").arg(min_level.to_string());
        }

        if let Some(max_level) = params.get("maxLevel").and_then(|l| l.as_i64()) {
            cmd.arg("--max-level").arg(max_level.to_string());
        }

        // 卡密参数
        if let Some(kami_key) = params.get("kamiKey").and_then(|k| k.as_str()) {
            if !kami_key.is_empty() {
                cmd.arg("-k").arg(kami_key);
            }
        }

        info!("  ├─ Executing: {:?}", cmd);

        // 发送开始消息
        let start_msg = WsMessage {
            msg_type: MessageType::Stream,
            id: Some(task_id.clone()),
            data: Some(serde_json::json!({
                "taskId": task_id,
                "type": "start",
                "message": "暴力对比开始"
            })),
        };
        let _ = scan_tx.send(start_msg.encode());

        // 执行命令并获取输出
        match cmd.stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).spawn() {
            Ok(mut child) => {
                let stdout = child.stdout.take().unwrap();
                let stderr = child.stderr.take().unwrap();

                // 读取stdout
                let stdout_task_id = task_id.clone();
                let stdout_tx = scan_tx.clone();
                let stdout_handle = tokio::spawn(async move {
                    let reader = BufReader::new(stdout);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        info!("  ├─ [stdout] {}", line);
                        let stream_msg = WsMessage {
                            msg_type: MessageType::Stream,
                            id: Some(stdout_task_id.clone()),
                            data: Some(serde_json::json!({
                                "taskId": stdout_task_id,
                                "type": "stdout",
                                "line": line
                            })),
                        };
                        let _ = stdout_tx.send(stream_msg.encode());
                    }
                    info!("  ├─ [stdout] 读取完成");
                });

                // 读取stderr
                let stderr_task_id = task_id.clone();
                let stderr_tx = scan_tx.clone();
                let stderr_handle = tokio::spawn(async move {
                    let reader = BufReader::new(stderr);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        info!("  ├─ [stderr] {}", line);
                        let stream_msg = WsMessage {
                            msg_type: MessageType::Stream,
                            id: Some(stderr_task_id.clone()),
                            data: Some(serde_json::json!({
                                "taskId": stderr_task_id,
                                "type": "stderr",
                                "line": line
                            })),
                        };
                        let _ = stderr_tx.send(stream_msg.encode());
                    }
                    info!("  ├─ [stderr] 读取完成");
                });

                // 等待任务完成
                info!("  ├─ 等待子进程完成...");
                let status = child.wait().await;
                info!("  ├─ 等待stdout读取完成...");
                let _ = stdout_handle.await;
                info!("  ├─ 等待stderr读取完成...");
                let _ = stderr_handle.await;
                info!("  ├─ 所有任务完成");

                // 发送完成消息
                let exit_code = status.map(|s| s.code()).unwrap_or(None);
                let complete_msg = WsMessage {
                    msg_type: MessageType::Stream,
                    id: Some(task_id.clone()),
                    data: Some(serde_json::json!({
                        "taskId": task_id,
                        "type": "complete",
                        "exitCode": exit_code,
                        "success": exit_code == Some(0)
                    })),
                };
                info!("  ├─ 发送完成消息");
                let _ = scan_tx.send(complete_msg.encode());

                info!("  ├─ Compare-norm task completed: {} exit_code={:?}", task_id, exit_code);
            }
            Err(e) => {
                error!("  ├─ Failed to start compare-norm: {}", e);
                let error_msg = WsMessage {
                    msg_type: MessageType::Stream,
                    id: Some(task_id.clone()),
                    data: Some(serde_json::json!({
                        "taskId": task_id,
                        "type": "error",
                        "message": format!("启动暴力对比失败: {}", e)
                    })),
                };
                let _ = scan_tx.send(error_msg.encode());
            }
        }
    }

    /// 执行 norm 转 out（同步返回结果）
    async fn execute_to_out(params: &serde_json::Value) -> serde_json::Value {
        use tokio::process::Command;

        let binary = handlers::get_scan_binary();

        // 构建命令参数
        let mut cmd = Command::new(&binary);
        cmd.arg("to-out");

        // 输入文件
        if let Some(files) = params.get("inputFiles").and_then(|f| f.as_array()) {
            for file in files {
                if let Some(file_str) = file.as_str() {
                    cmd.arg("-i").arg(file_str);
                }
            }
        }

        // 输出文件
        if let Some(output) = params.get("outputFile").and_then(|o| o.as_str()) {
            cmd.arg("-o").arg(output);
        }

        // 卡密参数
        if let Some(kami_key) = params.get("kamiKey").and_then(|k| k.as_str()) {
            if !kami_key.is_empty() {
                cmd.arg("-k").arg(kami_key);
            }
        }

        info!("  ├─ Executing to-out: {:?}", cmd);

        match cmd.output().await {
            Ok(output) => {
                let exit_code = output.status.code();
                let stdout = String::from_utf8_lossy(&output.stdout).to_string();
                let stderr = String::from_utf8_lossy(&output.stderr).to_string();

                info!("  ├─ to-out completed: exit_code={:?}", exit_code);
                if !stderr.is_empty() {
                    info!("  ├─ stderr: {}", stderr);
                }

                serde_json::json!({
                    "success": exit_code == Some(0),
                    "exitCode": exit_code,
                    "stdout": stdout.trim(),
                    "stderr": stderr.trim()
                })
            }
            Err(e) => {
                error!("  ├─ Failed to execute to-out: {}", e);
                serde_json::json!({
                    "success": false,
                    "error": format!("执行失败: {}", e)
                })
            }
        }
    }

    /// 运行格式转换任务
    async fn run_convert_format_task(task_id: String, params: serde_json::Value, scan_tx: broadcast::Sender<String>) {
        use tokio::process::Command;
        use tokio::io::{AsyncBufReadExt, BufReader};

        let binary = handlers::get_scan_binary();

        // 构建命令参数
        let mut cmd = Command::new(&binary);
        cmd.arg("format");

        // 输入文件
        if let Some(input) = params.get("filePath").and_then(|i| i.as_str()) {
            cmd.arg("-i").arg(input);
        }

        // 输出文件
        if let Some(output) = params.get("outputPath").and_then(|o| o.as_str()) {
            cmd.arg("-o").arg(output);
        } else {
            // 自动生成输出路径：将 .out/.bin 替换为 .txt
            if let Some(input) = params.get("filePath").and_then(|i| i.as_str()) {
                let output = if input.ends_with(".out") {
                    input.replace(".out", ".txt")
                } else if input.ends_with(".bin") {
                    input.replace(".bin", ".txt")
                } else {
                    format!("{}.txt", input)
                };
                cmd.arg("-o").arg(&output);
            }
        }

        // 进程位数
        let bit = if params.get("is32Bit").and_then(|b| b.as_bool()).unwrap_or(false) { 32 } else { 64 };
        cmd.arg("-b").arg(bit.to_string());

        // 文件夹模式
        if params.get("folder").and_then(|f| f.as_bool()).unwrap_or(false) {
            cmd.arg("--folder");
        }

        // 层级限制
        if let Some(level_min) = params.get("levelMin").and_then(|l| l.as_i64()) {
            cmd.arg("--level-min").arg(level_min.to_string());
        }

        if let Some(level_max) = params.get("levelMax").and_then(|l| l.as_i64()) {
            cmd.arg("--level-max").arg(level_max.to_string());
        }

        // 限制数量
        if let Some(limit) = params.get("limit").and_then(|l| l.as_i64()) {
            cmd.arg("--limit").arg(limit.to_string());
        }

        // 卡密参数
        if let Some(kami_key) = params.get("kamiKey").and_then(|k| k.as_str()) {
            if !kami_key.is_empty() {
                cmd.arg("-k").arg(kami_key);
            }
        }

        info!("  ├─ Executing: {:?}", cmd);

        // 发送开始消息
        let start_msg = WsMessage {
            msg_type: MessageType::Stream,
            id: Some(task_id.clone()),
            data: Some(serde_json::json!({
                "taskId": task_id,
                "type": "start",
                "message": "格式转换开始"
            })),
        };
        let _ = scan_tx.send(start_msg.encode());

        // 执行命令并获取输出
        match cmd.stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).spawn() {
            Ok(mut child) => {
                let stdout = child.stdout.take().unwrap();
                let stderr = child.stderr.take().unwrap();

                // 读取stdout
                let stdout_task_id = task_id.clone();
                let stdout_tx = scan_tx.clone();
                let stdout_handle = tokio::spawn(async move {
                    let reader = BufReader::new(stdout);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        info!("  ├─ [stdout] {}", line);
                        let stream_msg = WsMessage {
                            msg_type: MessageType::Stream,
                            id: Some(stdout_task_id.clone()),
                            data: Some(serde_json::json!({
                                "taskId": stdout_task_id,
                                "type": "stdout",
                                "line": line
                            })),
                        };
                        let _ = stdout_tx.send(stream_msg.encode());
                    }
                    info!("  ├─ [stdout] 读取完成");
                });

                // 读取stderr
                let stderr_task_id = task_id.clone();
                let stderr_tx = scan_tx.clone();
                let stderr_handle = tokio::spawn(async move {
                    let reader = BufReader::new(stderr);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        info!("  ├─ [stderr] {}", line);
                        let stream_msg = WsMessage {
                            msg_type: MessageType::Stream,
                            id: Some(stderr_task_id.clone()),
                            data: Some(serde_json::json!({
                                "taskId": stderr_task_id,
                                "type": "stderr",
                                "line": line
                            })),
                        };
                        let _ = stderr_tx.send(stream_msg.encode());
                    }
                    info!("  ├─ [stderr] 读取完成");
                });

                // 等待任务完成
                info!("  ├─ 等待子进程完成...");
                let _ = tokio::join!(stdout_handle, stderr_handle);
                let output = child.wait_with_output().await;
                let exit_code = output.as_ref().ok().and_then(|o| o.status.code());

                // 发送完成消息
                let complete_msg = WsMessage {
                    msg_type: MessageType::Stream,
                    id: Some(task_id.clone()),
                    data: Some(serde_json::json!({
                        "taskId": task_id,
                        "type": "complete",
                        "success": exit_code == Some(0),
                        "exitCode": exit_code
                    })),
                };
                info!("  ├─ 发送完成消息");
                let _ = scan_tx.send(complete_msg.encode());

                info!("  ├─ Convert-format task completed: {} exit_code={:?}", task_id, exit_code);
            }
            Err(e) => {
                error!("  ├─ Failed to start convert-format: {}", e);
                let error_msg = WsMessage {
                    msg_type: MessageType::Stream,
                    id: Some(task_id.clone()),
                    data: Some(serde_json::json!({
                        "taskId": task_id,
                        "type": "error",
                        "message": format!("启动格式转换失败: {}", e)
                    })),
                };
                let _ = scan_tx.send(error_msg.encode());
            }
        }
    }

    /// 运行过滤任务
    async fn run_filter_task(task_id: String, params: serde_json::Value, scan_tx: broadcast::Sender<String>) {
        use tokio::process::Command;
        use tokio::io::{AsyncBufReadExt, BufReader};

        let binary = handlers::get_scan_binary();

        // 构建命令参数
        let mut cmd = Command::new(&binary);
        cmd.arg("filter");

        // 输入文件
        if let Some(input) = params.get("input").and_then(|i| i.as_str()) {
            cmd.arg("-i").arg(input);
        }

        // 模式
        if let Some(mode) = params.get("mode").and_then(|m| m.as_str()) {
            cmd.arg("-m").arg(mode);
        }

        // 进程位数
        if let Some(bit) = params.get("bit").and_then(|b| b.as_i64()) {
            cmd.arg("-b").arg(bit.to_string());
        }

        // PID
        if let Some(pid) = params.get("pid").and_then(|p| p.as_i64()) {
            cmd.arg("--pid").arg(pid.to_string());
        }

        // 目标地址
        if let Some(target) = params.get("target").and_then(|t| t.as_u64()) {
            cmd.arg("--target").arg(format!("0x{:X}", target));
        }

        // 输出文件
        if let Some(output) = params.get("output").and_then(|o| o.as_str()) {
            cmd.arg("-o").arg(output);
        }

        // 输出模式
        if let Some(output_mode) = params.get("outputMode").and_then(|m| m.as_str()) {
            cmd.arg("--output-mode").arg(output_mode);
        }

        // Reader
        if let Some(reader) = params.get("reader").and_then(|r| r.as_str()) {
            if !reader.is_empty() {
                cmd.arg("--reader").arg(reader);
            }
        }

        // 卡密参数
        if let Some(kami_key) = params.get("kamiKey").and_then(|k| k.as_str()) {
            if !kami_key.is_empty() {
                cmd.arg("-k").arg(kami_key);
            }
        }

        info!("  ├─ Executing filter command");

        // 发送开始消息
        let start_msg = WsMessage {
            msg_type: MessageType::Stream,
            id: Some(task_id.clone()),
            data: Some(serde_json::json!({
                "taskId": task_id,
                "type": "start",
                "message": "过滤开始"
            })),
        };
        let _ = scan_tx.send(start_msg.encode());

        // 执行命令并获取输出
        match cmd.stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).spawn() {
            Ok(mut child) => {
                let stdout = child.stdout.take().unwrap();
                let stderr = child.stderr.take().unwrap();

                // 读取stdout
                let stdout_task_id = task_id.clone();
                let stdout_tx = scan_tx.clone();
                let stdout_handle = tokio::spawn(async move {
                    let reader = BufReader::new(stdout);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        info!("  ├─ [stdout] {}", line);
                        let stream_msg = WsMessage {
                            msg_type: MessageType::Stream,
                            id: Some(stdout_task_id.clone()),
                            data: Some(serde_json::json!({
                                "taskId": stdout_task_id,
                                "type": "stdout",
                                "line": line
                            })),
                        };
                        let _ = stdout_tx.send(stream_msg.encode());
                    }
                    info!("  ├─ [stdout] 读取完成");
                });

                // 读取stderr
                let stderr_task_id = task_id.clone();
                let stderr_tx = scan_tx.clone();
                let stderr_handle = tokio::spawn(async move {
                    let reader = BufReader::new(stderr);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        info!("  ├─ [stderr] {}", line);
                        let stream_msg = WsMessage {
                            msg_type: MessageType::Stream,
                            id: Some(stderr_task_id.clone()),
                            data: Some(serde_json::json!({
                                "taskId": stderr_task_id,
                                "type": "stderr",
                                "line": line
                            })),
                        };
                        let _ = stderr_tx.send(stream_msg.encode());
                    }
                    info!("  ├─ [stderr] 读取完成");
                });

                // 等待任务完成
                info!("  ├─ 等待子进程完成...");
                let status = child.wait().await;
                info!("  ├─ 等待stdout读取完成...");
                let _ = stdout_handle.await;
                info!("  ├─ 等待stderr读取完成...");
                let _ = stderr_handle.await;
                info!("  ├─ 所有任务完成");

                // 发送完成消息
                let exit_code = status.map(|s| s.code()).unwrap_or(None);
                let complete_msg = WsMessage {
                    msg_type: MessageType::Stream,
                    id: Some(task_id.clone()),
                    data: Some(serde_json::json!({
                        "taskId": task_id,
                        "type": "complete",
                        "exitCode": exit_code,
                        "success": exit_code == Some(0)
                    })),
                };
                info!("  ├─ 发送完成消息");
                let _ = scan_tx.send(complete_msg.encode());

                info!("  ├─ Filter task completed: {} exit_code={:?}", task_id, exit_code);
            }
            Err(e) => {
                error!("  ├─ Failed to start filter: {}", e);
                let error_msg = WsMessage {
                    msg_type: MessageType::Stream,
                    id: Some(task_id.clone()),
                    data: Some(serde_json::json!({
                        "taskId": task_id,
                        "type": "error",
                        "message": format!("启动过滤失败: {}", e)
                    })),
                };
                let _ = scan_tx.send(error_msg.encode());
            }
        }
    }
}

/// 处理客户端连接
async fn handle_connection(
    stream: TcpStream,
    addr: SocketAddr,
    broadcast_tx: broadcast::Sender<String>,
    service: Arc<Service>,
) {
    info!("═══════════════════════════════════════════");
    info!("New WebSocket connection from: {}", addr);
    info!("═══════════════════════════════════════════");

    let ws_stream = match accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            error!("WebSocket handshake failed for {}: {}", addr, e);
            return;
        }
    };

    info!("[{}] WebSocket handshake completed", addr);

    let (mut ws_sender, mut ws_receiver) = ws_stream.split();

    // 订阅广播
    let mut broadcast_rx = broadcast_tx.subscribe();

    // 订阅扫描输出
    let mut scan_output_rx = service.get_scan_output_rx();

    // 发送欢迎消息
    let welcome = WsMessage::response(
        None,
        serde_json::json!({
            "status": "connected",
            "message": "Welcome to FScan Service",
            "version": "2.0.0",
            "features": ["heartbeat", "command"],
            "commands": ["ping", "status", "login", "kami_info", "get_apps", "get_app_info", "get_modules", "get_next_file", "start_scan", "compare", "compare_norm", "to_out", "filter_run", "convert_format"]
        }),
    );
    info!("[{}] → Sending welcome message", addr);
    debug!("[{}] → Welcome: {}", addr, welcome.encode());
    if let Err(e) = ws_sender.send(welcome.encode().into()).await {
        error!("Failed to send welcome message to {}: {}", addr, e);
        return;
    }

    // 双向消息转发
    let tx = broadcast_tx.clone();
    let client_addr = addr;
    let mut send_task = tokio::spawn(async move {
        // 合并两个接收器
        loop {
            tokio::select! {
                msg = broadcast_rx.recv() => {
                    if let Ok(msg) = msg {
                        debug!("[{}] → Sending broadcast: {}", client_addr, msg);
                        if ws_sender.send(msg.into()).await.is_err() {
                            break;
                        }
                    }
                }
                msg = scan_output_rx.recv() => {
                    if let Ok(msg) = msg {
                        let preview: String = msg.chars().take(100).collect();
                        info!("[{}] → Sending scan output: {}...", client_addr, preview);
                        if ws_sender.send(msg.into()).await.is_err() {
                            break;
                        }
                    }
                }
            }
        }
    });

    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = ws_receiver.next().await {
            if let tokio_tungstenite::tungstenite::Message::Text(text) = msg {
                info!("[{}] ← Received: {}", addr, text);

                // 解析消息
                if let Some(ws_msg) = WsMessage::decode(&text) {
                    // 通过 Service 处理消息
                    if let Some(response) = service.handle_message(ws_msg, tx.clone()).await {
                        info!("[{}] → Response type: {:?}", addr, response.msg_type);
                        debug!("[{}] → Response: {}", addr, response.encode());
                        let _ = tx.send(response.encode());
                    }
                } else {
                    warn!("[{}] ⚠ Failed to parse message", addr);
                }
            }
        }
    });

    // 等待任一任务完成
    tokio::select! {
        _ = &mut send_task => recv_task.abort(),
        _ = &mut recv_task => send_task.abort(),
    }

    info!("═══════════════════════════════════════════");
    info!("Connection closed: {}", addr);
    info!("═══════════════════════════════════════════");
}

#[tokio::main]
async fn main() {
    // 初始化日志（默认 info 级别）
    if std::env::var("RUST_LOG").is_err() {
        std::env::set_var("RUST_LOG", "info");
    }
    env_logger::init();

    // 启动日志
    info!("╔═══════════════════════════════════════════╗");
    info!("║     FScan Service v2.0.0                  ║");
    info!("║     Command Executor Mode                 ║");
    info!("╚═══════════════════════════════════════════╝");

    // 创建服务
    let service = Arc::new(Service::new());
    info!("✓ Service initialized with {} command handlers", service.handlers.len());

    // 绑定地址
    let addr = "0.0.0.0:8080";
    info!("Starting server on: {}", addr);

    let listener = match TcpListener::bind(addr).await {
        Ok(l) => {
            info!("✓ Server bound to: {}", addr);
            l
        }
        Err(e) => {
            error!("✗ Failed to bind to {}: {}", addr, e);
            std::process::exit(1);
        }
    };

    // 广播通道
    let (broadcast_tx, _) = broadcast::channel(100);
    info!("✓ Broadcast channel created");

    info!("═══════════════════════════════════════════");
    info!("Server ready, waiting for connections...");
    info!("═══════════════════════════════════════════");

    // 接受连接
    while let Ok((stream, addr)) = listener.accept().await {
        info!("New connection from: {}", addr);
        let broadcast_tx = broadcast_tx.clone();
        let service = service.clone();
        tokio::spawn(async move {
            handle_connection(stream, addr, broadcast_tx, service).await;
        });
    }
}
