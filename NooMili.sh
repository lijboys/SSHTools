cat > /usr/local/bin/n <<'EOF'
#!/bin/bash

# ============================================
# SSHTools 工具箱 - NAT/VPS 多功能管理面板
# Version: v2.6.0

SCRIPT_VERSION="v2.6.0"

NAT_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/NooMili.sh"
MTP_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/mtp.sh"
KOMARI_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/komari.sh"
SOCKS5_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/s5.sh"
SBOX_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/sbox.sh"

IP_FILE="/etc/.noomili_ip"
IP_TYPE_FILE="/etc/.noomili_ip_type"
PORTS_FILE="/etc/.noomili_ports"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行！${RESET}"
    exit 1
fi

pause() {
    read -p "按回车键返回主菜单..."
}

get_public_ip() {
    local ip_type=$1
    local sources=()

    if [ "$ip_type" = "6" ]; then
        sources=("ipv6.icanhazip.com" "api6.ipify.org" "ifconfig.co")
        for src in "${sources[@]}"; do
            local result
            result=$(curl -s6m3 --connect-timeout 3 "$src" 2>/dev/null)
            if [ -n "$result" ] && [[ "$result" =~ ^[0-9a-fA-F:]+$ ]]; then
                echo "$result"
                return 0
            fi
        done
    else
        sources=("ipv4.icanhazip.com" "api.ipify.org" "ifconfig.me")
        for src in "${sources[@]}"; do
            local result
            result=$(curl -s4m3 --connect-timeout 3 "$src" 2>/dev/null)
            if [ -n "$result" ] && [[ "$result" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "$result"
                return 0
            fi
        done
    fi
    return 1
}

install_shortcut() {
    if [ ! -f "/usr/local/bin/n" ]; then
        if curl -fsSL --connect-timeout 10 "${NAT_URL}" -o /usr/local/bin/n 2>/dev/null; then
            chmod +x /usr/local/bin/n
        elif [ -f "$0" ] && [ "$0" != "bash" ] && [ "$0" != "-bash" ]; then
            cp -f "$0" /usr/local/bin/n && chmod +x /usr/local/bin/n
        fi
    fi
}
install_shortcut

show_sys_info() {
    clear
    echo -e "${CYAN}====================================================${RESET}"
    echo -e "                 🖥️  系统核心信息看板"
    echo -e "${CYAN}====================================================${RESET}"
    echo -e "${YELLOW}正在探测各项硬件与网络指标，请稍候...${RESET}"

    OS_NAME=$(grep -w "PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    [ -z "$OS_NAME" ] && OS_NAME="Unknown OS"
    KERNEL_VER=$(uname -r)
    ARCH=$(uname -m)
    UPTIME=$(uptime -p 2>/dev/null | sed 's/up //')
    [ -z "$UPTIME" ] && UPTIME=$(uptime | awk -F'( |,|:)+' '{print $6,$7",",$8,"hours,",$9,"minutes"}')
    LOAD_AVG=$(awk '{print $1, $2, $3}' /proc/loadavg)

    if command -v systemd-detect-virt >/dev/null 2>&1; then
        VIRT_TYPE=$(systemd-detect-virt 2>/dev/null)
        [ -z "$VIRT_TYPE" ] && VIRT_TYPE="none"
    else
        VIRT_TYPE="未知"
    fi

    CPU_MODEL=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)
    CPU_CORES=$(nproc)
    [ -z "$CPU_MODEL" ] && CPU_MODEL="Virtual CPU (未识别)"

    MEM_INFO=$(free -m | grep Mem)
    MEM_TOTAL=$(echo "$MEM_INFO" | awk '{print $2}')
    MEM_USED=$(echo "$MEM_INFO" | awk '{print $3}')
    if [ "$MEM_TOTAL" -gt 0 ] 2>/dev/null; then
        MEM_PERCENT=$(awk "BEGIN {printf \"%.1f\", $MEM_USED/$MEM_TOTAL*100}")
    else
        MEM_PERCENT="0.0"
    fi

    SWAP_INFO=$(free -m | grep Swap)
    SWAP_TOTAL=$(echo "$SWAP_INFO" | awk '{print $2}')
    SWAP_USED=$(echo "$SWAP_INFO" | awk '{print $3}')

    DISK_INFO=$(df -h / | tail -n 1)
    DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
    DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
    DISK_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}')

    LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
    [ -z "$LOCAL_IP" ] && LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$LOCAL_IP" ] && LOCAL_IP="未分配"

    AUTO_IPV4=$(get_public_ip 4)
    AUTO_IPV6=$(get_public_ip 6)

    if [ -f "$IP_FILE" ]; then
        SAVED_IP=$(cat "$IP_FILE")
        SAVED_TYPE=$(cat "$IP_TYPE_FILE" 2>/dev/null || echo "4")
    else
        SAVED_IP=""
        SAVED_TYPE=""
    fi

    if [ -n "$AUTO_IPV4" ]; then
        DISPLAY_IPV4="$AUTO_IPV4 ${RED}(自动识别)${RESET}"
    else
        DISPLAY_IPV4="${RED}获取失败${RESET}"
    fi

    if [ -n "$AUTO_IPV6" ]; then
        DISPLAY_IPV6="$AUTO_IPV6 ${RED}(自动识别)${RESET}"
    else
        DISPLAY_IPV6="未分配或无 IPv6"
    fi

    if [ -n "$SAVED_IP" ]; then
        if [ "$SAVED_TYPE" = "6" ]; then
            DISPLAY_IPV6="${GREEN}${SAVED_IP}${RESET} ${YELLOW}(手动校准)${RESET}"
        else
            DISPLAY_IPV4="${GREEN}${SAVED_IP}${RESET} ${YELLOW}(手动校准)${RESET}"
        fi
    fi

    if [ -f "$PORTS_FILE" ]; then
        NAT_PORTS=$(cat "$PORTS_FILE")
    else
        NAT_PORTS="${YELLOW}未设置 (按 p 设置)${RESET}"
    fi

    NET_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    TRAFFIC_INFO=""
    if [ -n "$NET_IFACE" ] && [ -d "/sys/class/net/$NET_IFACE" ]; then
        RX_BYTES=$(cat /sys/class/net/$NET_IFACE/statistics/rx_bytes 2>/dev/null)
        TX_BYTES=$(cat /sys/class/net/$NET_IFACE/statistics/tx_bytes 2>/dev/null)
        if [ -n "$RX_BYTES" ] && [ -n "$TX_BYTES" ]; then
            RX_GB=$(awk "BEGIN {printf \"%.2f\", $RX_BYTES/1024/1024/1024}")
            TX_GB=$(awk "BEGIN {printf \"%.2f\", $TX_BYTES/1024/1024/1024}")
            TRAFFIC_INFO="↓${RX_GB}GB ↑${TX_GB}GB"
        fi
    fi

    clear
    echo -e "${CYAN}====================================================${RESET}"
    echo -e " 💻 ${GREEN}系统 OS:${RESET}    $OS_NAME ($ARCH)"
    echo -e " ⚙️  ${GREEN}系统内核:${RESET}  $KERNEL_VER"
    echo -e " 🎭 ${GREEN}虚拟类型:${RESET}  $VIRT_TYPE"
    echo -e " ⏱️  ${GREEN}在线时间:${RESET}  $UPTIME"
    echo -e " 📈 ${GREEN}系统负载:${RESET}  $LOAD_AVG ${YELLOW}(1/5/15分)${RESET}"
    echo -e "${CYAN}----------------------------------------------------${RESET}"
    echo -e " 🧠 ${GREEN}CPU 核心:${RESET}  $CPU_CORES Core(s)"
    echo -e " 🧠 ${GREEN}CPU 型号:${RESET}  $CPU_MODEL"
    echo -e " 📦 ${GREEN}内存占用:${RESET}  ${YELLOW}${MEM_USED}MB${RESET} / ${MEM_TOTAL}MB (${MEM_PERCENT}%)"
    echo -e " 💾 ${GREEN}Swap:${RESET}      ${SWAP_USED}MB / ${SWAP_TOTAL}MB"
    echo -e " 💽 ${GREEN}硬盘空间:${RESET}  ${YELLOW}${DISK_USED}${RESET} / ${DISK_TOTAL} (${DISK_PERCENT})"
    echo -e "${CYAN}----------------------------------------------------${RESET}"
    echo -e " 🌐 ${GREEN}内网 IPv4:${RESET} ${LOCAL_IP}"
    echo -e " 🌍 ${GREEN}公网 IPv4:${RESET} ${DISPLAY_IPV4}"
    echo -e " 🌍 ${GREEN}公网 IPv6:${RESET} ${YELLOW}${DISPLAY_IPV6}${RESET}"
    echo -e " 🔌 ${GREEN}NAT 端口:${RESET}  ${NAT_PORTS}"
    if [ -n "$TRAFFIC_INFO" ]; then
        echo -e " 📊 ${GREEN}流量统计:${RESET}  $TRAFFIC_INFO ${YELLOW}(自开机)${RESET}"
    fi
    echo -e "${CYAN}----------------------------------------------------${RESET}"
    echo -e "${YELLOW}提示: 自动识别 IP 不一定等于商家面板里的实际映射入口 IP${RESET}"
    echo -e "${CYAN}====================================================${RESET}"
    echo -e "${YELLOW}操作: [回车]返回 [c]校准IP [p]设置端口 [d]恢复自动${RESET}"
    read -p "请输入选择: " sub_choice

    case "$sub_choice" in
        c|C)
            echo ""
            echo -e "${CYAN}--- IP 类型选择 ---${RESET}"
            echo -e "  ${GREEN}1.${RESET} IPv4"
            echo -e "  ${GREEN}2.${RESET} IPv6"
            read -p "请选择 (回车默认 1): " ip_choice

            if [ "$ip_choice" = "2" ]; then
                read -p "👉 请输入控制面板看到的真实 IPv6: " user_ip
                if [[ "$user_ip" =~ ^[0-9a-fA-F:]+$ ]]; then
                    echo "$user_ip" > "$IP_FILE"
                    echo "6" > "$IP_TYPE_FILE"
                    echo -e "${GREEN}✅ IPv6 校准成功！已永久保存。${RESET}"
                    sleep 1
                    show_sys_info
                else
                    echo -e "${RED}❌ 格式错误！${RESET}"
                    sleep 2
                    show_sys_info
                fi
            else
                read -p "👉 请输入控制面板看到的真实 IPv4: " user_ip
                if [[ "$user_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    echo "$user_ip" > "$IP_FILE"
                    echo "4" > "$IP_TYPE_FILE"
                    echo -e "${GREEN}✅ IPv4 校准成功！已永久保存。${RESET}"
                    sleep 1
                    show_sys_info
                else
                    echo -e "${RED}❌ 格式错误！${RESET}"
                    sleep 2
                    show_sys_info
                fi
            fi
            ;;
        p|P)
            echo ""
            read -p "👉 请输入NAT端口范围 (如 10001-10020): " user_ports
            if [ -n "$user_ports" ]; then
                echo "$user_ports" > "$PORTS_FILE"
                echo -e "${GREEN}✅ 端口范围已保存！${RESET}"
                sleep 1
                show_sys_info
            else
                echo -e "${RED}❌ 输入为空！${RESET}"
                sleep 2
                show_sys_info
            fi
            ;;
        d|D)
            rm -f "$IP_FILE" "$IP_TYPE_FILE"
            echo -e "${YELLOW}已恢复自动获取 IP。${RESET}"
            sleep 1
            show_sys_info
            ;;
    esac
}

