cat > /usr/local/bin/sbox <<'EOF'
#!/bin/bash

# ============================================
# SBox 代理管理面板 (Hysteria2 / TUIC / AnyTLS)
# Version: v1.0.0
# ============================================

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
BLUE="\033[34m"
RESET="\033[0m"

SCRIPT_VERSION="v1.0.0"
SCRIPT_URL="https://raw.githubusercontent.com/lijboys/SSHTools/main/sbox.sh"

SB_BIN="/usr/local/bin/sing-box"
SB_VER="1.11.7"
CONF_DIR="/etc/sbox"
HY2_CONF="${CONF_DIR}/hy2.json"
TUIC_CONF="${CONF_DIR}/tuic.json"
ANYTLS_CONF="${CONF_DIR}/anytls.json"
CERT_DIR="${CONF_DIR}/certs"
LOG_DIR="/var/log/sbox"

HY2_SVC="sbox-hy2"
TUIC_SVC="sbox-tuic"
ANYTLS_SVC="sbox-anytls"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行！${RESET}"
    exit 1
fi

mkdir -p "$CONF_DIR" "$CERT_DIR" "$LOG_DIR"

pause() { read -p "按回车键返回主菜单..."; }

is_valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

is_port_in_use() {
    local port=$1
    if command -v ss >/dev/null 2>&1; then
        ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"
    else
        return 1
    fi
}

get_public_ip() {
    local ip_type="${1:-4}" ip=""
    if [ "$ip_type" = "6" ]; then
        ip=$(curl -s6m3 ipv6.icanhazip.com 2>/dev/null)
        [ -z "$ip" ] && ip=$(curl -s6m3 api6.ipify.org 2>/dev/null)
        [ -z "$ip" ] && ip=$(curl -s6m3 ifconfig.co 2>/dev/null)
    else
        ip=$(curl -s4m3 ipv4.icanhazip.com 2>/dev/null)
        [ -z "$ip" ] && ip=$(curl -s4m3 api.ipify.org 2>/dev/null)
        [ -z "$ip" ] && ip=$(curl -s4m3 ifconfig.me 2>/dev/null)
    fi
    echo "$ip"
}

cached_ip4="" cached_ip6="" cached_ts=0
get_ip_cached() {
    local now=$(date +%s)
    local age=$(( now - cached_ts ))
    if [ $age -gt 300 ] || [ -z "$cached_ip4" ]; then
        cached_ip4=$(get_public_ip 4)
        cached_ip6=$(get_public_ip 6)
        cached_ts=$now
    fi
    [ "$1" = "6" ] && echo "$cached_ip6" || echo "$cached_ip4"
}

is_valid_ipv4() {
    local ip=$1
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r a b c d <<< "$ip"
    for x in "$a" "$b" "$c" "$d"; do
        [[ "$x" =~ ^[0-9]+$ ]] || return 1
        [ "$x" -ge 0 ] && [ "$x" -le 255 ] || return 1
    done
    return 0
}

is_valid_ipv6() {
    local ip=$1
    [[ "$ip" =~ : ]] || return 1
    [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]] || return 1
    return 0
}

is_valid_domain() { [[ "$1" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; }

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *) echo "unsupported" ;;
    esac
}

mem_warn() {
    local m=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    local s=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')
    if [ -n "$m" ] && [ "$m" -le 256 ]; then
        echo ""
        echo -e "${RED}╔══════════════════════════════════════╗${RESET}"
        echo -e "${RED}║  ⚠ 当前内存: ${m}MB  |  Swap: ${s:-0}MB          ║${RESET}"
        echo -e "${RED}║  低配机器强烈建议先开 Swap 再装！   ║${RESET}"
        echo -e "${RED}║  主控菜单 → 12. Swap 管理           ║${RESET}"
        echo -e "${RED}╚══════════════════════════════════════╝${RESET}"
        [ ${s:-0} -lt 128 ] && echo -e "${YELLOW}当前 Swap 不足128MB，编译可能 OOM${RESET}"
        read -p "确认继续？[y/N]: " go
        [[ "$go" != "y" && "$go" != "Y" ]] && return 1
    fi
    return 0
}

