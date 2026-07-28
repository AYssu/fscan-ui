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
