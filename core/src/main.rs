use futures_util::{SinkExt, StreamExt};
use log::{error, info, warn, debug};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::broadcast;
use tokio_tungstenite::accept_async;

/// 消息类型
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum MessageType {
    Heartbeat,
    Command,
    Response,
    Error,
}

/// WebSocket 消息
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct WsMessage {
    #[serde(rename = "type")]
    pub msg_type: MessageType,
    pub data: Option<serde_json::Value>,
    pub id: Option<String>,
}

impl WsMessage {
    pub fn heartbeat() -> Self {
        Self {
            msg_type: MessageType::Heartbeat,
            data: None,
            id: None,
        }
    }

    pub fn response(id: Option<String>, data: serde_json::Value) -> Self {
        Self {
            msg_type: MessageType::Response,
            data: Some(data),
            id,
        }
    }

    pub fn error(id: Option<String>, message: &str) -> Self {
        Self {
            msg_type: MessageType::Error,
            data: Some(serde_json::json!({ "message": message })),
            id,
        }
    }

    pub fn encode(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }

    pub fn decode(s: &str) -> Option<Self> {
        serde_json::from_str(s).ok()
    }
}

/// 处理客户端连接
async fn handle_connection(
    stream: TcpStream,
    addr: SocketAddr,
    broadcast_tx: broadcast::Sender<String>,
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
            "message": "Welcome to FScan WebSocket Server"
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
                    match ws_msg.msg_type {
                        MessageType::Heartbeat => {
                            // 心跳响应
                            info!("[{}] ♥ Heartbeat received, sending pong", addr);
                            let pong = WsMessage::heartbeat();
                            let response = pong.encode();
                            debug!("[{}] → Heartbeat response: {}", addr, response);
                            let _ = tx.send(response);
                        }
                        MessageType::Command => {
                            // 处理指令
                            info!("[{}] ⚡ Processing command", addr);
                            let response = handle_command(&ws_msg);
                            info!("[{}] → Command response: {:?}", addr, response.msg_type);
                            debug!("[{}] → Response: {}", addr, response.encode());
                            let _ = tx.send(response.encode());
                        }
                        _ => {
                            warn!("[{}] ❓ Unknown message type: {:?}", addr, ws_msg.msg_type);
                        }
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

/// 处理指令
fn handle_command(msg: &WsMessage) -> WsMessage {
    let data = msg.data.as_ref();

    // 解析指令
    let command = data
        .and_then(|d| d.get("command"))
        .and_then(|c| c.as_str())
        .unwrap_or("unknown");

    let params = data.and_then(|d| d.get("params"));

    info!("  ├─ Command: {}", command);
    debug!("  └─ Params: {:?}", params);

    let response = match command {
        "ping" => {
            info!("  ├─ Processing: ping");
            WsMessage::response(
                msg.id.clone(),
                serde_json::json!({ "pong": true }),
            )
        }
        "status" => {
            info!("  ├─ Processing: status");
            WsMessage::response(
                msg.id.clone(),
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
        "scan" => {
            // 示例：扫描指令
            let target = params
                .and_then(|p| p.get("target"))
                .and_then(|t| t.as_str())
                .unwrap_or("0x0");

            info!("  ├─ Processing: scan target={}", target);
            WsMessage::response(
                msg.id.clone(),
                serde_json::json!({
                    "status": "started",
                    "target": target,
                    "message": "Scan started",
                }),
            )
        }
        "login" => {
            // 登录指令
            let account = params
                .and_then(|p| p.get("account"))
                .and_then(|a| a.as_str())
                .unwrap_or("");
            let password = params
                .and_then(|p| p.get("password"))
                .and_then(|p| p.as_str())
                .unwrap_or("");

            info!("  ├─ Processing: login account={}", account);

            // 验证账号密码（假数据）
            if account == "2997036064" && password.len() > 0 {
                info!("  ├─ Login success");
                WsMessage::response(
                    msg.id.clone(),
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
                WsMessage::error(
                    msg.id.clone(),
                    "账号或密码错误",
                )
            }
        }
        "get_processes" => {
            // 获取进程列表（假数据）
            info!("  ├─ Processing: get_processes");
            WsMessage::response(
                msg.id.clone(),
                serde_json::json!({
                    "success": true,
                    "processes": [
                        {
                            "packageName": "com.tencent.tmgp.sgame",
                            "arch": "x64",
                            "pid": 12345
                        },
                        {
                            "packageName": "com.miHoYo.Yuanshen",
                            "arch": "x64",
                            "pid": 23456
                        },
                        {
                            "packageName": "com.netease.g93na",
                            "arch": "x64",
                            "pid": 34567
                        },
                        {
                            "packageName": "com.tencent.ig",
                            "arch": "x64",
                            "pid": 45678
                        },
                        {
                            "packageName": "com.activision.callofduty.shooter",
                            "arch": "arm64",
                            "pid": 56789
                        }
                    ]
                }),
            )
        }
        "get_modules" => {
            // 获取模块列表（假数据，根据包名返回不同模块）
            let package_name = params
                .and_then(|p| p.get("packageName"))
                .and_then(|p| p.as_str())
                .unwrap_or("");

            info!("  ├─ Processing: get_modules package={}", package_name);

            let modules = match package_name {
                "com.tencent.tmgp.sgame" => {
                    // 王者荣耀模块
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
                    // 原神模块
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
                    // 第五人格模块
                    serde_json::json!([
                        {"name": "libgame.so", "index": "1", "type": "Cd", "startAddress": "0x1100000", "endAddress": "0x1200000"},
                        {"name": "libgame.so", "index": "2", "type": "Xa", "startAddress": "0x1200000", "endAddress": "0x1350000"},
                        {"name": "libunity.so", "index": "1", "type": "Cd", "startAddress": "0x1400000", "endAddress": "0x1480000"},
                        {"name": "libc.so", "index": "1", "type": "Cd", "startAddress": "0x1500000", "endAddress": "0x1520000"}
                    ])
                }
                "com.tencent.ig" => {
                    // PUBG Mobile模块
                    serde_json::json!([
                        {"name": "libtersafe2.so", "index": "1", "type": "Cd", "startAddress": "0x1600000", "endAddress": "0x1700000"},
                        {"name": "libUE4.so", "index": "1", "type": "Cd", "startAddress": "0x1700000", "endAddress": "0x1A00000"},
                        {"name": "libUE4.so", "index": "2", "type": "Cb", "startAddress": "0x1A00000", "endAddress": "0x1A80000"},
                        {"name": "libUE4.so", "index": "3", "type": "Xa", "startAddress": "0x1A80000", "endAddress": "0x2000000"},
                        {"name": "libc.so", "index": "1", "type": "Cd", "startAddress": "0x2100000", "endAddress": "0x2120000"}
                    ])
                }
                "com.activision.callofduty.shooter" => {
                    // 使命召唤模块
                    serde_json::json!([
                        {"name": "libil2cpp.so", "index": "1", "type": "Cd", "startAddress": "0x2200000", "endAddress": "0x2400000"},
                        {"name": "libil2cpp.so", "index": "2", "type": "Xa", "startAddress": "0x2400000", "endAddress": "0x2700000"},
                        {"name": "libnative.so", "index": "1", "type": "Xa", "startAddress": "0x2800000", "endAddress": "0x2900000"},
                        {"name": "libc.so", "index": "1", "type": "Cd", "startAddress": "0x2A00000", "endAddress": "0x2A20000"}
                    ])
                }
                _ => {
                    // 默认模块
                    serde_json::json!([
                        {"name": "libmain.so", "index": "1", "type": "Cd", "startAddress": "0x3000000", "endAddress": "0x3100000"},
                        {"name": "libc.so", "index": "1", "type": "Cd", "startAddress": "0x3200000", "endAddress": "0x3220000"}
                    ])
                }
            };

            WsMessage::response(
                msg.id.clone(),
                serde_json::json!({
                    "success": true,
                    "packageName": package_name,
                    "modules": modules
                }),
            )
        }
        "get_files" => {
            // 获取文件列表（假数据）
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

            // 所有假数据
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

            // 根据 extensions 过滤文件
            let files: Vec<_> = all_files.into_iter()
                .filter(|f| {
                    let ext = f.get("extension").and_then(|e| e.as_str()).unwrap_or("");
                    extensions.contains(&ext)
                })
                .collect();

            WsMessage::response(
                msg.id.clone(),
                serde_json::json!({
                    "success": true,
                    "dir": dir,
                    "extensions": extensions,
                    "files": files
                }),
            )
        }
        "convert_format" => {
            // 转换格式文件（假数据）
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

            info!("  ├─ Processing: convert_format file={} limit={} is32bit={}", file_path, limit, is_32bit);

            // 生成输出文件路径（将 .out/.bin 替换为 .txt）
            let output_path = if file_path.ends_with(".out") {
                file_path.replace(".out", ".txt")
            } else if file_path.ends_with(".bin") {
                file_path.replace(".bin", ".txt")
            } else {
                format!("{}.txt", file_path)
            };

            WsMessage::response(
                msg.id.clone(),
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
        "preview_txt" => {
            // 预览 txt 文件前N行（假数据）
            let file_path = params
                .and_then(|p| p.get("filePath"))
                .and_then(|f| f.as_str())
                .unwrap_or("");
            let max_lines = params
                .and_then(|p| p.get("maxLines"))
                .and_then(|l| l.as_i64())
                .unwrap_or(200);

            info!("  ├─ Processing: preview_txt file={} maxLines={}", file_path, max_lines);

            // 假数据：返回一些预览行
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
                msg.id.clone(),
                serde_json::json!({
                    "success": true,
                    "filePath": file_path,
                    "totalLines": lines.len(),
                    "lines": lines
                }),
            )
        }
        "debug_pointers" => {
            // 批量调试指针（假数据）
            let pointers = params
                .and_then(|p| p.get("pointers"))
                .and_then(|p| p.as_array())
                .map(|arr| arr.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>())
                .unwrap_or_else(|| vec![]);

            info!("  ├─ Processing: debug_pointers count={}", pointers.len());

            // 假数据：为每个指针链生成调试结果
            let results: Vec<_> = pointers.iter().enumerate().map(|(i, ptr)| {
                if ptr.contains("error") || ptr.is_empty() {
                    serde_json::json!({
                        "input": ptr,
                        "error": "无效的指针格式"
                    })
                } else {
                    // 模拟调试结果
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
            }).collect();

            WsMessage::response(
                msg.id.clone(),
                serde_json::json!({
                    "success": true,
                    "count": results.len(),
                    "results": results
                }),
            )
        }
        _ => {
            warn!("  ├─ Unknown command: {}", command);
            WsMessage::error(
                msg.id.clone(),
                &format!("Unknown command: {}", command),
            )
        }
    };

    info!("  └─ Response type: {:?}", response.msg_type);
    response
}

#[tokio::main]
async fn main() {
    // 初始化日志
    env_logger::init();

    // 启动日志
    info!("╔═══════════════════════════════════════════╗");
    info!("║     FScan WebSocket Server v1.0.0         ║");
    info!("╚═══════════════════════════════════════════╝");

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
        tokio::spawn(async move {
            handle_connection(stream, addr, broadcast_tx).await;
        });
    }
}