update_system() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "          🔄 正在执行全自动系统更新"
    echo -e "${CYAN}=========================================${RESET}"

    local mem_total
    mem_total=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    if [ -n "$mem_total" ] && [ "$mem_total" -le 256 ]; then
        echo -e "${RED}⚠️ 小内存(${mem_total}MB)更新可能触发 OOM！建议先开 Swap${RESET}"
        read -p "确定继续？[y/N]: " go_update
        [[ "$go_update" != "y" && "$go_update" != "Y" ]] && { return; }
    fi

    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get upgrade -y
    elif command -v dnf >/dev/null 2>&1; then
        dnf makecache
        dnf update -y
    elif command -v yum >/dev/null 2>&1; then
        yum makecache
        yum update -y
    elif command -v apk >/dev/null 2>&1; then
        apk update && apk upgrade
    else
        echo -e "${RED}未知的包管理器！请手动执行更新。${RESET}"
    fi

    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${GREEN}✅ 系统更新完毕！${RESET}"
    pause
}

clean_system() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "          🧹 开始深度系统瘦身清理"
    echo -e "${CYAN}=========================================${RESET}"

    SPACE_BEFORE=$(df / | tail -n 1 | awk '{print $3}')

    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-size=50M >/dev/null 2>&1
    fi

    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get autoremove -y >/dev/null 2>&1
        apt-get clean >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        dnf autoremove -y >/dev/null 2>&1
        dnf clean all >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum autoremove -y >/dev/null 2>&1
        yum clean all >/dev/null 2>&1
    fi

    find /tmp -type f -mmin +10 -delete 2>/dev/null
    find /var/tmp -type f -mmin +10 -delete 2>/dev/null

    SPACE_AFTER=$(df / | tail -n 1 | awk '{print $3}')
    FREED_KB=$((SPACE_BEFORE - SPACE_AFTER))

    echo -e "${CYAN}=========================================${RESET}"
    if [ "$FREED_KB" -le 0 ]; then
        echo -e "${GREEN}✅ 清理完成！系统已经很干净了~${RESET}"
    else
        FREED_MB=$(awk "BEGIN {printf \"%.2f\", $FREED_KB/1024}")
        echo -e "${GREEN}✅ 清理完成！释放了 ${YELLOW}${FREED_MB} MB${GREEN} 空间！${RESET}"
    fi
    pause
}