disk_check() {
    local avail=$(df -m /tmp 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "$avail" ] && [ "$avail" -lt 100 ]; then
        echo -e "${RED}⚠ /tmp 可用空间仅 ${avail}MB，安装可能失败${RESET}"
        read -p "仍继续？[y/N]: " go
        [[ "$go" != "y" && "$go" != "Y" ]] && return 1
    fi
    return 0
}

# ==================== sing-box 核心安装 ====================

install_sb_core() {
    [ -x "$SB_BIN" ] && { "$SB_BIN" version >/dev/null 2>&1 && return 0; }

    disk_check || return 1

    local arch=$(detect_arch)
    [ "$arch" = "unsupported" ] && { echo -e "${RED}❌ 不支持的架构: $(uname -m)${RESET}"; return 1; }

    local dl_url="https://github.com/SagerNet/sing-box/releases/download/v${SB_VER}/sing-box-${SB_VER}-linux-${arch}.tar.gz"
    local tmp=$(mktemp -d)

    echo -e "${YELLOW}下载 sing-box v${SB_VER} (${arch})...${RESET}"
    curl -fL --connect-timeout 20 -o "${tmp}/sb.tar.gz" "$dl_url" || {
        echo -e "${RED}❌ 下载失败: $dl_url${RESET}"
        rm -rf "$tmp"; return 1
    }

    tar -zxf "${tmp}/sb.tar.gz" -C "$tmp" || { rm -rf "$tmp"; return 1; }
    local bin=$(find "$tmp" -type f -name sing-box | head -n1)
    [ -z "$bin" ] && { rm -rf "$tmp"; return 1; }

    install -m 755 "$bin" "$SB_BIN"
    rm -rf "$tmp"

    "$SB_BIN" version >/dev/null 2>&1 || return 1
    echo -e "${GREEN}✅ sing-box 核心安装完成${RESET}"
    return 0
}

gen_self_cert() {
    local domain="${1:-sbox.local}"
    local key="${CERT_DIR}/server.key"
    local cert="${CERT_DIR}/server.crt"
    if [ -f "$key" ] && [ -f "$cert" ]; then
        return 0
    fi
    openssl req -x509 -newkey rsa:2048 -keyout "$key" -out "$cert" \
        -days 3650 -nodes -subj "/CN=${domain}" >/dev/null 2>&1
    chmod 600 "$key" "$cert"
}

get_service_status() {
    local svc=$1
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "${GREEN}运行中${RESET}"
    elif systemctl list-unit-files 2>/dev/null | grep -q "^${svc}"; then
        echo -e "${RED}已停止${RESET}"
    else
        echo -e "${YELLOW}未安装${RESET}"
    fi
}

# ==================== Hysteria2 ====================

