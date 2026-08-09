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

/// 通过执行外部 scan get-files 命令获取目录中的文件列表
pub fn get_files_in_dir(dir: &str, extensions: &[String]) -> Result<Vec<serde_json::Value>, String> {
    let binary = get_scan_binary();

    // 构建命令：./scan get-files -d <dir> -e <extension>
    // 注意：scan 命令每次只能查询一个扩展名，需要多次调用
    let mut all_files = Vec::new();

    for ext in extensions {
        info!("  Executing: {} get-files -d {} -e {}", binary, dir, ext);

        let output = Command::new(&binary)
            .arg("get-files")
            .arg("-d")
            .arg(dir)
            .arg("-e")
            .arg(ext)
            .output()
            .map_err(|e| format!("Failed to execute {}: {}", binary, e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!("Command failed: {}", stderr));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        info!("  Raw output: {}", &stdout[..stdout.len().min(200)]);

        // 解析 JSON 响应
        #[derive(serde::Deserialize)]
        struct FilesResponse {
            success: bool,
            files: Vec<serde_json::Value>,
        }

        let response: FilesResponse = serde_json::from_str(&stdout)
            .map_err(|e| format!("Failed to parse JSON: {}", e))?;

        if !response.success {
            return Err("Command returned success=false".to_string());
        }

        all_files.extend(response.files);
    }

    // 按修改时间排序（最新的在前）
    all_files.sort_by(|a, b| {
        let time_a = a.get("modified").and_then(|v| v.as_str()).unwrap_or("0");
        let time_b = b.get("modified").and_then(|v| v.as_str()).unwrap_or("0");
        time_b.cmp(time_a)
    });

    info!("  Found {} files in {}", all_files.len(), dir);
    Ok(all_files)
}

/// 通过执行外部 scan reader-test 命令测试读取器
pub fn reader_test(reader_type: &str) -> Result<String, String> {
    let binary = get_scan_binary();
    info!("  Executing: {} reader-test --reader {}", binary, reader_type);

    let mut cmd = Command::new(&binary);
    cmd.arg("reader-test");
    if !reader_type.is_empty() {
        cmd.arg("--reader").arg(reader_type);
    }

    let output = cmd.output()
        .map_err(|e| format!("Failed to execute {}: {}", binary, e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success() {
        return Err(format!("Command failed: {}", stderr));
    }

    info!("  Reader test output: {} bytes", stdout.len());
    Ok(stdout)
}

/// 列出过滤目标地址（对应 filter -l 命令）
pub fn filter_list_targets(
    input_file: &str,
    mode: &str,
    bit: i32,
    value_type: i32,
    pid: i32,
) -> Result<serde_json::Value, String> {
    let binary = get_scan_binary();
    info!("  Executing: {} filter -i {} -m {} -b {} --pid {} --list --value-type {}", binary, input_file, mode, bit, pid, value_type);

    let output = Command::new(&binary)
        .arg("filter")
        .arg("-i")
        .arg(input_file)
        .arg("-m")
        .arg(mode)
        .arg("-b")
        .arg(bit.to_string())
        .arg("--pid")
        .arg(pid.to_string())
        .arg("--list")
        .arg("--value-type")
        .arg(value_type.to_string())
        .output()
        .map_err(|e| format!("Failed to execute {}: {}", binary, e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success() {
        return Err(format!("Command failed: {}", stderr));
    }

    info!("  Filter list targets output: {} bytes", stdout.len());

    // 解析 JSON 响应
    let result: serde_json::Value = serde_json::from_str(&stdout)
        .map_err(|e| format!("Failed to parse JSON: {}", e))?;

    Ok(result)
}

/// 检查文件是否存在
pub fn check_file_exists(file_path: &str) -> Result<bool, String> {
    let exists = std::path::Path::new(file_path).exists();
    info!("  Check file exists: {} -> {}", file_path, exists);
    Ok(exists)
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