nat_info_card() {
    clear
    echo -e "${CYAN}====================================================${RESET}"
    echo -e "              📇 NAT 小鸡信息卡"
    echo -e "${CYAN}====================================================${RESET}"

    if [ -f "$IP_FILE" ]; then
        CARD_IP=$(cat "$IP_FILE")
        CARD_TYPE=$(cat "$IP_TYPE_FILE" 2>/dev/null || echo "4")
    else
        CARD_IPV4=$(get_public_ip 4)
        CARD_IPV6=$(get_public_ip 6)
        [ -z "$CARD_IPV4" ] && CARD_IPV4="N/A"
        [ -z "$CARD_IPV6" ] && CARD_IPV6="N/A"
    fi

    if [ -f "$PORTS_FILE" ]; then
        CARD_PORTS=$(cat "$PORTS_FILE")
    else
        CARD_PORTS="未设置"
    fi

    HOSTNAME_INFO=$(hostname)

    echo -e " 📛 ${GREEN}主机名:${RESET}    $HOSTNAME_INFO"
    if [ -f "$IP_FILE" ]; then
        if [ "$CARD_TYPE" = "6" ]; then
            echo -e " 🌍 ${GREEN}校准IPv6:${RESET}  $CARD_IP"
        else
            echo -e " 🌍 ${GREEN}校准IPv4:${RESET}  $CARD_IP"
        fi
    else
        echo -e " 🌍 ${GREEN}IPv4:${RESET}      $CARD_IPV4"
        echo -e " 🌍 ${GREEN}IPv6:${RESET}      $CARD_IPV6"
    fi
    echo -e " 🔌 ${GREEN}端口范围:${RESET}  $CARD_PORTS"
    echo -e "${CYAN}----------------------------------------------------${RESET}"
    echo -e "${YELLOW} 常用端口占用检测:${RESET}"

    for port in 22 80 443 8080; do
        if command -v ss >/dev/null 2>&1; then
            if ss -tlnp 2>/dev/null | grep -q ":$port "; then
                PROC=$(ss -tlnp 2>/dev/null | grep ":$port " | head -1 | grep -oP 'users:\(\("\K[^"]+' | head -1)
                echo -e "  端口 ${YELLOW}$port${RESET}: ${RED}已占用${RESET} ${CYAN}($PROC)${RESET}"
            else
                echo -e "  端口 ${YELLOW}$port${RESET}: ${GREEN}空闲${RESET}"
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
                PROC=$(netstat -tlnp 2>/dev/null | grep ":$port " | awk '{print $NF}' | head -1)
                echo -e "  端口 ${YELLOW}$port${RESET}: ${RED}已占用${RESET} ${CYAN}($PROC)${RESET}"
            else
                echo -e "  端口 ${YELLOW}$port${RESET}: ${GREEN}空闲${RESET}"
            fi
        else
            echo -e "  端口 ${YELLOW}$port${RESET}: ${YELLOW}无法检测${RESET}"
        fi
    done

    echo -e "${CYAN}====================================================${RESET}"
    pause
}

launch_mtp() {
    if [ ! -f "/usr/local/bin/mtp" ]; then
        echo -e "${YELLOW}首次进入，正在拉取 MTP 代理面板...${RESET}"
        local tmp_sh=$(mktemp)
        if curl -fsSL --connect-timeout 15 "${MTP_URL}" -o "$tmp_sh" 2>/dev/null; then
            bash "$tmp_sh"
            rm -f "$tmp_sh"
        else
            rm -f "$tmp_sh"
            echo -e "${RED}❌ 下载失败，请检查网络后重试！${RESET}"
            pause
        fi
    else
        /usr/local/bin/mtp
    fi
}

launch_komari() {
    if [ ! -f "/usr/local/bin/komari" ]; then
        echo -e "${YELLOW}首次进入，正在拉取 Komari 探针面板...${RESET}"
        local tmp_sh=$(mktemp)
        if curl -fsSL --connect-timeout 15 "${KOMARI_URL}" -o "$tmp_sh" 2>/dev/null; then
            bash "$tmp_sh"
            rm -f "$tmp_sh"
        else
            rm -f "$tmp_sh"
            echo -e "${RED}❌ 下载失败，请检查网络后重试！${RESET}"
            pause
        fi
    else
        /usr/local/bin/komari
    fi
}

launch_s5() {
    if [ ! -f "/usr/local/bin/s5" ]; then
        echo -e "${YELLOW}首次进入，正在拉取 SOCKS5 管理面板...${RESET}"
        local tmp_sh=$(mktemp)
        if curl -fsSL --connect-timeout 15 "${SOCKS5_URL}" -o "$tmp_sh" 2>/dev/null; then
            bash "$tmp_sh"
            rm -f "$tmp_sh"
        else
            rm -f "$tmp_sh"
            echo -e "${RED}❌ 下载失败，请检查网络后重试！${RESET}"
            pause
        fi
    else
        /usr/local/bin/s5
    fi
}

launch_sbox() {
    if [ ! -f "/usr/local/bin/sbox" ]; then
        echo -e "${YELLOW}首次进入，正在拉取 SBox 代理面板...${RESET}"
        local tmp_sh=$(mktemp)
        if curl -fsSL --connect-timeout 15 "${SBOX_URL}" -o "$tmp_sh" 2>/dev/null; then
            bash "$tmp_sh"
            rm -f "$tmp_sh"
        else
            rm -f "$tmp_sh"
            echo -e "${RED}❌ 下载失败，请检查网络后重试！${RESET}"
            pause
        fi
    else
        /usr/local/bin/sbox
    fi
}

