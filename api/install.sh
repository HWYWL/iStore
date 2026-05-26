#!/bin/sh
# ============================================================
#  router-api 一键安装脚本
#  兼容：标准 OpenWrt / ImmortalWrt / LEDE / iStoreOS
#  用法：wget -qO- https://xxx.com/router-api/install.sh | sh
# ============================================================

set -e

# ---- 配置（部署前修改这里）----
DOWNLOAD_BASE="https://raw.githubusercontent.com/你的用户名/iStore/main/api"
API_FILE="router-api"
INSTALL_PATH="/www/cgi-bin/${API_FILE}"
CGI_PREFIX="/cgi-bin"

# ---- 颜色 ----
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
NC='\033[0m'

log()  { printf "${GREEN}[✓]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$1"; }
err()  { printf "${RED}[✗]${NC} %s\n" "$1"; exit 1; }
info() { printf "${CYAN}[i]${NC} %s\n" "$1"; }

# ---- 检测下载工具 ----
detect_downloader() {
    if command -v wget >/dev/null 2>&1; then
        echo "wget -qO-"
    elif command -v curl >/dev/null 2>&1; then
        echo "curl -sSL"
    elif command -v uclient-fetch >/dev/null 2>&1; then
        # OpenWrt 自带的最小化下载工具
        echo "uclient-fetch -qO-"
    else
        return 1
    fi
}

