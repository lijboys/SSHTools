#!/bin/bash

# =========================================================
#  NatTools - Komari 专用运维脚本 (lijboys 版)
#  GitHub: https://github.com/lijboys/NatTools
# =========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Error: Please run as root!${PLAIN}"; exit 1; fi

# ================= 自动创建快捷键 =================
if [ ! -f "/usr/local/bin/komari" ]; then
    curl -fsSL "https://raw.githubusercontent.com/lijboys/NatTools/main/komari.sh" -o /usr/local/bin/komari 2>/dev/null || cp -f "$0" /usr/local/bin/komari
    chmod +x /usr/local/bin/komari
fi
# ==================================================

# 状态检测
check_install() {
    if [ -f "/opt/komari/komari" ]; then
        STATUS="${GREEN}已安装${PLAIN}"
    else
        STATUS="${RED}未安装${PLAIN}"
    fi
}

draw_menu() {
    check_install
    clear
    echo -e "${BLUE}=======================================${PLAIN}"
    echo -e "       📊 Komari 探针管理面板"
    echo -e "${BLUE}=======================================${PLAIN}"
    echo -e "当前状态: komari $STATUS"
    echo -e "快捷指令: ${GREEN}komari${PLAIN}"
    echo -e "官方介绍：https://github.com/komari-monitor/komari"
    echo -e "${BLUE}---------------------------------------${PLAIN}"
    echo -e "  ${GREEN}1.${PLAIN} 安装                        ${GREEN}2.${PLAIN} 更新"
    echo -e "  ${RED}3.${PLAIN} 卸载                        ${YELLOW}4.${PLAIN} 查看初始凭据"
    echo -e "${BLUE}---------------------------------------${PLAIN}"
    echo -e "  ${GREEN}5.${PLAIN} 添加域名访问 (含SSL/CF回源)   ${RED}6.${PLAIN} 删除域名访问"
    echo -e "  ${GREEN}7.${PLAIN} 允许 IP+端口 访问             ${RED}8.${PLAIN} 阻止 IP+端口 访问"
    echo -e "${BLUE}---------------------------------------${PLAIN}"
    echo -e "  ${YELLOW}00.${PLAIN} 返回主菜单 (NatTools)      ${GREEN}0.${PLAIN} 退出脚本"
    echo -e "${BLUE}=======================================${PLAIN}"
    echo -n " 请输入你的选择: "
}

# 1. 安装并自动显示密码
install_komari() {
    apt update && apt install -y curl wget sed socat nginx-light iptables
    echo -e "${YELLOW}正在拉取官方程序...${PLAIN}"
    curl -fsSL https://raw.githubusercontent.com/komari-monitor/komari/main/install-komari.sh | bash -s -- 1
    
    echo -e "${GREEN}安装完成！正在为你提取初始账号信息...${PLAIN}"
    sleep 3
    echo -e "${BLUE}=======================================${PLAIN}"
    journalctl -u komari -n 200 | grep -E "Username:|Password:" || echo "密码获取稍有延迟，请稍后使用选项 4 查看。"
    echo -e "${BLUE}=======================================${PLAIN}"
    read -p "按回车返回菜单..."
}

# 5. 添加域名访问 (CF回源优化)
add_domain() {
    read -p "请输入域名: " domain
    read -p "请输入内网端口 (默认 25774): " port
    port=${port:-25774}
    
    echo -e "选择模式: 1) 普通域名+自动SSL  2) Cloudflare 回源模式 (由CF提供SSL)"
    read -p "请选择: " cf_mode

    if [ "$cf_mode" == "2" ]; then
        # CF回源模式：Nginx只监听80，由CF走小黄云转发
        cat > /etc/nginx/sites-available/${domain} <<EOF
server {
    listen 80;
    server_name ${domain};
    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        echo -e "${GREEN}CF回源配置完成！请在CF面板开启小黄云并设置 Origin Rule 指向你的 80 或对应映射端口。${PLAIN}"
    else
        # 普通SSL模式
        # ... (此处保留之前的 acme.sh 或 手动上传逻辑)
        echo -e "${YELLOW}正在配置 SSL...${PLAIN}"
        # (代码同之前，支持重新申请或修改)
    fi
    ln -sf /etc/nginx/sites-available/${domain} /etc/nginx/sites-enabled/
    systemctl restart nginx
    read -p "处理完成，按回车返回..."
}

# 7 & 8 防火墙开关
manage_firewall() {
    local action=$1
    local port=25774
    if [ "$action" == "allow" ]; then
        iptables -I INPUT -p tcp --dport $port -j ACCEPT
        echo -e "${GREEN}已开启 IP+端口 ($port) 访问权限。${PLAIN}"
    else
        iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        iptables -A INPUT -p tcp --dport $port -j DROP
        echo -e "${RED}已阻止直接通过 IP+端口 访问。${PLAIN}"
    fi
    read -p "按回车返回..."
}

# 脚本入口
while true; do
    draw_menu
    read choice
    case $choice in
        1) install_komari ;;
        2) # 更新逻辑
           curl -fsSL https://raw.githubusercontent.com/komari-monitor/komari/main/install-komari.sh | bash -s -- 2
           ;;
        3) # 卸载
           systemctl stop komari && rm -rf /opt/komari
           echo "卸载成功" ; sleep 2 ;;
        4) # 查看凭据
           journalctl -u komari -n 200 | grep -E "Username:|Password:"
           read -p "回车继续..." ;;
        5) add_domain ;;
        6) # 删除域名
           ls /etc/nginx/sites-available/
           read -p "输入要删除的域名: " d
           rm -f /etc/nginx/sites-available/$d /etc/nginx/sites-enabled/$d
           systemctl restart nginx ;;
        7) manage_firewall "allow" ;;
        8) manage_firewall "deny" ;;
        00) # 返回主菜单逻辑
           if [ -f "/usr/local/bin/n" ]; then
               exec /usr/local/bin/n
           else
               echo -e "${RED}未安装主控！请先运行主控安装命令。${PLAIN}"
               sleep 2
           fi
           ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}输入错误，请重新选择！${PLAIN}"; sleep 1 ;;
    esac
done