launch_lucky() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "        🛡️ Lucky (Web SSL/反代管理)部署"
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "Lucky 是一款极低内存占用的 Web 面板工具。"
    echo -e "支持自动申请 SSL 证书 + 反向代理。"
    echo -e "非常适合 NAT 小鸡使用！"
    echo -e "${CYAN}-----------------------------------------${RESET}"

    local mem_total
    mem_total=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    if [ -n "$mem_total" ] && [ "$mem_total" -le 256 ]; then
        echo -e "${RED}⚠️ 当前内存仅 ${mem_total}MB，Lucky 运行需要约 50-80MB。${RESET}"
        echo -e "${YELLOW}建议先添加 Swap 再安装。(主菜单 12 -> Swap 管理)${RESET}"
    fi

    if command -v lucky >/dev/null 2>&1 || [ -d "/etc/lucky" ] || [ -d "/opt/lucky" ]; then
        echo -e "${YELLOW}⚠️ 检测到 Lucky 可能已经安装。${RESET}"
        read -p "是否仍然继续执行官方安装脚本？[Y/n]: " install_choice
    else
        read -p "确认安装 Lucky 面板吗？[Y/n]: " install_choice
    fi

    if [[ -z "$install_choice" || "$install_choice" == "Y" || "$install_choice" == "y" ]]; then
        echo -e "${YELLOW}正在调用 Lucky 官方一键安装脚本...${RESET}"
        curl -fsSL https://gitee.com/gdy666/lucky/raw/main/install.sh | bash
        echo -e "${GREEN}✅ Lucky 部署完毕！${RESET}"
    else
        echo -e "${YELLOW}已取消安装。${RESET}"
    fi
    pause
}

run_external() {
    local name=$1
    local cmd=$2
    clear
    echo -e "${YELLOW}即将执行外部脚本: ${CYAN}$name${RESET}"
    echo -e "${RED}⚠️ 来自第三方，请确认你信任该来源！${RESET}"
    read -p "确认继续吗？[Y/n]: " confirm
    if [[ -z "$confirm" || "$confirm" == "y" || "$confirm" == "Y" ]]; then
        eval "$cmd"
    else
        echo -e "${YELLOW}已取消。${RESET}"
        sleep 1
    fi
}

sys_bar() {
    local load mem_info swap_info disk_pct
    load=$(awk '{printf "%.1f", $1}' /proc/loadavg 2>/dev/null || echo "?")
    mem_info=$(free -m 2>/dev/null | awk '/^Mem:/{printf "%d/%dMB",$3,$2}')
    [ -z "$mem_info" ] && mem_info="-"
    swap_info=$(free -m 2>/dev/null | awk '/^Swap:/{if($2>0) printf "%d/%dMB",$3,$2; else print "无"}')
    [ -z "$swap_info" ] && swap_info="无"
    disk_pct=$(df / 2>/dev/null | awk 'NR==2{print $5}')
    [ -z "$disk_pct" ] && disk_pct="-"
    echo -e "${CYAN}负载:${RESET}${YELLOW}${load}${RESET} | ${CYAN}内存:${RESET}${YELLOW}${mem_info}${RESET} | ${CYAN}Swap:${RESET}${YELLOW}${swap_info}${RESET} | ${CYAN}磁盘:${RESET}${YELLOW}${disk_pct}${RESET}"
}

sub_status() {
    local mtp_s="-" komari_s="-" s5_s="-" sbox_s="-"
    local mtp_c="${CYAN}" komari_c="${CYAN}" s5_c="${CYAN}" sbox_c="${CYAN}"

    if [ -f "/usr/local/bin/mtp" ] && [ -x "/usr/local/bin/mtg" ]; then
        if systemctl is-active --quiet mtg 2>/dev/null || pgrep -f "mtg run" >/dev/null 2>&1; then
            mtp_s="●" mtp_c="${GREEN}"
        else
            mtp_s="○" mtp_c="${YELLOW}"
        fi
    fi

    if [ -d "/opt/komari" ]; then
        if systemctl is-active --quiet komari 2>/dev/null; then
            komari_s="●" komari_c="${GREEN}"
        else
            komari_s="○" komari_c="${YELLOW}"
        fi
    fi

    if [ -f "/etc/s5_info.txt" ]; then
        if systemctl is-active --quiet danted 2>/dev/null || systemctl is-active --quiet gost-s5 2>/dev/null; then
            s5_s="●" s5_c="${GREEN}"
        else
            s5_s="○" s5_c="${YELLOW}"
        fi
    fi

    if [ -f "/usr/local/bin/sbox" ] && [ -x "/usr/local/bin/sing-box" ]; then
        if systemctl is-active --quiet sbox-hy2 2>/dev/null || systemctl is-active --quiet sbox-tuic 2>/dev/null || systemctl is-active --quiet sbox-anytls 2>/dev/null; then
            sbox_s="●" sbox_c="${GREEN}"
        else
            sbox_s="○" sbox_c="${YELLOW}"
        fi
    fi

    echo -e "服务: ${CYAN}MTP${RESET}${mtp_c}${mtp_s}${RESET} ${CYAN}Komari${RESET}${komari_c}${komari_s}${RESET} ${CYAN}S5${RESET}${s5_c}${s5_s}${RESET} ${CYAN}SBox${RESET}${sbox_c}${sbox_s}${RESET}"
}