# ---- 检测运行环境 ----
detect_openwrt() {
    if [ -f /etc/openwrt_release ] || [ -f /etc/os-release ]; then
        local name
        name=$(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || \
               grep -oP 'DISTRIB_DESCRIPTION='\''\K[^'\'']+' /etc/openwrt_release 2>/dev/null || \
               echo "Unknown OpenWrt")
        log "检测到系统: ${name}"
    else
        warn "未检测到 OpenWrt 特征文件，继续尝试安装..."
    fi
}

# ---- 检查 Web 服务器 ----
check_web_server() {
    if command -v uhttpd >/dev/null 2>&1 && pgrep uhttpd >/dev/null 2>&1; then
        echo "uhttpd"
    elif command -v nginx >/dev/null 2>&1 && pgrep nginx >/dev/null 2>&1; then
        echo "nginx"
    elif command -v lighttpd >/dev/null 2>&1 && pgrep lighttpd >/dev/null 2>&1; then
        echo "lighttpd"
    else
        echo "none"
    fi
}

# ---- 配置 uhttpd CGI ----
setup_uhttpd_cgi() {
    info "配置 uhttpd CGI 支持..."

    # 确保 uhttpd 已安装
    if ! command -v uhttpd >/dev/null 2>&1; then
        warn "未找到 uhttpd，尝试安装..."
        opkg update >/dev/null 2>&1
        opkg install uhttpd >/dev/null 2>&1 || err "uhttpd 安装失败，请手动安装"
    fi

    # 配置 CGI 路径
    uci -q set uhttpd.main='uhttpd' 2>/dev/null
    uci -q set uhttpd.main.cgi_prefix="${CGI_PREFIX}"
    uci commit uhttpd

    # 重启 uhttpd
    /etc/init.d/uhttpd restart >/dev/null 2>&1 || /etc/init.d/uhttpd start >/dev/null 2>&1
    log "uhttpd CGI 配置完成"
}

# ---- 配置 nginx CGI ----
setup_nginx_cgi() {
    warn "检测到 nginx，CGI 需要额外配置 uhttpd 作为后端"
    warn "建议改回 uhttpd，或手动配置 nginx FastCGI"
    warn "尝试安装 uhttpd 作为 CGI 后端..."
    setup_uhttpd_cgi
}

# ---- 下载并安装 CGI 脚本 ----
install_api_script() {
    local downloader
    downloader=$(detect_downloader) || err "未找到任何下载工具 (wget/curl/uclient-fetch)"

    info "正在下载 ${API_FILE} ..."
    $downloader "${DOWNLOAD_BASE}/${API_FILE}" > "${INSTALL_PATH}" || {
        err "下载失败，请检查网络连接和 DOWNLOAD_BASE 地址"
    }

    chmod +x "${INSTALL_PATH}"
    log "已安装到 ${INSTALL_PATH}"
}

# ---- 生成随机 Token ----
generate_token() {
    local token
    token=$(head -c 32 /dev/urandom 2>/dev/null | base64 2>/dev/null | tr -d '\n' | tr '/+' '_-')
    if [ -z "$token" ]; then
        # 降级：用时间和随机数
        token=$(date +%s%N 2>/dev/null | sha256sum 2>/dev/null | cut -c1-32 || \
                echo "$(date +%s)$(head -c 16 /dev/urandom 2>/dev/null | md5sum | cut -c1-8)" | md5sum | cut -c1-32)
    fi
    echo "${token:-$(date +%s | md5sum | cut -c1-32)}"
}

# ---- 配置 Token 认证 ----
setup_token() {
    local token
    token=$(generate_token)

    uci -q delete router-api.config 2>/dev/null || true
    uci set router-api.config='config'
    uci set router-api.config.auth_enabled='1'
    uci set router-api.config.auth_token="${token}"
    uci commit router-api

    # 保存 token 到文件，方便用户查看
    echo "$token" > /etc/router-api-token
    chmod 600 /etc/router-api-token

    log "Token 认证已启用"
    echo ""
    info "=============================="
    info " 你的 API Token (请保管好):  "
    info " ${token}"
    info "=============================="
    echo ""
}

# ---- 验证安装 ----
verify_installation() {
    info "验证安装..."
    sleep 1  # 等 uhttpd 完全启动

    local test_url="http://127.0.0.1${CGI_PREFIX}/${API_FILE}?action=ping"
    local result

    if command -v wget >/dev/null 2>&1; then
        result=$(wget -qO- "$test_url" 2>/dev/null || echo "")
    elif command -v curl >/dev/null 2>&1; then
        result=$(curl -sS "$test_url" 2>/dev/null || echo "")
    elif command -v uclient-fetch >/dev/null 2>&1; then
        result=$(uclient-fetch -qO- "$test_url" 2>/dev/null || echo "")
    fi

    if echo "$result" | grep -q '"pong"'; then
        log "安装验证成功！API 工作正常"
        return 0
    else
        warn "验证请求未返回预期结果，但文件已安装"
        warn "请手动测试: curl ${test_url}"
        return 1
    fi
}

# ---- 打印使用说明 ----
print_usage() {
    local router_ip
    router_ip=$(uci -q get network.lan.ipaddr 2>/dev/null || ip addr show br-lan 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || echo "路由器IP")

    echo ""
    echo "=============================================="
    echo "  router-api 安装完成！"
    echo "=============================================="
    echo ""
    echo "  API 地址: http://${router_ip}${CGI_PREFIX}/${API_FILE}"
    echo ""
    echo "  快速测试:"
    echo "    curl 'http://${router_ip}${CGI_PREFIX}/${API_FILE}?action=ping'"
    echo "    curl 'http://${router_ip}${CGI_PREFIX}/${API_FILE}?action=system_info' -H 'X-Auth-Token: <你的token>'"
    echo ""
    echo "  支持的操作:"
    echo "    ping              - 健康检查"
    echo "    system_info       - 系统信息"
    echo "    network_interfaces - 网络接口"
    echo "    network_wifi      - WiFi 状态"
    echo "    dhcp_leases       - DHCP 租约"
    echo "    storage_info      - 存储信息"
    echo "    memory_info       - 内存信息"
    echo "    cpu_info          - CPU 信息"
    echo "    uci_get           - 读取 UCI 配置"
    echo "    uci_get_all       - 读取全部 UCI 配置"
    echo ""
    echo "  查看 Token: cat /etc/router-api-token"
    echo "  卸载: wget -qO- ${DOWNLOAD_BASE}/uninstall.sh | sh"
    echo ""
    echo "=============================================="
}

# ============================================================
#   Main
# ============================================================

echo ""
echo "╔═══════════════════════════════╗"
echo "║   router-api  一键安装程序    ║"
echo "║   适配所有 OpenWrt 衍生版     ║"
echo "╚═══════════════════════════════╝"
echo ""

detect_openwrt

# Step 1: 检查/配置 Web 服务器
WS=$(check_web_server)
case "$WS" in
    uhttpd)
        log "检测到 uhttpd"
        setup_uhttpd_cgi
        ;;
    nginx)
        setup_nginx_cgi
        ;;
    lighttpd)
        warn "检测到 lighttpd，尝试安装 uhttpd..."
        setup_uhttpd_cgi
        ;;
    *)
        warn "未检测到 Web 服务器，尝试安装 uhttpd..."
        opkg update >/dev/null 2>&1 || true
        opkg install uhttpd >/dev/null 2>&1 || err "uhttpd 安装失败"
        setup_uhttpd_cgi
        ;;
esac

# Step 2: 下载安装 CGI 脚本
install_api_script

# Step 3: 配置 Token
setup_token

# Step 4: 验证
verify_installation

# Step 5: 使用说明
print_usage

log "全部完成！"