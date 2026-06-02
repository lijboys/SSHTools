# 🛠️ NooMili SSH工具箱

<div align="center">
  
[🦇 MTP 代理搭建教程](./MD/MTP.md) | [📊 Komari 探针部署教程](./MD/komari.md) | [📡 SBox 代理部署教程](./MD/sbox.md) | [☁️ CF Worker 短链搭建教程](./MD/cf.md)

</div>

## 🌟 简介

**NooMili工具箱** (v2.6.0) 是一款全能的服务器主控面板，**全面兼容独立 VPS 与海外廉价 NAT 小鸡（Alpine/LXC 架构）**。内置 MTP 代理、Komari 探针、SOCKS5 代理的一键部署管理，以及 BBR 加速、Swap 虚拟内存、SSH 安全加固、Lucky Web SSL 面板等实用工具，是管理所有小鸡的绝佳瑞士军刀。

## 🚀 一键极速部署指令（四选一）

安装主控面板后，即可在内部自由调用各项功能。

### 方案 A：Cloudflare 自定义短域名 (极简推荐)
如果你拥有自己的域名，利用 CF 网页版搭建专属的极简短链（完美防墙，全球极速秒连！）：
```
bash <(curl -fsSL vvvps.qzz.io)
```

👉 **[点击查看：CF Worker 极简短链搭建教程](https://github.com/lijboys/SSHTools/blob/main/MD/cf.md)**

### 方案 B：免费短链白嫖（免域名、极简指令）

利用免费短链服务，无需自己购买域名（如使用 `is.gd` 短链）：

```bash
bash <(curl -Ls is.gd/你的自定义后缀)
```

### 方案 C：直写系统命令（简单粗暴，推荐极简系统）

直接将脚本下载为系统全局命令并瞬间唤醒面板（适合未安装 curl 的纯净系统）：

```bash
wget -O /usr/local/bin/n [https://raw.githubusercontent.com/lijboys/SSHTools/main/NooMili.sh](https://raw.githubusercontent.com/lijboys/SSHTools/main/NooMili.sh) && chmod +x /usr/local/bin/n && n
```

### 方案 D：经典拉取执行

传统的 GitHub Raw 裸脚本部署方法：

```bash
bash <(curl -fsSL [https://raw.githubusercontent.com/lijboys/SSHTools/main/NooMili.sh](https://raw.githubusercontent.com/lijboys/SSHTools/main/NooMili.sh))
```

-----

## 🛠️ 后续日常管理 (常驻快捷键)

首次安装完成后，无论何时登录你的机器，只需要在 SSH 敲入以下一个字母并回车，即可瞬间唤醒管理面板：

```bash
n
```

**主控面板核心功能：**

| 菜单 | 功能 | 说明 |
|:--:|------|------|
| 1-4 | **系统基础运维** | 系统信息看板、一键系统更新、垃圾清理、NAT 信息卡 |
| 5-8,15 | **子模块管理** | MTP 代理面板、Komari 探针面板、SOCKS5 面板、Lucky SSL 面板、SBox 代理面板(hy2/tuic/anytls) |
| 9-10 | **外部精选合集** | 老王一键工具箱、科技lion一键脚本 |
| 11-14 | **系统增强** | BBR 网络加速、Swap 虚拟内存管理、SSH 安全加固、进程保活巡检 |
| u | **热更新** | 从 GitHub 同步主控最新代码 |
| x | **卸载** | 彻底卸载全部组件 / 仅卸载主控 |

> **💡 128MB 小内存机器提示：** 安装服务前建议先用 `12. Swap 管理` 添加虚拟内存；`14. 进程保活` 可安装 cron 巡检，服务 OOM 崩溃后 5 分钟内自动拉起。

> **⚠️ 常见问题说明：**
> 若运行指令时提示找不到 `curl` 或 `wget`，请先根据你的系统执行安装：
>
>   * Ubuntu/Debian：`apt-get install -y curl wget`
>   * Alpine：`apk add curl wget bash`
>   * Fedora：`dnf install -y curl wget`
>   * CentOS/Rocky/Oracle等：`yum install -y curl wget`
