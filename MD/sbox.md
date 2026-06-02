# 📡 SSHTools - SBox 代理部署教程

[⬅️ 返回 NooMili 工具箱主页](../README.md)

## 🌟 简介

SBox 面板统一管理三款基于 **sing-box** 核心的现代代理协议：**Hysteria2**、**TUIC v5**、**AnyTLS**。全程自建部署，不依赖任何第三方安装脚本，核心二进制直连 GitHub 官方仓库。

| 协议 | 类型 | 规模 | 适用场景 |
|------|------|:--:|------|
| **Hysteria2** | UDP/QUIC | ~40MB | 高延迟跨国线路，抗丢包强 |
| **TUIC v5** | UDP/TLS | ~30MB | 平衡型，延迟与吞吐均衡 |
| **AnyTLS** | TLS 填充 | ~25MB | 最轻量，低配机器首选 |

> **💡 128MB 小内存机器：** 面板启动时会自动检测内存和 Swap，不足时红色提示。建议安装前先通过主控 `12. Swap 管理` 添加至少 256MB Swap。

## 🚀 启动方式

已安装 NooMili 主控时，两种方式唤醒：
1. 终端输入 `n` 打开主菜单，选择 **[15] SBox 代理**
2. 或在终端直接输入快捷指令：
   ```bash
   sbox
   ```

*(单独安装指令：)*
```bash
wget -O /usr/local/bin/sbox https://raw.githubusercontent.com/lijboys/SSHTools/main/sbox.sh && chmod +x /usr/local/bin/sbox && sbox
```

## 🛠️ 核心功能

### 1. 三协议一键部署
选择对应协议 → 输入端口和密码 → 自动下载 sing-box 核心 → 生成配置 → 创建 systemd 服务并启动。全程约 30 秒。

### 2. 自签证书自动生成
安装时自动生成 10 年有效期自签 TLS 证书，无需域名和公网 CA。如需真实证书可自行替换 `/etc/sbox/certs/` 下的文件后重启服务。

### 3. 伪装域名 (sni)
Hysteria2 和 AnyTLS 支持设置伪装 sni（如 `www.bing.com`），使流量看起来像普通 HTTPS，增强隐蔽性。

### 4. 内存保护
- 安装前弹红框显式确认（显示当前内存 + Swap）
- `/tmp` 空间不足 100MB 时告警
- 所有 systemd 服务均配置 `Restart=always`，OOM 崩溃 5 秒内自动拉起

### 5. 面板功能清单

| 菜单 | 功能 |
|:--:|------|
| 1-3 | 安装 Hysteria2 / TUIC / AnyTLS |
| 4-5 | 启动/停止全部已安装服务 |
| 6-7 | 重启全部 / 查看日志 |
| 8 | 更新面板代码 |
| 9 | 卸载服务（可按协议单独卸载或全部清除） |
| 00 | 返回 NooMili 主控 |

## 🔗 客户端推荐

| 协议 | iOS | Android | Windows/macOS |
|------|-----|---------|---------------|
| Hysteria2 | Shadowrocket / Stash | v2rayNG / NekoBox | Hysteria 官方客户端 |
| TUIC v5 | Stash (需配置) | v2rayNG | sing-box / clash meta |
| AnyTLS | Shadowrocket | NekoBox | sing-box |