manage_swap() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "         💾 Swap 虚拟内存管理"
    echo -e "${CYAN}=========================================${RESET}"

    local swap_file="/swapfile"
    local current_swap
    current_swap=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')
    [ -z "$current_swap" ] && current_swap=0

    echo -e "当前 Swap: ${YELLOW}${current_swap}MB${RESET}"
    echo -e "${CYAN}-----------------------------------------${RESET}"

    local total_mem
    total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')

    if [ "$current_swap" -gt 0 ]; then
        echo -e "  ${GREEN}1.${RESET} 修改 Swap 大小"
        echo -e "  ${RED}2.${RESET} 删除 Swap"
        echo -e "  ${GREEN}0.${RESET} 返回"
        read -p "选择: " sw_choice
        case "$sw_choice" in
            1) ;;
            2)
                swapoff "$swap_file" 2>/dev/null
                sed -i '/swapfile/d' /etc/fstab 2>/dev/null
                rm -f "$swap_file"
                echo -e "${GREEN}✅ Swap 已删除！${RESET}"
                pause; return
                ;;
            *) return ;;
        esac
    fi

    echo ""
    echo -e "${YELLOW}当前物理内存: ${total_mem}MB${RESET}"
    if [ "$total_mem" -le 256 ]; then
        echo -e "${YELLOW}💡 内存较小，建议开 ${total_mem}~$((total_mem*2))MB Swap${RESET}"
    fi
    echo -e "  ${GREEN}1.${RESET} $((total_mem))MB (1倍内存)"
    echo -e "  ${GREEN}2.${RESET} $((total_mem*2))MB (2倍内存)"
    echo -e "  ${GREEN}3.${RESET} 512MB"
    echo -e "  ${GREEN}4.${RESET} 1024MB"
    echo -e "  ${GREEN}5.${RESET} 自定义大小"
    echo -e "  ${GREEN}0.${RESET} 返回"
    read -p "请选择: " size_choice

    local swap_size
    case "$size_choice" in
        1) swap_size=$((total_mem)) ;;
        2) swap_size=$((total_mem*2)) ;;
        3) swap_size="512" ;;
        4) swap_size="1024" ;;
        5) read -p "输入大小(MB): " swap_size ;;
        *) return ;;
    esac

    [ -z "$swap_size" ] || ! [[ "$swap_size" =~ ^[0-9]+$ ]] || [ "$swap_size" -lt 32 ] && { echo -e "${RED}输入无效${RESET}"; pause; return; }
    [ "$swap_size" -gt 4096 ] && { echo -e "${YELLOW}超过4GB不建议${RESET}"; pause; return; }

    echo -e "${YELLOW}正在创建 ${swap_size}MB Swap...${RESET}"
    swapoff "$swap_file" 2>/dev/null
    rm -f "$swap_file"

    if command -v fallocate >/dev/null 2>&1; then
        fallocate -l "${swap_size}M" "$swap_file" 2>/dev/null || {
            echo -e "${RED}❌ 磁盘空间不足${RESET}"; pause; return
        }
    else
        dd if=/dev/zero of="$swap_file" bs=1048576 count="$swap_size" 2>/dev/null || {
            echo -e "${RED}❌ 创建失败(磁盘空间不足?)${RESET}"; pause; return
        }
    fi

    chmod 600 "$swap_file"
    mkswap "$swap_file" >/dev/null 2>&1
    swapon "$swap_file" >/dev/null 2>&1

    if swapon --show 2>/dev/null | grep -q "$swap_file"; then
        sed -i '/swapfile/d' /etc/fstab 2>/dev/null
        echo "$swap_file none swap sw 0 0" >> /etc/fstab
        echo -e "${GREEN}✅ Swap ${swap_size}MB 创建成功！${RESET}"
        free -m | grep -i swap
    else
        echo -e "${RED}❌ Swap 启用失败！${RESET}"
    fi
    pause
}

enable_bbr() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "        🚀 BBR 网络加速一键开启"
    echo -e "${CYAN}=========================================${RESET}"

    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [ "$current_cc" = "bbr" ]; then
        echo -e "${GREEN}✅ BBR 已开启！${RESET}"
        echo -e "当前算法: ${YELLOW}${current_cc}${RESET}"
        pause
        return
    fi

    local kernel_ver major minor
    kernel_ver=$(uname -r)
    major=$(echo "$kernel_ver" | cut -d. -f1)
    minor=$(echo "$kernel_ver" | cut -d. -f2)

    if [ "$major" -lt 4 ] 2>/dev/null || { [ "$major" -eq 4 ] && [ "$minor" -lt 9 ] 2>/dev/null; }; then
        echo -e "${RED}内核版本: ${kernel_ver}${RESET}"
        echo -e "${YELLOW}BBR 需要内核 4.9+，当前版本过低${RESET}"
        echo -e "${YELLOW}建议升级内核后重试(需重启VPS)${RESET}"
        pause; return
    fi

    echo -e "${YELLOW}正在开启 BBR...${RESET}"
    modprobe tcp_bbr 2>/dev/null
    sed -i '/net.core.default_qdisc/d;/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null
    cat >> /etc/sysctl.conf <<'SYSCTL_EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
SYSCTL_EOF
    sysctl -p >/dev/null 2>&1

    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [ "$current_cc" = "bbr" ]; then
        echo -e "${GREEN}✅ BBR 开启成功！${RESET}"
        echo -e "当前算法: ${YELLOW}${current_cc}${RESET}"
    else
        echo -e "${RED}❌ BBR 开启失败${RESET}"
        echo -e "${YELLOW}提示: 部分VPS需母机开启对应内核模块${RESET}"
    fi
    pause
}

ssh_harden() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "       🔐 SSH 安全加固管理"
    echo -e "${CYAN}=========================================${RESET}"

    local ssh_port
    ssh_port=$(grep -E '^Port ' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    [ -z "$ssh_port" ] && ssh_port="22"

    echo -e "当前SSH端口: ${GREEN}${ssh_port}${RESET}"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${GREEN}1.${RESET} 修改 SSH 端口"
    echo -e "  ${GREEN}2.${RESET} 禁用 root 密码登录 (改用密钥)"
    echo -e "  ${GREEN}3.${RESET} 一键安装公钥 (从 url 拉取)"
    echo -e "  ${YELLOW}4.${RESET} 恢复默认: 22端口 + 允许密码"
    echo -e "  ${GREEN}0.${RESET} 返回"
    read -p "选择: " sh_choice

    case "$sh_choice" in
        1)
            read -p "输入新 SSH 端口 (1024-65535): " new_port
            if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1024 ] || [ "$new_port" -gt 65535 ]; then
                echo -e "${RED}端口无效${RESET}"; pause; return
            fi
            sed -i "s/^#\{0,1\}Port .*/Port ${new_port}/" /etc/ssh/sshd_config
            grep -q "^Port " /etc/ssh/sshd_config || echo "Port ${new_port}" >> /etc/ssh/sshd_config
            if command -v iptables >/dev/null 2>&1; then
                iptables -I INPUT -p tcp --dport "$new_port" -j ACCEPT 2>/dev/null
            fi
            systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || /etc/init.d/ssh restart 2>/dev/null
            echo -e "${GREEN}✅ SSH 端口已改为 ${new_port}${RESET}"
            echo -e "${YELLOW}⚠️ 请用新端口重新连接！当前连接不受影响${RESET}"
            ;;
        2)
            sed -i 's/^#\{0,1\}PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
            sed -i 's/^#\{0,1\}PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
            sed -i 's/^#\{0,1\}PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
            systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || /etc/init.d/ssh restart 2>/dev/null
            echo -e "${GREEN}✅ 已禁用密码登录，仅允许密钥${RESET}"
            echo -e "${YELLOW}⚠️ 确保已配置公钥，否则 SSH 会锁死！${RESET}"
            ;;
        3)
            read -p "输入公钥 URL (如 https://example.com/key.pub): " key_url
            [ -z "$key_url" ] && { echo -e "${RED}URL为空${RESET}"; pause; return; }
            mkdir -p /root/.ssh
            if curl -fsSL --connect-timeout 10 "$key_url" >> /root/.ssh/authorized_keys 2>/dev/null; then
                chmod 700 /root/.ssh
                chmod 600 /root/.ssh/authorized_keys
                echo -e "${GREEN}✅ 公钥已安装${RESET}"
            else
                echo -e "${RED}❌ 公钥下载失败${RESET}"
            fi
            ;;
        4)
            sed -i 's/^#\{0,1\}Port .*/Port 22/' /etc/ssh/sshd_config
            sed -i 's/^#\{0,1\}PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
            sed -i 's/^#\{0,1\}PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
            systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || /etc/init.d/ssh restart 2>/dev/null
            echo -e "${GREEN}✅ SSH 已恢复默认配置${RESET}"
            ;;
    esac
    pause
}

