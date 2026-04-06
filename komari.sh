#!/bin/bash

# =========================================================
#  NooMili - Komari 专用运维脚本
#  GitHub: https://github.com/lijboys/SSHTools
#  Version: v1.1.0
# =========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

SCRIPT_VERSION="v1.1.0"
SCRIPT_URL="https://raw.githubusercontent.com/lijboys/SSHTools/main/komari.sh"

INSTALLER_URL="https://raw.githubusercontent.com/komari-monitor/komari/main/install-komari.sh"
INSTALL_DIR="/opt/komari"
ADMIN_INFO_FILE="${INSTALL_DIR}/.admin_info"
NAT_PORT_FILE="${INSTALL_DIR}/.nat_port"
NAT_CONF_AVAIL="/etc/nginx/sites-available/komari-nat"
NAT_CONF_ENABLED="/etc/nginx/sites-enabled/komari-nat"
DEFAULT_PORT="25774"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行！${PLAIN}"
    exit 1
fi

cd ~

# ================= 基础函数 =================

pause() {
    read -p "按回车返回菜单..."
}

check_dependencies() {
    local missing=()
    for cmd in curl wget sed grep awk systemctl; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}❌ 缺少依赖: ${missing[*]}${PLAIN}"
        return 1
    fi
    return 0
}

is_valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

