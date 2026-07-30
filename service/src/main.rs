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
    GetProcesses,
    GetModules,
    GetFiles,
    ConvertFormat,
    PreviewTxt,
    DebugPointers,
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
            Self::GetProcesses => {
                info!("  ├─ Processing: get_processes");
                WsMessage::response(
                    id,
                    serde_json::json!({
                        "success": true,
                        "processes": [
                            { "packageName": "com.tencent.tmgp.sgame", "arch": "x64", "pid": 12345 },
                            { "packageName": "com.miHoYo.Yuanshen", "arch": "x64", "pid": 23456 },
                            { "packageName": "com.netease.g93na", "arch": "x64", "pid": 34567 },
                            { "packageName": "com.tencent.ig", "arch": "x64", "pid": 45678 },
                            { "packageName": "com.activision.callofduty.shooter", "arch": "arm64", "pid": 56789 }
                        ]
                    }),
                )
            }
            Self::GetModules => {
                let package_name = params
                    .and_then(|p| p.get("packageName"))
                    .and_then(|p| p.as_str())
                    .unwrap_or("");

                info!("  ├─ Processing: get_modules package={}", package_name);

                let modules = match package_name {
                    "com.tencent.tmgp.sgame" => {
                        serde_json::json!([
                            {"name": "libil2cpp.so", "index": "1", "type": "Cd", "startAddress": "0x100000", "endAddress": "0x250000"},
                            {"name": "libil2cpp.so", "index": "2", "type": "Cb", "startAddress": "0x250000", "endAddress": "0x2A0000"},
                            {"name": "libil2cpp.so", "index": "3", "type": "Xa", "startAddress": "0x2A0000", "endAddress": "0x500000"},
                            {"name": "libunity.so", "index": "1", "type": "Cd", "startAddress": "0x500000", "endAddress": "0x580000"},
                            {"name": "libunity.so", "index": "2", "type": "Xa", "startAddress": "0x580000", "endAddress": "0x620000"},
                            {"name": "libc.so", "index": "1", "type": "Cd", "startAddress": "0x700000", "endAddress": "0x720000"},
                            {"name": "libc.so", "index": "2", "type": "Cb", "startAddress": "0x720000", "endAddress": "0x740000"}
                        ])
                    }
                    "com.miHoYo.Yuanshen" => {
                        serde_json::json!([
                            {"name": "libil2cpp.so", "index": "1", "type": "Cd", "startAddress": "0x800000", "endAddress": "0xA00000"},
                            {"name": "libil2cpp.so", "index": "2", "type": "Cb", "startAddress": "0xA00000", "endAddress": "0xA80000"},
                            {"name": "libil2cpp.so", "index": "3", "type": "Xa", "startAddress": "0xA80000", "endAddress": "0xD00000"},
                            {"name": "libunity.so", "index": "1", "type": "Cd", "startAddress": "0xD00000", "endAddress": "0xD80000"},
                            {"name": "libnative.so", "index": "1", "type": "Xa", "startAddress": "0xE00000", "endAddress": "0xE80000"},
                            {"name": "libmihoyo.so", "index": "1", "type": "Cd", "startAddress": "0xF00000", "endAddress": "0xF50000"},
                            {"name": "libc.so", "index": "1", "type": "Cd", "startAddress": "0x1000000", "endAddress": "0x1020000"},
                            {"name": "libdl.so", "index": "1", "type": "Cb", "startAddress": "0x1020000", "endAddress": "0x1030000"}
                        ])
                    }
                    "com.netease.g93na" => {
                        serde_json::json!([
                            {"name": "libgame.so", "index": "1", "type": "Cd", "startAddress": "0x1100000", "endAddress": "0x1200000"},
                            {"name": "libgame.so", "index": "2", "type": "Xa", "startAddress": "0x1200000", "endAddress": "0x1350000"},
                            {"name": "libunity.so", "index": "1", "type": "Cd", "startAddress": "0x1400000", "endAddress": "0x1480000"},
                            {"name": "libc.so", "index": "1", "type": "Cd", "startAddress": "0x1500000", "endAddress": "0x1520000"}
                        ])
                    }
                    "com.tencent.ig" => {
                        serde_json::json!([
                            {"name": "libtersafe2.so", "index": "1", "type": "Cd", "startAddress": "0x1600000", "endAddress": "0x1700000"},
                            {"name": "libUE4.so", "index": "1", "type": "Cd", "startAddress": "0x1700000", "endAddress": "0x1A00000"},
                            {"name": "libUE4.so", "index": "2", "type": "Cb", "startAddress": "0x1A00000", "endAddress": "0x1A80000"},
                            {"name": "libUE4.so", "index": "3", "type": "Xa", "startAddress": "0x1A80000", "endAddress": "0x2000000"},
                            {"name": "libc.so", "index": "1", "type": "Cd", "startAddress": "0x2100000", "endAddress": "0x2120000"}
                        ])
                    }
                    "com.activision.callofduty.shooter" => {
                        serde_json::json!([
                            {"name": "libil2cpp.so", "index": "1", "type": "Cd", "startAddress": "0x2200000", "endAddress": "0x2400000"},
                            {"name": "libil2cpp.so", "index": "2", "type": "Xa", "startAddress": "0x2400000", "endAddress": "0x2700000"},
                            {"name": "libnative.so", "index": "1", "type": "Xa", "startAddress": "0x2800000", "endAddress": "0x2900000"},
                            {"name": "libc.so", "index": "1", "type": "Cd", "startAddress": "0x2A00000", "endAddress": "0x2A20000"}
                        ])
                    }
                    _ => {
                        serde_json::json!([
                            {"name": "libmain.so", "index": "1", "type": "Cd", "startAddress": "0x3000000", "endAddress": "0x3100000"},
                            {"name": "libc.so", "index": "1", "type": "Cd", "startAddress": "0x3200000", "endAddress": "0x3220000"}
                        ])
                    }
                };

                WsMessage::response(
                    id,
                    serde_json::json!({
                        "success": true,
                        "packageName": package_name,
                        "modules": modules
                    }),
                )
            }
            Self::GetFiles => {
                let dir = params
                    .and_then(|p| p.get("dir"))
                    .and_then(|d| d.as_str())
                    .unwrap_or("/sdcard/fscan/data");
                let extensions = params
                    .and_then(|p| p.get("extensions"))
                    .and_then(|e| e.as_array())
                    .map(|arr| arr.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>())
                    .unwrap_or_else(|| vec!["out", "txt"]);

                info!("  ├─ Processing: get_files dir={} extensions={:?}", dir, extensions);

                let all_files = vec![
                    serde_json::json!({
                        "name": "scan_result_20260726.out",
                        "path": "/sdcard/fscan/data/scan_result_20260726.out",
                        "size": 1258291,
                        "modified": "2026-07-26 14:30:22",
                        "extension": "out",
                        "arch": "x64"
                    }),
                    serde_json::json!({
                        "name": "scan_result_20260725.out",
                        "path": "/sdcard/fscan/data/scan_result_20260725.out",
                        "size": 892416,
                        "modified": "2026-07-25 18:15:45",
                        "extension": "out",
                        "arch": "arm64"
                    }),
                    serde_json::json!({
                        "name": "pointer_list.txt",
                        "path": "/sdcard/fscan/data/pointer_list.txt",
                        "size": 45678,
                        "modified": "2026-07-26 10:22:11",
                        "extension": "txt"
                    }),
                    serde_json::json!({
                        "name": "game_data.txt",
                        "path": "/sdcard/fscan/data/game_data.txt",
                        "size": 234567,
                        "modified": "2026-07-24 09:45:33",
                        "extension": "txt"
                    }),
                    serde_json::json!({
                        "name": "base_address.out",
                        "path": "/sdcard/fscan/data/base_address.out",
                        "size": 67890,
                        "modified": "2026-07-23 16:58:12",
                        "extension": "out",
                        "arch": "x86"
                    }),
                ];

                let files: Vec<_> = all_files
                    .into_iter()
                    .filter(|f| {
                        let ext = f.get("extension").and_then(|e| e.as_str()).unwrap_or("");
                        extensions.contains(&ext)
                    })
                    .collect();

                WsMessage::response(
                    id,
                    serde_json::json!({
                        "success": true,
                        "dir": dir,
                        "extensions": extensions,
                        "files": files
                    }),
                )
            }
            Self::ConvertFormat => {
                let file_path = params
                    .and_then(|p| p.get("filePath"))
                    .and_then(|f| f.as_str())
                    .unwrap_or("");
                let limit = params
                    .and_then(|p| p.get("limit"))
                    .and_then(|l| l.as_i64())
                    .unwrap_or(300000000);
                let is_32bit = params
                    .and_then(|p| p.get("is32Bit"))
                    .and_then(|b| b.as_bool())
                    .unwrap_or(false);

                info!(
                    "  ├─ Processing: convert_format file={} limit={} is32bit={}",
                    file_path, limit, is_32bit
                );

                let output_path = if file_path.ends_with(".out") {
                    file_path.replace(".out", ".txt")
                } else if file_path.ends_with(".bin") {
                    file_path.replace(".bin", ".txt")
                } else {
                    format!("{}.txt", file_path)
                };

                WsMessage::response(
                    id,
                    serde_json::json!({
                        "success": true,
                        "inputPath": file_path,
                        "outputPath": output_path,
                        "limit": limit,
                        "is32Bit": is_32bit,
                        "message": "转换完成"
                    }),
                )
            }
            Self::PreviewTxt => {
                let file_path = params
                    .and_then(|p| p.get("filePath"))
                    .and_then(|f| f.as_str())
                    .unwrap_or("");
                let max_lines = params
                    .and_then(|p| p.get("maxLines"))
                    .and_then(|l| l.as_i64())
                    .unwrap_or(200);

                info!(
                    "  ├─ Processing: preview_txt file={} maxLines={}",
                    file_path, max_lines
                );

                let lines = vec![
                    "libil2cpp.so[Cd][1]+0x1000 -> [0x7fff12345678]",
                    "libil2cpp.so[Cd][1]+0x1008 -> [0x7fff12345680]",
                    "libil2cpp.so[Cb][2]+0x200 -> [0x7fff23456789]",
                    "libil2cpp.so[Xa][3]+0x3000 -> [0x7fff34567890]",
                    "libunity.so[Cd][1]+0x500 -> [0x7fff45678901]",
                    "libc.so[Cd][1]+0x100 -> [0x7fff56789012]",
                    "libc.so[Cb][2]+0x200 -> [0x7fff67890123]",
                    "libm.so[Cb][1]+0x300 -> [0x7fff78901234]",
                ];

                WsMessage::response(
                    id,
                    serde_json::json!({
                        "success": true,
                        "filePath": file_path,
                        "totalLines": lines.len(),
                        "lines": lines
                    }),
                )
            }
            Self::DebugPointers => {
                let pointers = params
                    .and_then(|p| p.get("pointers"))
                    .and_then(|p| p.as_array())
                    .map(|arr| arr.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>())
                    .unwrap_or_default();

                info!("  ├─ Processing: debug_pointers count={}", pointers.len());

                let results: Vec<_> = pointers
                    .iter()
                    .enumerate()
                    .map(|(i, ptr)| {
                        if ptr.contains("error") || ptr.is_empty() {
                            serde_json::json!({
                                "input": ptr,
                                "error": "无效的指针格式"
                            })
                        } else {
                            let base_addr = 0x7fff00000000u64 + (i as u64 * 0x10000);
                            serde_json::json!({
                                "input": ptr,
                                "dword": format!("0x{:08x}", base_addr % 0xFFFFFFFF),
                                "float": format!("{:.8}", (base_addr as f64 % 100.0) / 100.0),
                                "trace": [
                                    format!("libUE4.so[Cd][1] = 0x{:x}", base_addr),
                                    format!("0x{:x}+0xffff = 0x{:x}", base_addr, base_addr + 0xffff),
                                    format!("0x{:x}+0x123 = 0x{:x}", base_addr + 0xffff, base_addr + 0xffff + 0x123),
                                    format!("0x{:x}+0x234 = 0x{:x}", base_addr + 0xffff + 0x123, base_addr + 0xffff + 0x123 + 0x234),
                                ]
                            })
                        }
                    })
                    .collect();

                WsMessage::response(
                    id,
                    serde_json::json!({
                        "success": true,
                        "count": results.len(),
                        "results": results
                    }),
                )
            }
        }
    }
}