proc_guard() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "       🔄 进程保活 / 崩溃自愈"
    echo -e "${CYAN}=========================================${RESET}"

    echo -e "${YELLOW}检测已安装服务状态...${RESET}"
    echo ""

    local has_any=""
    local cron_needed=""

    if [ -f "/usr/local/bin/mtp" ] && [ -x "/usr/local/bin/mtg" ]; then
        has_any="1"
        if systemctl is-active --quiet mtg 2>/dev/null || pgrep -f "mtg run" >/dev/null 2>&1; then
            echo -e "  ${CYAN}MTP mtg${RESET}  ${GREEN}运行中${RESET} (systemd/Restart=always)"
        else
            echo -e "  ${CYAN}MTP mtg${RESET}  ${RED}已停止${RESET}"
            cron_needed="1"
        fi
    fi

    if [ -d "/opt/komari" ]; then
        has_any="1"
        if systemctl is-active --quiet komari 2>/dev/null; then
            echo -e "  ${CYAN}Komari${RESET}    ${GREEN}运行中${RESET}"
        else
            echo -e "  ${CYAN}Komari${RESET}    ${RED}已停止${RESET}"
            cron_needed="1"
        fi
    fi

    if [ -f "/etc/s5_info.txt" ]; then
        has_any="1"
        if systemctl is-active --quiet danted 2>/dev/null || systemctl is-active --quiet gost-s5 2>/dev/null; then
            echo -e "  ${CYAN}S5${RESET}        ${GREEN}运行中${RESET} (Restart=always)"
        else
            echo -e "  ${CYAN}S5${RESET}        ${RED}已停止${RESET}"
            cron_needed="1"
        fi
    fi

    if [ -f "/usr/local/bin/sbox" ] && [ -x "/usr/local/bin/sing-box" ]; then
        has_any="1"
        if systemctl is-active --quiet sbox-hy2 2>/dev/null || systemctl is-active --quiet sbox-tuic 2>/dev/null || systemctl is-active --quiet sbox-anytls 2>/dev/null; then
            echo -e "  ${CYAN}SBox${RESET}      ${GREEN}运行中${RESET} (Restart=always)"
        else
            echo -e "  ${CYAN}SBox${RESET}      ${RED}已停止${RESET}"
            cron_needed="1"
        fi
    fi

    if [ -z "$has_any" ]; then
        echo -e "${YELLOW}未检测到任何已安装的服务${RESET}"
        pause; return
    fi

    echo ""
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "说明: systemd 服务已自带 Restart=always，崩溃会自动拉起"
    echo -e "      非 systemd 环境或极端情况，可安装 cron 巡检兜底"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo ""

    local CRON_TAG="# SSHTools-proc-guard"
    local has_cron=""
    crontab -l 2>/dev/null | grep -q "$CRON_TAG" && has_cron="1"

    if [ -n "$has_cron" ]; then
        echo -e "  cron 巡检: ${GREEN}已安装${RESET}"
        echo ""
        echo -e "  ${RED}9.${RESET} 卸载 cron 巡检"
    else
        echo -e "  cron 巡检: ${YELLOW}未安装${RESET}"
        echo ""
        echo -e "  ${GREEN}1.${RESET} 安装 cron 巡检 (每5分钟检测，崩溃自动拉起)"
    fi

    echo -e "  ${GREEN}2.${RESET} 一键重启所有已停止服务"
    echo -e "  ${GREEN}0.${RESET} 返回"
    read -p "选择: " pg_choice

    case "$pg_choice" in
        1)
            if [ -n "$has_cron" ]; then
                echo -e "${YELLOW}cron 巡检已安装${RESET}"
                pause; return
            fi
            crontab -l 2>/dev/null | grep -v "$CRON_TAG" > /tmp/sshtools_cron
            cat >> /tmp/sshtools_cron <<'GUARD_CRON'
# SSHTools-proc-guard — 每5分钟巡检服务
# MTP mtg
*/5 * * * * [ ! -x /usr/local/bin/mtg ] && exit 0; { command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet mtg; } || pgrep -f "mtg run" >/dev/null 2>&1 || rc-service mtg status >/dev/null 2>&1 || { command -v systemctl >/dev/null 2>&1 && systemctl start mtg; } || { [ -f /etc/init.d/mtg ] && rc-service mtg start; } || { [ -f /usr/local/bin/mtg_guard.sh ] && nohup setsid /usr/local/bin/mtg_guard.sh >/dev/null 2>&1 &; }
# Komari
*/5 * * * * [ ! -d /opt/komari ] && exit 0; { command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet komari; } || pgrep -f komari >/dev/null 2>&1 || { command -v systemctl >/dev/null 2>&1 && systemctl start komari; }
# S5 (dante or gost)
*/5 * * * * [ ! -f /etc/s5_info.txt ] && exit 0; { command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet danted; } || { command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet gost-s5; } || rc-service danted status >/dev/null 2>&1 || pgrep -f sockd >/dev/null 2>&1 || { command -v systemctl >/dev/null 2>&1 && { systemctl start danted; systemctl start gost-s5; }; } || { [ -f /etc/init.d/danted ] && rc-service danted start; }
# SBox (hy2/tuic/anytls)
*/5 * * * * [ ! -x /usr/local/bin/sing-box ] && exit 0; for s in sbox-hy2 sbox-tuic sbox-anytls; do systemctl is-active --quiet "$s" 2>/dev/null || systemctl start "$s" 2>/dev/null; done
GUARD_CRON
            crontab /tmp/sshtools_cron 2>/dev/null
            rm -f /tmp/sshtools_cron
            echo -e "${GREEN}✅ cron 巡检已安装！每5分钟自动拉起崩溃服务${RESET}"
            echo -e "${YELLOW}适用于低配机器 OOM/意外退出场景${RESET}"
            ;;
        9)
            crontab -l 2>/dev/null | grep -v "$CRON_TAG" | { [ -s /dev/stdin ] && crontab - || true; }
            echo -e "${GREEN}✅ cron 巡检已卸载${RESET}"
            ;;
        2)
            echo -e "${YELLOW}正在重启所有已停止服务...${RESET}"
            [ -f "/usr/local/bin/mtp" ] && ! systemctl is-active --quiet mtg 2>/dev/null && ! pgrep -f "mtg run" >/dev/null 2>&1 && { systemctl start mtg 2>/dev/null || true; echo "  MTP 已重启"; }
            [ -d "/opt/komari" ] && ! systemctl is-active --quiet komari 2>/dev/null && { systemctl start komari 2>/dev/null || true; echo "  Komari 已重启"; }
            [ -f "/etc/s5_info.txt" ] && ! systemctl is-active --quiet danted 2>/dev/null && ! systemctl is-active --quiet gost-s5 2>/dev/null && { systemctl start danted 2>/dev/null; systemctl start gost-s5 2>/dev/null; echo "  S5 已重启"; }
            [ -x "/usr/local/bin/sing-box" ] && { for s in sbox-hy2 sbox-tuic sbox-anytls; do systemctl is-active --quiet "$s" 2>/dev/null || systemctl start "$s" 2>/dev/null; done; echo "  SBox 已检查"; }
            echo -e "${GREEN}✅ 完成${RESET}"
            ;;
    esac
    pause
}