is_valid_domain() {
    [[ "$1" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
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

is_port_in_use() {
    ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1$"
}

download_installer() {
    local tmp_file="/tmp/komari-install.sh"
    if ! curl -fsSL --connect-timeout 10 "$INSTALLER_URL" -o "$tmp_file"; then
        echo -e "${RED}❌ 官方安装脚本下载失败！${PLAIN}"
        return 1
    fi
    chmod +x "$tmp_file"
    return 0
}

get_public_ip() {
    local ip
    ip=$(curl -s4m3 ifconfig.me 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s4m3 ipinfo.io/ip 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s4m3 api.ipify.org 2>/dev/null)

    if is_valid_ipv4 "$ip"; then
        echo "$ip"
    else
        echo ""
    fi
}

# ================= 快捷命令创建 =================

install_shortcut() {
    if [ ! -f "/usr/local/bin/komari" ]; then
        local tmp_file
        tmp_file=$(mktemp)

        if curl -fsSL "$SCRIPT_URL" -o "$tmp_file" 2>/dev/null && bash -n "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" /usr/local/bin/komari
        else
            rm -f "$tmp_file"
            cp -f "$0" /usr/local/bin/komari 2>/dev/null
        fi

        chmod +x /usr/local/bin/komari
    fi
}

install_shortcut

# ================= 状态 / 信息读取 =================

get_current_port() {
    if [ -f "$NAT_PORT_FILE" ]; then
        cat "$NAT_PORT_FILE"
    else
        echo "$DEFAULT_PORT"
    fi
}

read_admin_info() {
    CUSTOM_USER=$(grep '^CUSTOM_USER=' "$ADMIN_INFO_FILE" 2>/dev/null | cut -d'"' -f2)
    CUSTOM_PASS=$(grep '^CUSTOM_PASS=' "$ADMIN_INFO_FILE" 2>/dev/null | cut -d'"' -f2)
}

check_install() {
    if [ -d "$INSTALL_DIR" ] && systemctl list-unit-files 2>/dev/null | grep -q "^komari.service"; then
        STATUS="${GREEN}已安装${PLAIN}"
    elif [ -d "$INSTALL_DIR" ]; then
        STATUS="${YELLOW}目录存在(安装状态未知)${PLAIN}"
    else
        STATUS="${RED}未安装${PLAIN}"
    fi
}

get_komari_service_status() {
    if systemctl list-unit-files 2>/dev/null | grep -q "^komari.service"; then
        if systemctl is-active --quiet komari; then
            echo -e "${GREEN}运行中${PLAIN}"
        else
            echo -e "${RED}已停止${PLAIN}"
        fi
    else
        echo -e "${YELLOW}未发现服务${PLAIN}"
    fi
}

draw_menu() {
    check_install
    CURRENT_PORT=$(get_current_port)
    PUBLIC_IP=$(get_public_ip)

    clear
    echo -e "${BLUE}=======================================${PLAIN}"
    echo -e "       📊 Komari 探针管理面板 ${GREEN}${SCRIPT_VERSION}${PLAIN}"
    echo -e "${BLUE}=======================================${PLAIN}"
    echo -e "当前状态: komari $STATUS"
    echo -e "服务状态: $(get_komari_service_status)"

    if [ -d "$INSTALL_DIR" ]; then
        echo -e "公网访问端口: ${YELLOW}${CURRENT_PORT}${PLAIN}"
        if [ -n "$PUBLIC_IP" ]; then
            echo -e "直连访问地址: ${CYAN}http://${PUBLIC_IP}:${CURRENT_PORT}${PLAIN}"
        else
            echo -e "直连访问地址: ${YELLOW}公网 IP 获取失败，请手动确认${PLAIN}"
        fi

        if [ -d "/etc/nginx/sites-enabled/" ]; then
            DOMAINS=$(ls -1 /etc/nginx/sites-enabled/ 2>/dev/null | grep -v "default" | grep -v "^komari-nat$" | tr '\n' ' ')
            if [ -n "$DOMAINS" ]; then
                echo -e "已绑定域名:   ${GREEN}${DOMAINS}${PLAIN}"
            fi
        fi
    fi

    echo -e "官方介绍：https://github.com/komari-monitor/komari"
    echo -e "${BLUE}---------------------------------------${PLAIN}"
    echo -e "  ${GREEN}1.${PLAIN} 安装                        ${GREEN}2.${PLAIN} 更新 (探针程序)"
    echo -e "  ${RED}3.${PLAIN} 彻底卸载                    ${YELLOW}4.${PLAIN} 查看/修改凭据备忘"
    echo -e "${BLUE}---------------------------------------${PLAIN}"
    echo -e "  ${GREEN}5.${PLAIN} 修改面板端口 ${YELLOW}(纯 IP直连，换端口专用)${PLAIN}"
    echo -e "  ${GREEN}6.${PLAIN} 添加域名访问"
    echo -e "  ${RED}7.${PLAIN} 删除域名访问"
    echo -e "${BLUE}---------------------------------------${PLAIN}"
    echo -e "  ${CYAN}8.${PLAIN} 查看 Komari 服务日志"
    echo -e "  ${CYAN}88.${PLAIN} 更新探针面板代码 (从 GitHub 同步)"
    echo -e "  ${YELLOW}9.${PLAIN} 返回主菜单 (NooMili)"
    echo -e "  ${GREEN}0.${PLAIN} 退出脚本"
    echo -e "${BLUE}=======================================${PLAIN}"
    echo -n " 请输入你的选择: "
}

# ================= 凭据相关 =================

show_credentials() {
    echo -e "${BLUE}=======================================${PLAIN}"

    if [ -f "$ADMIN_INFO_FILE" ]; then
        read_admin_info
        echo -e "👉 当前记录账号: ${GREEN}${CUSTOM_USER:-未记录}${PLAIN}"
        echo -e "👉 当前记录密码: ${YELLOW}${CUSTOM_PASS:-未记录}${PLAIN}"
        echo -e "${CYAN}(此为您在此脚本中手动保存的备忘凭据)${PLAIN}"
    else
        LOG_LINE=$(journalctl -u komari --no-pager 2>/dev/null | grep -E "Username:|Password:" | tail -n 1)
        if [ -n "$LOG_LINE" ]; then
            USERNAME=$(echo "$LOG_LINE" | sed -n 's/.*Username: \([^ ,]*\).*/\1/p')
            PASSWORD=$(echo "$LOG_LINE" | sed -n 's/.*Password: \([^ ]*\).*/\1/p')
            echo -e "👉 初始账号: ${GREEN}${USERNAME:-未知}${PLAIN}"
            echo -e "👉 初始密码: ${YELLOW}${PASSWORD:-未知}${PLAIN}"
            echo -e "${RED}(注意：这只是安装时的初始密码，如果你已在网页修改，请及时更新下方备忘。)${PLAIN}"
        else
            echo -e "${YELLOW}日志中暂未找到初始账号信息（可能是导入了旧数据或日志已清理）。${PLAIN}"
        fi
    fi

    echo -e "${BLUE}=======================================${PLAIN}"
    echo ""
    read -p "是否需要更新/记录最新密码备忘？[y/N]: " update_cred
    if [[ "$update_cred" == "y" || "$update_cred" == "Y" ]]; then
        read -p "请输入网页端设置的新账号: " new_u
        read -p "请输入网页端设置的新密码: " new_p

        if [ -n "$new_u" ] && [ -n "$new_p" ]; then
            cat > "$ADMIN_INFO_FILE" <<EOF
CUSTOM_USER="${new_u}"
CUSTOM_PASS="${new_p}"
EOF
            chmod 600 "$ADMIN_INFO_FILE"
            echo -e "${GREEN}✅ 备忘凭据已安全保存！${PLAIN}"
        else
            echo -e "${RED}输入为空，取消保存。${PLAIN}"
        fi
    fi
}

# ================= Nginx / NAT 端口映射 =================

ensure_nginx_dirs() {
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
}

remove_old_iptables_rules() {
    while iptables -D INPUT -p tcp --dport 25774 -j DROP 2>/dev/null; do :; done
    while iptables -D INPUT ! -i lo -p tcp --dport 25774 -j DROP 2>/dev/null; do :; done

    if [ -f "$NAT_PORT_FILE" ]; then
        old_port=$(cat "$NAT_PORT_FILE" 2>/dev/null)
        if is_valid_port "$old_port"; then
            while iptables -D INPUT -p tcp --dport "$old_port" -j ACCEPT 2>/dev/null; do :; done
        fi
    fi
}

apply_port_mapping() {
    local new_port=$1

    if ! is_valid_port "$new_port"; then
        echo -e "${RED}❌ 端口无效！${PLAIN}"
        return 1
    fi

    if [ "$new_port" != "$DEFAULT_PORT" ] && is_port_in_use "$new_port"; then
        echo -e "${RED}❌ 端口 ${new_port} 已被占用，请更换！${PLAIN}"
        return 1
    fi

    ensure_nginx_dirs

    cat > "$NAT_CONF_AVAIL" <<EOF
server {
    listen ${new_port};
    server_name _;
    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:${DEFAULT_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

    ln -sf "$NAT_CONF_AVAIL" "$NAT_CONF_ENABLED"

    if ! nginx -t >/dev/null 2>&1; then
        echo -e "${RED}❌ Nginx 配置测试失败，已取消应用！${PLAIN}"
        rm -f "$NAT_CONF_AVAIL" "$NAT_CONF_ENABLED"
        return 1
    fi

    if ! systemctl restart nginx; then
        echo -e "${RED}❌ Nginx 重启失败！${PLAIN}"
        return 1
    fi

    remove_old_iptables_rules
    iptables -I INPUT -p tcp --dport "$new_port" -j ACCEPT 2>/dev/null
    iptables -A INPUT ! -i lo -p tcp --dport 25774 -j DROP 2>/dev/null

    echo "$new_port" > "$NAT_PORT_FILE"
    return 0
}

# ================= 安装 / 更新 / 卸载 =================

install_komari() {
    clear
    echo -e "${CYAN}=======================================${PLAIN}"
    echo -e "${CYAN}        🚀 开始安装 Komari 探针${PLAIN}"
    echo -e "${CYAN}=======================================${PLAIN}"

    check_dependencies || { pause; return; }

    apt update && apt install -y curl wget sed socat nginx-light iptables
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 依赖安装失败！${PLAIN}"
        pause
        return
    fi

    systemctl enable nginx --now >/dev/null 2>&1

    echo -e "${YELLOW}正在拉取官方程序...${PLAIN}"
    if ! download_installer; then
        pause
        return
    fi

    if ! echo "1" | bash /tmp/komari-install.sh; then
        echo -e "${RED}❌ 官方 Komari 安装流程执行失败！${PLAIN}"
        rm -f /tmp/komari-install.sh
        pause
        return
    fi

    rm -f /tmp/komari-install.sh
    echo "$DEFAULT_PORT" > "$NAT_PORT_FILE"

    echo -e "\n${GREEN}=======================================${PLAIN}"
    echo -e "${GREEN}✅ 探针核心安装完成！正在提取初始账号信息...${PLAIN}"
    sleep 3
    show_credentials

    echo -e "\n${YELLOW}💡 提示：如果你的机器可直接使用默认的 25774 端口，请直接回车。${PLAIN}"
    read -p "👉 若需修改访问端口(如 2250)，请在此输入 (回车保持 25774): " new_port

    if [ -n "$new_port" ] && [ "$new_port" != "$DEFAULT_PORT" ]; then
        echo -e "${YELLOW}正在配置底层 Nginx 路由，接驳端口至 ${new_port}...${PLAIN}"
        if apply_port_mapping "$new_port"; then
            echo -e "${GREEN}✅ 端口映射成功！${PLAIN}"
        else
            echo -e "${RED}❌ 端口映射失败，已保持默认端口 ${DEFAULT_PORT}${PLAIN}"
            echo "$DEFAULT_PORT" > "$NAT_PORT_FILE"
        fi
    else
        echo "$DEFAULT_PORT" > "$NAT_PORT_FILE"
        echo -e "${GREEN}✅ 已保持默认端口 ${DEFAULT_PORT}。${PLAIN}"
    fi

    CURRENT_PORT=$(get_current_port)
    PUBLIC_IP=$(get_public_ip)
    echo -e "\n${CYAN}🎉 全部配置完毕！现在请在浏览器打开：${PLAIN}"
    if [ -n "$PUBLIC_IP" ]; then
        echo -e "${YELLOW}http://${PUBLIC_IP}:${CURRENT_PORT}${PLAIN}"
    else
        echo -e "${YELLOW}http://你的服务器IP:${CURRENT_PORT}${PLAIN}"
    fi

    echo ""
    pause
}

update_komari_core() {
    clear
    echo -e "${YELLOW}正在升级官方 Komari 探针核心...${PLAIN}"

    if ! download_installer; then
        pause
        return
    fi

    if echo "2" | bash /tmp/komari-install.sh; then
        echo -e "${GREEN}✅ 升级完成！${PLAIN}"
    else
        echo -e "${RED}❌ 升级失败！${PLAIN}"
    fi

    rm -f /tmp/komari-install.sh
    pause
}

uninstall_komari() {
    clear
    echo -e "${RED}你正在执行彻底卸载操作！${PLAIN}"
    read -p "确认卸载 Komari 探针及相关配置？[y/N]: " confirm_uninstall

    if [[ "$confirm_uninstall" != "y" && "$confirm_uninstall" != "Y" ]]; then
        echo -e "${YELLOW}已取消卸载。${PLAIN}"
        sleep 1
        return
    fi

    echo -e "${RED}正在彻底卸载 Komari 探针及所有配置...${PLAIN}"

    if download_installer; then
        echo "3" | bash /tmp/komari-install.sh >/dev/null 2>&1
        rm -f /tmp/komari-install.sh
    fi

    rm -f "$NAT_CONF_ENABLED" "$NAT_CONF_AVAIL"
    systemctl restart nginx 2>/dev/null

    remove_old_iptables_rules
    rm -f "$ADMIN_INFO_FILE" "$NAT_PORT_FILE"
    rm -f /usr/local/bin/komari

    echo -e "${GREEN}✅ 彻底卸载成功！面板即将自动关闭...${PLAIN}"
    sleep 2
    exit 0
}

# ================= 端口 / 域名管理 =================

change_port() {
    echo -e "\n${CYAN}--- 修改面板端口向导 ---${PLAIN}"
    read -p "👉 请输入新的公网访问端口 (直接回车则取消修改): " new_port

    if [ -z "$new_port" ]; then
        return
    fi

    if ! is_valid_port "$new_port"; then
        echo -e "${RED}❌ 端口无效！${PLAIN}"
        pause
        return
    fi

    echo -e "${YELLOW}正在配置底层路由与安全规则，接驳端口...${PLAIN}"
    if apply_port_mapping "$new_port"; then
        echo -e "${GREEN}✅ 端口修改成功！你可以直接使用 IP+端口 访问。${PLAIN}"
    else
        echo -e "${RED}❌ 端口修改失败！${PLAIN}"
    fi
    pause
}

add_domain() {
    ensure_nginx_dirs

    read -p "请输入域名: " domain
    if ! is_valid_domain "$domain"; then
        echo -e "${RED}❌ 域名格式不正确！${PLAIN}"
        pause
        return
    fi

    echo -e "选择模式:"
    echo -e "  ${GREEN}1.${PLAIN} 普通域名反代"
    echo -e "  ${GREEN}2.${PLAIN} Cloudflare 回源模式"
    read -p "请选择 [1/2]: " cf_mode
    [ -z "$cf_mode" ] && cf_mode="1"

    cat > "/etc/nginx/sites-available/${domain}" <<EOF
server {
    listen 80;
    server_name ${domain};
    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:${DEFAULT_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

    ln -sf "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/${domain}"

    if ! nginx -t >/dev/null 2>&1; then
        echo -e "${RED}❌ Nginx 配置测试失败！${PLAIN}"
        rm -f "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/${domain}"
        pause
        return
    fi

    if ! systemctl restart nginx; then
        echo -e "${RED}❌ Nginx 重启失败！${PLAIN}"
        pause
        return
    fi

    if [ "$cf_mode" = "2" ]; then
        echo -e "${GREEN}✅ Cloudflare 回源模式配置完成！${PLAIN}"
        echo -e "${YELLOW}请在 CF 面板中开启小黄云，并将域名解析到本机 IP。${PLAIN}"
        echo -e "${YELLOW}同时建议在 CF 中启用 Full 或 Full(Strict) 模式。${PLAIN}"
    else
        echo -e "${GREEN}✅ 域名反代配置完成！${PLAIN}"
        echo -e "${YELLOW}当前为 HTTP 反代，如需 HTTPS 请自行接入 certbot / acme。${PLAIN}"
    fi

    pause
}

delete_domain() {
    ensure_nginx_dirs
    local domain_list

    domain_list=$(ls -1 /etc/nginx/sites-available/ 2>/dev/null | grep -v "default" | grep -v "^komari-nat$")

    if [ -z "$domain_list" ]; then
        echo -e "${YELLOW}当前没有可删除的域名配置。${PLAIN}"
        pause
        return
    fi

    echo -e "${CYAN}当前已配置域名：${PLAIN}"
    echo "$domain_list"
    read -p "输入要删除的域名: " d

    if [ -z "$d" ]; then
        echo -e "${YELLOW}已取消。${PLAIN}"
        pause
        return
    fi

    rm -f "/etc/nginx/sites-available/$d" "/etc/nginx/sites-enabled/$d"

    if nginx -t >/dev/null 2>&1; then
        systemctl restart nginx
        echo -e "${GREEN}✅ 域名配置已删除。${PLAIN}"
    else
        echo -e "${RED}❌ 删除后 Nginx 配置异常，请手动检查！${PLAIN}"
    fi

    pause
}

# ================= 日志 / 脚本更新 =================

view_logs() {
    clear
    echo -e "${BLUE}=======================================${PLAIN}"
    echo -e "           📜 Komari 服务日志"
    echo -e "${BLUE}=======================================${PLAIN}"

    if systemctl list-unit-files 2>/dev/null | grep -q "^komari.service"; then
        journalctl -u komari --no-pager -n 50 2>/dev/null || echo "暂无日志"
    else
        echo "未发现 komari.service"
    fi

    echo -e "${BLUE}=======================================${PLAIN}"
    pause
}

update_panel() {
    clear
    echo -e "${YELLOW}正在从 GitHub 拉取最新探针面板代码...${PLAIN}"

    local tmp_file
    tmp_file=$(mktemp)

    if curl -fsSL --connect-timeout 10 "$SCRIPT_URL" -o "$tmp_file"; then
        if bash -n "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" /usr/local/bin/komari
            chmod +x /usr/local/bin/komari
            echo -e "${GREEN}✅ 探针面板更新完成！即将重启面板...${PLAIN}"
            sleep 2
            exec /usr/local/bin/komari
        else
            rm -f "$tmp_file"
            echo -e "${RED}❌ 新脚本语法校验失败，已取消更新！${PLAIN}"
            pause
        fi
    else
        rm -f "$tmp_file"
        echo -e "${RED}❌ 下载失败，请检查网络！${PLAIN}"
        pause
    fi
}

# ================= 主循环 =================

while true; do
    draw_menu
    read choice

    case "$choice" in
        1) install_komari ;;
        2) update_komari_core ;;
        3) uninstall_komari ;;
        4) show_credentials; pause ;;
        5) change_port ;;
        6) add_domain ;;
        7) delete_domain ;;
        8) view_logs ;;
        88) update_panel ;;
        9)
            if [ -f "/usr/local/bin/n" ]; then
                exec /usr/local/bin/n
            else
                echo -e "${RED}未安装主控！请先运行主控安装命令。${PLAIN}"
                sleep 2
            fi
            ;;
        0) clear; exit 0 ;;
        *)
            echo -e "${RED}输入错误，请重新选择！${PLAIN}"
            sleep 1
            ;;
    esac
done
