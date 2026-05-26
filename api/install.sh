#!/bin/sh
# ============================================================
#  router-api 一键安装脚本
#  兼容：标准 OpenWrt / ImmortalWrt / LEDE / iStoreOS / QWRT
#  用法：wget -qO- https://raw.githubusercontent.com/HWYWL/iStore/main/api/install.sh | sh
# ============================================================

set -e

# ---- 配置（自动推断，无需手动修改）----
SCRIPT_URL="https://raw.githubusercontent.com/HWYWL/iStore/main/api/install.sh"
DOWNLOAD_BASE="${SCRIPT_URL%/*}"
API_FILE="router-api"
INSTALL_PATH="/www/cgi-bin/${API_FILE}"

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
        echo "uclient-fetch -qO-"
    else
        return 1
    fi
}

# ---- 生成随机 Token（兼容所有 busybox/OpenWrt 版本）----
generate_token() {
    local token=""

    # 方式一：md5sum（所有 OpenWrt 都支持）
    if command -v md5sum >/dev/null 2>&1; then
        token=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | md5sum | cut -c1-32)
    fi

    # 方式二：sha256sum
    if [ -z "$token" ] && command -v sha256sum >/dev/null 2>&1; then
        token=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | sha256sum | cut -c1-32)
    fi

    # 方式三：纯 shell 降级（最极端情况）
    if [ -z "$token" ]; then
        token=$(date +%s%N 2>/dev/null || date +%s)$$
        while [ ${#token} -lt 32 ]; do
            token="${token}$(date +%s%N 2>/dev/null || echo 0)"
        done
        token=$(echo "$token" | cut -c1-32)
    fi

    echo "$token"
}

# ---- 检测运行环境 ----
detect_openwrt() {
    if [ -f /etc/openwrt_release ] || [ -f /etc/os-release ]; then
        local name
        name=$(grep -o 'PRETTY_NAME="[^"]*"' /etc/os-release 2>/dev/null | sed 's/PRETTY_NAME="//;s/"$//' | head -1)
        [ -z "$name" ] && name=$(grep -o "DISTRIB_DESCRIPTION='[^']*'" /etc/openwrt_release 2>/dev/null | sed "s/DISTRIB_DESCRIPTION='//;s/'$//" | head -1)
        [ -z "$name" ] && name="Unknown OpenWrt"
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
        opkg update >/dev/null 2>&1 || true
        opkg install uhttpd >/dev/null 2>&1 || err "uhttpd 安装失败，请手动安装"
    fi

    # 探测 uhttpd 配置节点名（兼容 main / @uhttpd[0] 等不同命名）
    local uhttpd_section
    uhttpd_section=$(uci show uhttpd 2>/dev/null | grep "uhttpd\." | grep "=uhttpd" | head -1 | cut -d= -f1 | cut -d. -f1-2)
    if [ -z "$uhttpd_section" ]; then
        # 降级：创建标准节点
        uci -q delete uhttpd.main 2>/dev/null || true
        uci set uhttpd.main='uhttpd' 2>/dev/null
        uhttpd_section="uhttpd.main"
    fi

    # 用探测到的节点名设置 CGI 前缀
    uci -q set "${uhttpd_section}.cgi_prefix=/cgi-bin" 2>/dev/null
    uci commit uhttpd 2>/dev/null || true

    # 重启 uhttpd（静默，忽略启动脚本不存在的情况）
    if [ -x /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart >/dev/null 2>&1 || /etc/init.d/uhttpd start >/dev/null 2>&1
    else
        killall -HUP uhttpd >/dev/null 2>&1 || true
    fi

    log "uhttpd CGI 配置完成"
}

# ---- 配置 nginx CGI ----
setup_nginx_cgi() {
    warn "检测到 nginx，CGI 需要额外配置 uhttpd 作为后端"
    warn "尝试安装 uhttpd 作为 CGI 后端..."
    setup_uhttpd_cgi
}

# ---- 下载并安装 CGI 脚本 ----
install_api_script() {
    local downloader
    downloader=$(detect_downloader) || err "未找到任何下载工具 (wget/curl/uclient-fetch)"

    info "正在下载 ${API_FILE} ..."

    # 先检测文件是否可下载
    local http_code
    http_code=$(wget --spider --server-response "${DOWNLOAD_BASE}/${API_FILE}" 2>&1 | \
                grep -oE 'HTTP/[0-9.]+\s+[0-9]+' | head -1 | awk '{print $2}' || echo "000")

    # 实际下载
    $downloader "${DOWNLOAD_BASE}/${API_FILE}" > "${INSTALL_PATH}" 2>/tmp/router-api-download-err.log || {
        warn "下载日志:"
        cat /tmp/router-api-download-err.log 2>/dev/null
        rm -f /tmp/router-api-download-err.log
        err "下载失败，请检查网络连接。\n       手动测试: wget -O- ${DOWNLOAD_BASE}/${API_FILE}"
    }
    rm -f /tmp/router-api-download-err.log

    # 验证下载内容非空
    if [ ! -s "${INSTALL_PATH}" ]; then
        err "下载文件为空，请检查源地址是否有效"
    fi

    chmod +x "${INSTALL_PATH}"
    log "已安装到 ${INSTALL_PATH}"
}

# ---- 配置 Token 认证 ----
setup_token() {
    local token
    token=$(generate_token)

    if [ -z "$token" ]; then
        warn "Token 生成失败，跳过认证配置"
        return 1
    fi

    # 保存到文件
    if ! echo "$token" > /etc/router-api-token 2>/dev/null; then
        warn "无法写入 /etc/router-api-token，跳过文件保存"
    else
        chmod 600 /etc/router-api-token 2>/dev/null || true
    fi

    # 写入 uci 配置（可选，某些精简版可能没有 uci）
    if command -v uci >/dev/null 2>&1; then
        uci -q delete router-api.config 2>/dev/null || true
        uci set router-api.config='config' 2>/dev/null
        uci set router-api.config.auth_enabled='1' 2>/dev/null
        uci set router-api.config.auth_token="${token}" 2>/dev/null
        uci commit router-api 2>/dev/null || true
    fi

    log "Token 认证已启用"
    echo ""
    info "=============================="
    info " 你的 API Token (请保管好):  "
    info " ${token}"
    info "=============================="
    echo ""
}

# ---- 创建 CGI 目录 ----
ensure_cgi_dir() {
    local cgi_dir="/www/cgi-bin"
    if [ ! -d "$cgi_dir" ]; then
        mkdir -p "$cgi_dir"
        log "创建目录 ${cgi_dir}"
    fi
}

# ---- 验证安装 ----
verify_installation() {
    info "验证安装..."
    sleep 1

    local test_url="http://127.0.0.1/cgi-bin/${API_FILE}?action=ping"
    local result=""

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
        warn "验证请求未返回预期结果"
        warn "返回内容: ${result:-空}"
        warn "请手动测试: curl ${test_url}"
        return 1
    fi
}

# ---- 打印使用说明 ----
print_usage() {
    local router_ip=""
    # 优先从接口获取实际 IP（而非 UCI 配置的默认值）
    router_ip=$(ip addr show br-lan 2>/dev/null | grep -oE 'inet [0-9.]+' | head -1 | awk '{print $2}')
    [ -z "$router_ip" ] && router_ip=$(ip addr show eth0 2>/dev/null | grep -oE 'inet [0-9.]+' | head -1 | awk '{print $2}')
    [ -z "$router_ip" ] && router_ip=$(ip addr show eth1 2>/dev/null | grep -oE 'inet [0-9.]+' | head -1 | awk '{print $2}')
    [ -z "$router_ip" ] && router_ip=$(uci -q get network.lan.ipaddr 2>/dev/null)
    [ -z "$router_ip" ] && router_ip="127.0.0.1"

    local token
    token=$(cat /etc/router-api-token 2>/dev/null || echo "未生成")

    echo ""
    echo "=============================================="
    echo "  router-api 安装完成！"
    echo "=============================================="
    echo ""
    echo "  API 地址: http://${router_ip}/cgi-bin/${API_FILE}"
    echo "  Token:    ${token}"
    echo ""
    echo "  快速测试:"
    echo "    curl 'http://${router_ip}/cgi-bin/${API_FILE}?action=ping'"
    echo "    curl 'http://${router_ip}/cgi-bin/${API_FILE}?action=system_info' -H 'X-Auth-Token: ${token}'"
    echo ""
    echo "  支持的操作:"
    echo "    ping              - 健康检查（无需 Token）"
    echo "    system_info       - 系统信息"
    echo "    system_board      - 硬件型号"
    echo "    network_interfaces - 网络接口"
    echo "    network_wifi      - WiFi 状态"
    echo "    network_devices   - 网络设备"
    echo "    dhcp_leases       - DHCP 租约"
    echo "    storage_info      - 存储信息"
    echo "    memory_info       - 内存信息"
    echo "    cpu_info          - CPU 信息"
    echo "    processes         - 进程列表"
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

# Step 2: 创建 CGI 目录
ensure_cgi_dir

# Step 3: 下载安装 CGI 脚本
install_api_script

# Step 4: 配置 Token
setup_token || true

# Step 5: 验证
verify_installation || true

# Step 6: 使用说明
print_usage

log "全部完成！"