update_nat() {
    clear
    echo -e "${YELLOW}正在从 GitHub 拉取最新主控代码...${RESET}"
    local tmp_file
    tmp_file=$(mktemp)
    if curl -fsSL --connect-timeout 10 "${NAT_URL}" -o "$tmp_file"; then
        if bash -n "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" /usr/local/bin/n
            chmod +x /usr/local/bin/n
            echo -e "${GREEN}✅ 更新成功！正在重启面板...${RESET}"
            sleep 1
            exec /usr/local/bin/n 2>/dev/null || {
                echo -e "${YELLOW}⚠ auto-restart 失败，请手动输入 n${RESET}"
                exit 0
            }
        else
            rm -f "$tmp_file"
            echo -e "${RED}❌ 下载的脚本有语法错误，已取消更新！${RESET}"
            pause
        fi
    else
        rm -f "$tmp_file"
        echo -e "${RED}❌ 下载失败，请检查网络！${RESET}"
        pause
    fi
}

update_scripts_menu() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "        🔄 服务脚本更新"
    echo -e "${CYAN}=========================================${RESET}"
    echo ""

    local has_mtp="" has_s5="" has_komari="" has_sbox="" has_any=""
    [ -f "/usr/local/bin/mtp" ]    && [ -x "/usr/local/bin/mtp" ]    && { has_mtp="1"; has_any="1"; }
    [ -f "/usr/local/bin/s5" ]     && [ -x "/usr/local/bin/s5" ]     && { has_s5="1"; has_any="1"; }
    [ -f "/usr/local/bin/komari" ] && [ -x "/usr/local/bin/komari" ] && { has_komari="1"; has_any="1"; }
    [ -f "/usr/local/bin/sbox" ]   && [ -x "/usr/local/bin/sbox" ]   && { has_sbox="1"; has_any="1"; }

    [ -z "$has_any" ] && { echo -e "${YELLOW}未检测到任何已安装的服务脚本，无需更新${RESET}"; pause; return; }

    echo -e "${GREEN} 1.${RESET} 🔄 一键更新全部已安装"
    echo ""
    [ -n "$has_mtp" ]    && echo -e "${GREEN} 2.${RESET} 更新 MTP"
    [ -n "$has_s5" ]     && echo -e "${GREEN} 3.${RESET} 更新 S5"
    [ -n "$has_komari" ] && echo -e "${GREEN} 4.${RESET} 更新 Komari"
    [ -n "$has_sbox" ]   && echo -e "${GREEN} 5.${RESET} 更新 SBox"
    echo ""
    echo -e "${GREEN} 0.${RESET} 返回"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    read -p "请选择: " up_choice

    do_update_one() {
        local name=$1 url=$2
        echo -ne "${YELLOW}  ${name}...${RESET}"
        local tmp_sh=$(mktemp)
        if curl -fsSL --connect-timeout 15 "$url" -o "$tmp_sh" 2>/dev/null; then
            if bash -n "$tmp_sh" 2>/dev/null; then
                mv "$tmp_sh" "/usr/local/bin/$name"
                chmod +x "/usr/local/bin/$name"
                echo -e "${GREEN} ✅${RESET}"
            else
                rm -f "$tmp_sh"
                echo -e "${RED} ✗ 语法错误${RESET}"
            fi
        else
            rm -f "$tmp_sh"
            echo -e "${RED} ✗ 下载失败${RESET}"
        fi
    }

    case "$up_choice" in
        1)
            echo ""
            [ -n "$has_mtp" ]    && do_update_one "mtp"    "$MTP_URL"
            [ -n "$has_s5" ]     && do_update_one "s5"     "$SOCKS5_URL"
            [ -n "$has_komari" ] && do_update_one "komari" "$KOMARI_URL"
            [ -n "$has_sbox" ]   && do_update_one "sbox"   "$SBOX_URL"
            echo -e "\n${GREEN}✅ 全部更新完成，下次启动生效${RESET}"
            ;;
        2) [ -n "$has_mtp" ]    && { echo ""; do_update_one "mtp"    "$MTP_URL"; } || echo -e "${RED}MTP 未安装${RESET}" ;;
        3) [ -n "$has_s5" ]     && { echo ""; do_update_one "s5"     "$SOCKS5_URL"; } || echo -e "${RED}S5 未安装${RESET}" ;;
        4) [ -n "$has_komari" ] && { echo ""; do_update_one "komari" "$KOMARI_URL"; } || echo -e "${RED}Komari 未安装${RESET}" ;;
        5) [ -n "$has_sbox" ]   && { echo ""; do_update_one "sbox"   "$SBOX_URL"; } || echo -e "${RED}SBox 未安装${RESET}" ;;
    esac
    pause
}

    update_one "mtp"    "$MTP_URL"
    update_one "s5"     "$SOCKS5_URL"
    update_one "komari" "$KOMARI_URL"
    update_one "sbox"   "$SBOX_URL"

    echo ""
    echo -e "${CYAN}=========================================${RESET}"
    [ "$updated" -gt 0 ] && echo -e "${GREEN}✅ ${updated} 个脚本已更新，下次启动生效${RESET}"
    [ "$failed" -gt 0 ]  && echo -e "${RED}❌ ${failed} 个脚本更新失败${RESET}"
    [ "$updated" -eq 0 ] && [ "$failed" -eq 0 ] && [ "$skipped" -eq 4 ] && echo -e "${YELLOW}未检测到任何已安装的服务脚本${RESET}"
    pause
}