install_hy2() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "      🚀 部署 Hysteria2"
    echo -e "${CYAN}=========================================${RESET}"
    mem_warn || { pause; return; }

    install_sb_core || { pause; return; }
    gen_self_cert

    echo ""
    echo -e "${YELLOW}💡 推荐使用 443 或 8443 端口${RESET}"
    while true; do
        read -rp "👉 监听端口 (回车默认 443, q 取消): " port
        port=${port:-443}
        [[ "$port" = "q" ]] && { pause; return; }
        if ! is_valid_port "$port"; then
            echo -e "${RED}❌ 端口无效！${RESET}"
        elif is_port_in_use "$port"; then
            echo -e "${RED}❌ 端口 ${port} 已被占用！${RESET}"
        else
            break
        fi
    done

    read -rp "👉 密码 (回车随机16位): " pass
    [ -z "$pass" ] && pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)

    echo ""
    echo -e "${CYAN}--- 伪装域名 (sni) ---${RESET}"
    echo -e "  ${GREEN}1.${RESET} www.bing.com ${YELLOW}(默认)${RESET}"
    echo -e "  ${GREEN}2.${RESET} www.microsoft.com"
    echo -e "  ${GREEN}3.${RESET} 自定义"
    read -rp "选择: " sni_c
    case "$sni_c" in
        2) sni="www.microsoft.com" ;;
        3) read -rp "输入 sni 域名: " sni; [ -z "$sni" ] && sni="www.bing.com" ;;
        *) sni="www.bing.com" ;;
    esac

    cat > "$HY2_CONF" <<EOF
{
  "log": {"level": "warn", "output": "${LOG_DIR}/hy2.log"},
  "inbounds": [{
    "type": "hysteria2",
    "tag": "hy2-in",
    "listen": "::",
    "listen_port": ${port},
    "up_mbps": 100,
    "down_mbps": 100,
    "users": [{"password": "${pass}"}],
    "tls": {
      "enabled": true,
      "certificate_path": "${CERT_DIR}/server.crt",
      "key_path": "${CERT_DIR}/server.key"
    },
    "masquerade": "https://${sni}"
  }]
}
EOF

    create_service "$HY2_SVC" "Hysteria2" "$HY2_CONF"
    restart_svc "$HY2_SVC"

    local ip=$(get_public_ip 4)
    [ -z "$ip" ] && ip=$(get_public_ip 6)
    [ -z "$ip" ] && ip="服务器IP"

    echo -e "\n${GREEN}✅ Hysteria2 部署完成！${RESET}"
    echo -e "状态: $(get_service_status $HY2_SVC)"
    echo -e "${CYAN}连接参数:${RESET}"
    echo -e "  地址: ${YELLOW}${ip}:${port}${RESET}"
    echo -e "  密码: ${YELLOW}${pass}${RESET}"
    echo -e "  传输: ${YELLOW}hysteria2${RESET}"
    pause
}

# ==================== TUIC ====================

install_tuic() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "        🚀 部署 TUIC v5"
    echo -e "${CYAN}=========================================${RESET}"
    mem_warn || { pause; return; }

    install_sb_core || { pause; return; }
    gen_self_cert

    echo ""
    while true; do
        read -rp "👉 监听端口 (回车默认 8443, q 取消): " port
        port=${port:-8443}
        [[ "$port" = "q" ]] && { pause; return; }
        if ! is_valid_port "$port"; then
            echo -e "${RED}❌ 端口无效！${RESET}"
        elif is_port_in_use "$port"; then
            echo -e "${RED}❌ 端口 ${port} 已被占用！${RESET}"
        else
            break
        fi
    done

    read -rp "👉 UUID (回车随机生成): " uuid
    [ -z "$uuid" ] && uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(tr -dc A-F0-9 </dev/urandom | head -c8)-$(tr -dc A-F0-9 </dev/urandom | head -c4)-4$(tr -dc A-F0-9 </dev/urandom | head -c3)-$(tr -dc A-F0-9 </dev/urandom | head -c4)-$(tr -dc A-F0-9 </dev/urandom | head -c12)")

    read -rp "👉 密码 (回车随机12位): " pass
    [ -z "$pass" ] && pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)

    cat > "$TUIC_CONF" <<EOF
{
  "log": {"level": "warn", "output": "${LOG_DIR}/tuic.log"},
  "inbounds": [{
    "type": "tuic",
    "tag": "tuic-in",
    "listen": "::",
    "listen_port": ${port},
    "users": [{"uuid": "${uuid}", "password": "${pass}"}],
    "congestion_control": "bbr",
    "tls": {
      "enabled": true,
      "certificate_path": "${CERT_DIR}/server.crt",
      "key_path": "${CERT_DIR}/server.key"
    }
  }]
}
EOF

    create_service "$TUIC_SVC" "TUIC v5" "$TUIC_CONF"
    restart_svc "$TUIC_SVC"

    local ip=$(get_public_ip 4)
    [ -z "$ip" ] && ip=$(get_public_ip 6)
    [ -z "$ip" ] && ip="服务器IP"

    echo -e "\n${GREEN}✅ TUIC 部署完成！${RESET}"
    echo -e "状态: $(get_service_status $TUIC_SVC)"
    echo -e "${CYAN}连接参数:${RESET}"
    echo -e "  地址: ${YELLOW}${ip}:${port}${RESET}"
    echo -e "  UUID: ${YELLOW}${uuid}${RESET}"
    echo -e "  密码: ${YELLOW}${pass}${RESET}"
    echo -e "  传输: ${YELLOW}tuic v5${RESET}"
    pause
}