/// 服务核心 - 命令执行器
pub struct Service {
    handlers: HashMap<String, CommandHandler>,
}

impl Service {
    pub fn new() -> Self {
        let mut handlers: HashMap<String, CommandHandler> = HashMap::new();

        // 注册所有命令处理器
        handlers.insert("ping".to_string(), CommandHandler::Ping);
        handlers.insert("status".to_string(), CommandHandler::Status);
        handlers.insert("login".to_string(), CommandHandler::Login);
        handlers.insert("get_processes".to_string(), CommandHandler::GetProcesses);
        handlers.insert("get_modules".to_string(), CommandHandler::GetModules);
        handlers.insert("get_files".to_string(), CommandHandler::GetFiles);
        handlers.insert("convert_format".to_string(), CommandHandler::ConvertFormat);
        handlers.insert("preview_txt".to_string(), CommandHandler::PreviewTxt);
        handlers.insert("debug_pointers".to_string(), CommandHandler::DebugPointers);

        Self { handlers }
    }

    pub async fn handle_message(&self, msg: WsMessage) -> Option<WsMessage> {
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

    // 发送欢迎消息
    let welcome = WsMessage::response(
        None,
        serde_json::json!({
            "status": "connected",
            "message": "Welcome to FScan Service",
            "version": "2.0.0",
            "features": ["heartbeat", "command"]
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
        while let Ok(msg) = broadcast_rx.recv().await {
            debug!("[{}] → Sending broadcast: {}", client_addr, msg);
            if ws_sender.send(msg.into()).await.is_err() {
                break;
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
                    if let Some(response) = service.handle_message(ws_msg).await {
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
    // 初始化日志
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