uninstall_nat() {
    clear
    echo -e "${CYAN}--- 卸载选项 ---${RESET}"
    echo -e "  ${RED}1.${RESET} 彻底卸载全部 (主控 + MTP + Komari + SOCKS5)"
    echo -e "  ${YELLOW}2.${RESET} 仅卸载主控面板 (保留子模块独立运行)"
    echo -e "  ${GREEN}0.${RESET} 取消并返回"
    read -p "请输入选择: " un_choice
    case "$un_choice" in
        1)
            echo -e "${RED}正在清理所有组件...${RESET}"
            if [ -f "/usr/local/bin/mtp" ]; then
                systemctl stop mtg >/dev/null 2>&1
                systemctl disable mtg >/dev/null 2>&1
                rm -f /etc/systemd/system/mtg.service
                systemctl daemon-reload
                pkill -f "mtg run" 2>/dev/null
                crontab -l 2>/dev/null | grep -v "mtg run" | { [ -s /dev/stdin ] && crontab - || true; }
                rm -f /usr/local/bin/mtg /etc/mtg.toml /etc/mtg_info.txt /usr/local/bin/mtp
            fi
            if [ -f "/usr/local/bin/komari" ]; then
                systemctl stop komari >/dev/null 2>&1
                systemctl disable komari >/dev/null 2>&1
                rm -f /etc/systemd/system/komari.service
                systemctl daemon-reload
                pkill -f "komari" 2>/dev/null
                rm -rf /opt/komari /usr/local/bin/komari
            fi
            if [ -f "/usr/local/bin/s5" ]; then
                systemctl stop danted >/dev/null 2>&1
                systemctl disable danted >/dev/null 2>&1
                rm -f /etc/danted.conf /etc/s5_info.txt /usr/local/bin/s5 /var/log/danted.log
            fi
            echo -e "${YELLOW}提示: 如果安装了 Lucky，请输入 lucky_uninstall 卸载。${RESET}"
            rm -f /usr/local/bin/n "$IP_FILE" "$IP_TYPE_FILE" "$PORTS_FILE"
            echo -e "${GREEN}✅ 全部组件已卸载！再见！${RESET}"
            exit 0
            ;;
        2)
            rm -f /usr/local/bin/n "$IP_FILE" "$IP_TYPE_FILE" "$PORTS_FILE"
            echo -e "${GREEN}✅ 主控面板已卸载！${RESET}"
            exit 0
            ;;
        *) return ;;
    esac
}

while true; do
    clear
    echo -e "${CYAN} _    _             __  __ _ _ _ ${RESET}"
    echo -e "${CYAN}| \\ | |           |  \\/  (_) (_) ${RESET}"
    echo -e "${CYAN}|  \\| | ___   ___ | \\  / |_| |_  ${RESET}"
    echo -e "${CYAN}| . \\\` |/ _ \\ / _ \\| |\\/| | | | | ${RESET}"
    echo -e "${CYAN}| |\\  | (_) | (_) | |  | | | | | ${RESET}"
    echo -e "${CYAN}\\_| \\_/\\___/ \\___/\\_|  |_/_|_|_| ${RESET}"
    echo -e "${CYAN}══════════════════════════════════════${RESET}"
    echo -e "  ${GREEN}░ SSHTools 工具箱${RESET}  ${YELLOW}${SCRIPT_VERSION}${RESET}  ${CYAN}快捷指令:${RESET} ${GREEN}n${RESET}"
    echo -e "${CYAN}══════════════════════════════════════${RESET}"
    echo -e " ${YELLOW}▸ 系统概况${RESET}"
    sys_bar
    sub_status
    echo ""
    echo -e " ${GREEN}▸ 系统运维${RESET}"
    echo -e "  ${GREEN}1.${RESET} 系统信息查询  ${GREEN}2.${RESET} 系统更新    ${GREEN}3.${RESET} 清理垃圾  ${GREEN}4.${RESET} NAT信息卡"
    echo ""
    echo -e " ${BLUE}▸ 服务管理${RESET}"
    echo -e "  ${GREEN}5.${RESET} MTP 代理      ${GREEN}6.${RESET} Komari 探针  ${GREEN}7.${RESET} SOCKS5     ${GREEN}8.${RESET} Lucky SSL"
    echo -e "  ${GREEN}15.${RESET} ${CYAN}📡 SBox 代理${RESET} ${YELLOW}(hy2/tuic/anytls)${RESET}"
    echo ""
    echo -e " ${YELLOW}▸ 外部工具${RESET}"
    echo -e "  ${YELLOW}9.${RESET} 老王工具箱    ${YELLOW}10.${RESET} 科技lion脚本"
    echo ""
    echo -e " ${CYAN}▸ 系统增强${RESET}"
    echo -e "  ${GREEN}11.${RESET} 🚀 BBR 加速   ${GREEN}12.${RESET} 💾 Swap 管理  ${GREEN}13.${RESET} 🔐 SSH 加固  ${GREEN}14.${RESET} 🔄 进程保活"
    echo ""
    echo -e " ${BLUE}▸ 维护${RESET}"
    echo -e "  ${GREEN}s.${RESET} 更新服务脚本  ${CYAN}u.${RESET} 更新主控    ${RED}x.${RESET} 卸载工具箱  ${GREEN}0.${RESET} 退出"
    echo -e "${CYAN}══════════════════════════════════════${RESET}"
    read -p "请输入选择: " choice

    case "$choice" in
        1) show_sys_info ;;
        2) update_system ;;
        3) clean_system ;;
        4) nat_info_card ;;
        5) launch_mtp ;;
        6) launch_komari ;;
        7) launch_s5 ;;
        8) launch_lucky ;;
        15) launch_sbox ;;
        9) run_external "老王一键工具箱" "bash <(curl -fsSL ssh_tool.eooce.com)" ;;
        10) run_external "科技lion一键脚本" "bash <(curl -sL kejilion.sh)" ;;
        11) enable_bbr ;;
        12) manage_swap ;;
        13) ssh_harden ;;
        14) proc_guard ;;
        s|S) update_scripts_menu ;;
        u|U) update_nat ;;
        x|X) uninstall_nat ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}输入错误，请重新选择！${RESET}"; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/n
echo -e "\033[32m✅ 主控脚本已更新：默认思路回归 IPv4，同时保留 IPv6 校准能力。\033[0m"
echo -e "\033[33m正在启动主控面板...\033[0m"
sleep 1
exec /usr/local/bin/n
