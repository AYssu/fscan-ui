use log::info;
use serde::{Deserialize, Serialize};
use std::process::Command;

/// 进程信息
#[derive(Debug, Serialize, Deserialize)]
pub struct ProcessInfo {
    #[serde(rename = "packageName")]
    pub package_name: String,
    pub pid: i32,
    #[serde(default = "default_arch")]
    pub arch: String,
}

/// 内存模块信息
#[derive(Debug, Serialize, Deserialize)]
pub struct MemoryModule {
    pub name: String,
    pub index: String,
    #[serde(rename = "type")]
    pub mem_type: String,
    #[serde(rename = "startAddress")]
    pub start_address: String,
    #[serde(rename = "endAddress")]
    pub end_address: String,
}

fn default_arch() -> String {
    "unknown".to_string()
}

/// 获取可执行文件路径
/// 优先查找当前目录下的 scan，然后查找 core-fs/build/scan
pub fn get_scan_binary() -> String {
    let local_paths = [
        "./scan",
        "./core-fs/build/scan",
    ];

    for path in &local_paths {
        if std::path::Path::new(path).exists() {
            return path.to_string();
        }
    }

    // 默认返回 scan，依赖 PATH 环境变量
    "scan".to_string()
}

/// 通过执行外部 scan apps 命令获取运行的应用列表
pub fn get_running_apps() -> Result<Vec<ProcessInfo>, String> {
    let binary = get_scan_binary();
    info!("  Executing: {} apps", binary);

    let output = Command::new(&binary)
        .arg("apps")
        .output()
        .map_err(|e| format!("Failed to execute {}: {}", binary, e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Command failed: {}", stderr));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    info!("  Raw output: {}", stdout);

    // 解析 JSON 数组
    let apps: Vec<ProcessInfo> = serde_json::from_str(&stdout)
        .map_err(|e| format!("Failed to parse JSON: {}", e))?;

    info!("  Found {} running apps", apps.len());
    Ok(apps)
}

/// 通过执行外部 scan modules 命令获取进程的内存模块列表
pub fn get_process_modules(package_name: &str) -> Result<Vec<MemoryModule>, String> {
    let binary = get_scan_binary();
    info!("  Executing: {} modules -p {}", binary, package_name);

    let output = Command::new(&binary)
        .arg("modules")
        .arg("-p")
        .arg(package_name)
        .output()
        .map_err(|e| format!("Failed to execute {}: {}", binary, e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Command failed: {}", stderr));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    info!("  Raw output: {}", stdout);

    // 解析 JSON 响应
    #[derive(Deserialize)]
    struct ModulesResponse {
        success: bool,
        #[serde(rename = "packageName")]
        package_name: String,
        #[allow(dead_code)]
        pid: i32,
        modules: Vec<MemoryModule>,
    }

    let response: ModulesResponse = serde_json::from_str(&stdout)
        .map_err(|e| format!("Failed to parse JSON: {}", e))?;

    if !response.success {
        return Err("Command returned success=false".to_string());
    }

    info!("  Found {} modules for {}", response.modules.len(), response.package_name);
    Ok(response.modules)
}

/// 通过执行外部 scan app-info 命令获取单个应用的详细信息（包括PID）
pub fn get_app_info(package_name: &str) -> Result<ProcessInfo, String> {
    let binary = get_scan_binary();
    info!("  Executing: {} app-info -p {}", binary, package_name);

    let output = Command::new(&binary)
        .arg("app-info")
        .arg("-p")
        .arg(package_name)
        .output()
        .map_err(|e| format!("Failed to execute {}: {}", binary, e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Command failed: {}", stderr));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    info!("  Raw output: {}", stdout);

    // 解析 JSON 响应
    let app_info: ProcessInfo = serde_json::from_str(&stdout)
        .map_err(|e| format!("Failed to parse JSON: {}", e))?;

    info!("  Found app: {} PID={}", app_info.package_name, app_info.pid);
    Ok(app_info)
}

/// 通过执行外部 scan next-file 命令获取下一个可用的输出文件路径
pub fn get_next_file_path(dir: &str, extension: &str) -> Result<String, String> {
    let binary = get_scan_binary();
    info!("  Executing: {} next-file {} {}", binary, dir, extension);

    let output = Command::new(&binary)
        .arg("next-file")
        .arg(dir)
        .arg(extension)
        .output()
        .map_err(|e| format!("Failed to execute {}: {}", binary, e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Command failed: {}", stderr));
    }

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    info!("  Next file path: {}", stdout);

    Ok(stdout)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_scan_binary() {
        let binary = get_scan_binary();
        assert!(!binary.is_empty());
    }
}