# ==================== AnyTLS ====================

install_anytls() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "        🚀 部署 AnyTLS"
    echo -e "${CYAN}=========================================${RESET}"
    mem_warn || { pause; return; }

    install_sb_core || { pause; return; }
    gen_self_cert

    echo ""
    while true; do
        read -rp "👉 监听端口 (回车默认 9443, q 取消): " port
        port=${port:-9443}
        [[ "$port" = "q" ]] && { pause; return; }
        if ! is_valid_port "$port"; then
            echo -e "${RED}❌ 端口无效！${RESET}"
        elif is_port_in_use "$port"; then
            echo -e "${RED}❌ 端口 ${port} 已被占用！${RESET}"
        else
            break
        fi
    done

    read -rp "👉 密码 (回车随机12位): " pass
    [ -z "$pass" ] && pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)

    echo ""
    echo -e "${CYAN}--- 填充网站 (伪装) ---${RESET}"
    echo -e "  ${GREEN}1.${RESET} www.bing.com ${YELLOW}(默认)${RESET}"
    echo -e "  ${GREEN}2.${RESET} www.microsoft.com"
    echo -e "  ${GREEN}3.${RESET} 自定义"
    read -rp "选择: " pad_c
    case "$pad_c" in
        2) pad="www.microsoft.com" ;;
        3) read -rp "输入填充域名: " pad; [ -z "$pad" ] && pad="www.bing.com" ;;
        *) pad="www.bing.com" ;;
    esac

    cat > "$ANYTLS_CONF" <<EOF
{
  "log": {"level": "warn", "output": "${LOG_DIR}/anytls.log"},
  "inbounds": [{
    "type": "shadowtls",
    "tag": "anytls-in",
    "listen": "::",
    "listen_port": ${port},
    "version": 3,
    "users": [{"password": "${pass}"}],
    "handshake": {
      "server": "${pad}",
      "server_port": 443
    },
    "strict_mode": true
  }]
}
EOF

    create_service "$ANYTLS_SVC" "AnyTLS" "$ANYTLS_CONF"
    restart_svc "$ANYTLS_SVC"

    local ip=$(get_public_ip 4)
    [ -z "$ip" ] && ip=$(get_public_ip 6)
    [ -z "$ip" ] && ip="服务器IP"

    echo -e "\n${GREEN}✅ AnyTLS 部署完成！${RESET}"
    echo -e "状态: $(get_service_status $ANYTLS_SVC)"
    echo -e "${CYAN}连接参数:${RESET}"
    echo -e "  地址: ${YELLOW}${ip}:${port}${RESET}"
    echo -e "  密码: ${YELLOW}${pass}${RESET}"
    echo -e "  传输: ${YELLOW}anytls(shadowtls v3)${RESET}"
    pause
}

# ==================== 服务管理 ====================

create_service() {
    local svc="$1" desc="$2" conf="$3"
    cat > "/etc/systemd/system/${svc}.service" <<SVCEOF
[Unit]
Description=${desc} (sing-box)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SB_BIN} run -c ${conf}
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
}

restart_svc() {
    local svc="$1"
    systemctl enable "$svc" >/dev/null 2>&1
    systemctl restart "$svc" >/dev/null 2>&1
    sleep 1
    systemctl is-active --quiet "$svc"
}

