#!/bin/sh
# router-api 卸载脚本
# 用法：wget -qO- https://xxx.com/router-api/uninstall.sh | sh

set -e

INSTALL_PATH="/www/cgi-bin/router-api"

echo "正在卸载 router-api..."

# 删除 CGI 脚本
[ -f "$INSTALL_PATH" ] && rm -f "$INSTALL_PATH" && echo "[✓] 已删除 $INSTALL_PATH"

# 删除 token 文件
[ -f /etc/router-api-token ] && rm -f /etc/router-api-token && echo "[✓] 已删除 token 文件"

# 删除 uci 配置
uci -q delete router-api.config 2>/dev/null && uci commit router-api && echo "[✓] 已清除 uci 配置"

echo ""
echo "卸载完成!"