svc_ctl_all() {
    local action="$1"
    for svc in "$HY2_SVC" "$TUIC_SVC" "$ANYTLS_SVC"; do
        systemctl list-unit-files 2>/dev/null | grep -q "^${svc}" && systemctl "$action" "$svc" 2>/dev/null || true
    done
}

# ==================== 卸载 ====================

uninstall_svc() {
    local svc="$1" conf="$2"
    systemctl stop "$svc" 2>/dev/null
    systemctl disable "$svc" 2>/dev/null
    rm -f "/etc/systemd/system/${svc}.service"
    rm -f "$conf"
    systemctl daemon-reload 2>/dev/null
}

uninstall_menu() {
    clear
    echo -e "${RED}--- 卸载选项 ---${RESET}"
    echo ""
    echo -e "  ${GREEN}1.${RESET} 卸载 Hysteria2"
    echo -e "  ${GREEN}2.${RESET} 卸载 TUIC"
    echo -e "  ${GREEN}3.${RESET} 卸载 AnyTLS"
    echo -e "  ${RED}9.${RESET} 彻底卸载全部 (含 sing-box 核心 + 面板)"
    echo -e "  ${GREEN}0.${RESET} 返回"
    read -p "选择: " un_c

    case "$un_c" in
        1) uninstall_svc "$HY2_SVC" "$HY2_CONF"; echo -e "${GREEN}Hysteria2 已卸载${RESET}" ;;
        2) uninstall_svc "$TUIC_SVC" "$TUIC_CONF"; echo -e "${GREEN}TUIC 已卸载${RESET}" ;;
        3) uninstall_svc "$ANYTLS_SVC" "$ANYTLS_CONF"; echo -e "${GREEN}AnyTLS 已卸载${RESET}" ;;
        9)
            echo -e "${RED}彻底清理中...${RESET}"
            for svc in "$HY2_SVC" "$TUIC_SVC" "$ANYTLS_SVC"; do
                uninstall_svc "$svc" "${CONF_DIR}"
            done
            rm -rf "$CONF_DIR" "$LOG_DIR"
            rm -f "$SB_BIN" /usr/local/bin/sbox
            echo -e "${GREEN}全部卸载完成${RESET}"
            exit 0
            ;;
    esac
    sleep 1
}

# ==================== 日志 ====================

view_logs() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "             📜 SBox 运行日志"
    echo -e "${CYAN}=========================================${RESET}"

    local any=""
    for svc in "$HY2_SVC" "$TUIC_SVC" "$ANYTLS_SVC"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}"; then
            any="1"
            echo -e "\n${YELLOW}--- ${svc} (最近30行) ---${RESET}"
            journalctl -u "$svc" --no-pager -n 30 2>/dev/null || echo "暂无日志"
        fi
    done
    [ -z "$any" ] && echo "未安装任何服务"

    echo -e "${CYAN}=========================================${RESET}"
    pause
}

# ==================== 面板更新 ====================

update_script() {
    clear
    echo -e "${YELLOW}正在从 GitHub 拉取最新面板代码...${RESET}"
    local tmp_file=$(mktemp)
    if curl -fsSL --connect-timeout 10 "${SCRIPT_URL}" -o "$tmp_file" 2>/dev/null; then
        sed -i 's/\r$//' "$tmp_file"
        if bash -n "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" /usr/local/bin/sbox
            chmod +x /usr/local/bin/sbox
            echo -e "${GREEN}✅ 面板更新完成！正在重启...${RESET}"
            sleep 1
            exec /usr/local/bin/sbox 2>/dev/null || {
                echo -e "${YELLOW}⚠ auto-restart 失败，请手动输入 sbox${RESET}"
                exit 0
            }
        else
            rm -f "$tmp_file"
            echo -e "${RED}❌ 新脚本语法校验失败${RESET}"
            pause
        fi
    else
        rm -f "$tmp_file"
        echo -e "${RED}❌ 下载失败${RESET}"
        pause
    fi
}

# ==================== 主循环 ====================

while true; do
    clear

    local ipv4=$(get_ip_cached 4)
    local ipv6=$(get_ip_cached 6)

    echo -e "${CYAN}══════════════════════════════════════${RESET}"
    echo -e "  ${GREEN}░ SBox 代理面板${RESET}  ${YELLOW}${SCRIPT_VERSION}${RESET}"
    echo -e "${CYAN}══════════════════════════════════════${RESET}"
    echo -ne "核心: "
    if [ -x "$SB_BIN" ]; then
        echo -ne "${GREEN}sing-box v${SB_VER}${RESET}  "
    else
        echo -ne "${YELLOW}未安装${RESET}  "
    fi
    [ -n "$ipv4" ] && echo -ne "IPv4:${GREEN}${ipv4}${RESET}  "
    [ -n "$ipv6" ] && echo -ne "IPv6:${GREEN}${ipv6}${RESET}"
    echo ""

    local mem_cur=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    local swap_cur=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')
    if [ -n "$mem_cur" ] && [ "$mem_cur" -le 256 ] && [ "${swap_cur:-0}" -lt 128 ]; then
        echo -e "${RED}⚠ 内存 ${mem_cur}MB | Swap ${swap_cur:-0}MB — 装前建议加Swap！${RESET}"
    fi

    echo -e " ${YELLOW}▸ 安装状态${RESET}"
    echo -ne "  ${CYAN}Hysteria2${RESET}: $(get_service_status $HY2_SVC)  "
    echo -ne "${CYAN}TUIC${RESET}: $(get_service_status $TUIC_SVC)  "
    echo -e  "${CYAN}AnyTLS${RESET}: $(get_service_status $ANYTLS_SVC)"

    echo -e " ${GREEN}▸ 部署${RESET}"
    echo -e "  ${GREEN}1.${RESET} Hysteria2  (高性能 UDP, ~40MB)"
    echo -e "  ${GREEN}2.${RESET} TUIC v5     (轻量 UDP, ~30MB)"
    echo -e "  ${GREEN}3.${RESET} AnyTLS      (最轻量 TLS, ~25MB)"
    echo -e " ${YELLOW}▸ 控制${RESET}"
    echo -e "  ${GREEN}4.${RESET} 启动全部      ${RED}5.${RESET} 停止全部"
    echo -e "  ${CYAN}6.${RESET} 重启全部      ${CYAN}7.${RESET} 查看日志"
    echo -e " ${BLUE}▸ 维护${RESET}"
    echo -e "  ${BLUE}8.${RESET} 更新面板       ${RED}9.${RESET} 卸载服务"
    echo -e "  ${GREEN}0.${RESET} 退出            ${YELLOW}00.${RESET} 返回主菜单"
    echo -e "${CYAN}══════════════════════════════════════${RESET}"
    read -p "请输入序号选择功能: " choice

    case "$choice" in
        1) install_hy2 ;;
        2) install_tuic ;;
        3) install_anytls ;;
        4) svc_ctl_all start; echo -e "${GREEN}✅ 操作完成${RESET}"; sleep 1 ;;
        5) svc_ctl_all stop;  echo -e "${YELLOW}已停止${RESET}"; sleep 1 ;;
        6) svc_ctl_all restart; echo -e "${GREEN}✅ 已重启${RESET}"; sleep 1 ;;
        7) view_logs ;;
        8) update_script ;;
        9) uninstall_menu ;;
        0) clear; exit 0 ;;
        00) [ -f "/usr/local/bin/n" ] && exec /usr/local/bin/n || { echo -e "${RED}未安装主控！${RESET}"; sleep 2; } ;;
        *) echo -e "${RED}输入错误！${RESET}"; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/sbox
echo -e "\033[32m✅ SBox 面板已安装！\033[0m"
echo -e "\033[33m正在启动面板...\033[0m"
sleep 1
exec /usr/local/bin/sbox
