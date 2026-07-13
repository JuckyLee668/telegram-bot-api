#!/bin/bash
set -e

# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==================== 辅助函数 ====================

print_info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
print_ok()    { echo -e "${GREEN}[✓]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
print_err()   { echo -e "${RED}[✗]${NC} $1"; }

install_package() {
    local cmd=$1
    local pkg=$2
    if command -v "$cmd" &>/dev/null; then
        print_ok "$cmd 已安装"
        return 0
    fi
    print_info "正在安装 $cmd..."
    if command -v apt &>/dev/null; then
        apt update && apt install -y "$pkg"
    elif command -v yum &>/dev/null; then
        yum install -y "$pkg"
    elif command -v dnf &>/dev/null; then
        dnf install -y "$pkg"
    elif command -v zypper &>/dev/null; then
        zypper install -y "$pkg"
    else
        print_err "无法识别包管理器，请手动安装 $cmd"
        return 1
    fi
    if command -v "$cmd" &>/dev/null; then
        print_ok "$cmd 安装成功"
        return 0
    else
        print_err "$cmd 安装失败"
        return 1
    fi
}

install_caddy() {
    if command -v caddy &>/dev/null; then
        local ver
        ver=$(caddy version 2>/dev/null | head -c 30)
        print_ok "Caddy 已安装 ($ver)"
        return 0
    fi
    print_info "正在安装 Caddy (官方仓库)..."

    # 使用官方 Caddy 仓库（推荐方式，比 apt 默认版本新）
    if command -v apt &>/dev/null; then
        apt install -y debian-keyring debian-archive-keyring apt-transport-https curl 2>/dev/null
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list 2>/dev/null
        apt update && apt install -y caddy
        if command -v caddy &>/dev/null; then
            local ver
            ver=$(caddy version 2>/dev/null | head -c 30)
            print_ok "Caddy 已安装 ($ver)"
            return 0
        fi
    fi

    # 降级到二进制下载
    print_warn "apt 安装失败，尝试下载二进制..."
    local CADDY_ARCH
    case $(uname -m) in
        x86_64)  CADDY_ARCH="amd64" ;;
        aarch64) CADDY_ARCH="arm64" ;;
        *)       print_err "不支持的架构: $(uname -m)"; return 1 ;;
    esac

    local DOWNLOAD_URL
    DOWNLOAD_URL=$(curl -s https://api.github.com/repos/caddyserver/caddy/releases/latest | \
                   jq -r ".assets[] | select(.name | contains(\"linux_$CADDY_ARCH\") and contains(\"tar.gz\")) | .browser_download_url" | head -1)
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
        print_err "无法获取 Caddy 下载地址"
        return 1
    fi

    # 解压到 /root/ 而非 /tmp （tmpfs容量小）
    local TMP_DIR="/root/.caddy_install"
    mkdir -p "$TMP_DIR"
    curl -L "$DOWNLOAD_URL" | tar -xz -C "$TMP_DIR"
    if [ ! -f "$TMP_DIR/caddy" ]; then
        print_err "解压后未找到 caddy 二进制"
        rm -rf "$TMP_DIR"
        return 1
    fi
    mv "$TMP_DIR/caddy" /usr/local/bin/caddy
    chmod +x /usr/local/bin/caddy
    rm -rf "$TMP_DIR"
    print_ok "Caddy 已安装到 /usr/local/bin/caddy ($(caddy version 2>/dev/null | head -c 30))"
    return 0
}

install_libcpp() {
    print_info "检查 libc++ 依赖..."
    # 检查是否已安装（多种检查方式）
    if ldconfig -p 2>/dev/null | grep -q libc++ || dpkg -l 2>/dev/null | grep -q libc++ || rpm -qa 2>/dev/null | grep -q libc++; then
        print_ok "libc++ 已安装"
        return 0
    fi

    if command -v apt &>/dev/null; then
        apt update && apt install -y libc++-dev libc++abi-dev
    elif command -v yum &>/dev/null; then
        yum install -y libcxx-devel || (yum install -y epel-release && yum install -y libcxx-devel)
    elif command -v dnf &>/dev/null; then
        dnf install -y libcxx-devel
    elif command -v zypper &>/dev/null; then
        zypper install -y libc++-devel libc++abi-devel
    else
        print_err "无法自动安装 libc++，请手动安装"
        return 1
    fi

    if ldconfig -p 2>/dev/null | grep -q libc++ || dpkg -l 2>/dev/null | grep -q libc++; then
        print_ok "libc++ 安装成功"
    else
        print_warn "libc++ 可能未正确安装，继续尝试（程序可能使用静态链接）"
    fi
}

# ==================== 主脚本 ====================

if [ "$EUID" -ne 0 ]; then
    print_err "请以 root 用户执行此脚本"
    exit 1
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Telegram Bot API 安装脚本${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

# ========== 1. 基础依赖 ==========
echo -e "${GREEN}========== 1. 安装基础依赖 ==========${NC}"
install_package curl curl
install_package jq jq
install_caddy
install_libcpp

# ========== 2. 环境变量检查 ==========
echo -e "${GREEN}========== 2. 检查环境变量 ==========${NC}"
if [ -z "$TELEGRAM_API_ID" ] || [ -z "$TELEGRAM_API_HASH" ]; then
    print_err "请设置环境变量 TELEGRAM_API_ID 和 TELEGRAM_API_HASH"
    echo "  export TELEGRAM_API_ID=你的ID"
    echo "  export TELEGRAM_API_HASH=你的HASH"
    exit 1
fi
print_ok "TELEGRAM_API_ID / TELEGRAM_API_HASH 已设置"

# ========== 3. 下载/检查二进制 ==========
REPO="JuckyLee668/telegram-bot-api"
WORK_DIR="/opt/telegram-bot-api"
BIN_NAME="telegram-bot-api"
HTTP_PORT=8081
DOMAIN="api.xi-han.top"
DATA_DIR="/var/lib/telegram-bot-api"
LOG_FILE="/var/log/telegram-bot-api.log"
CADDYFILE="/etc/caddy/Caddyfile"
SERVICE_FILE="/etc/systemd/system/telegram-bot-api.service"

mkdir -p "$WORK_DIR" "$DATA_DIR" "$(dirname "$LOG_FILE")"
cd "$WORK_DIR"

echo -e "${GREEN}========== 3. 下载/更新 telegram-bot-api ==========${NC}"

# 检查已有二进制是否有执行权限（默认跳过，传 --force 或 -f 强制重下）
FORCE_REINSTALL=false
if [[ "$1" == "--force" || "$1" == "-f" ]]; then
    FORCE_REINSTALL=true
fi

if [ -x "$BIN_NAME" ] && [ "$FORCE_REINSTALL" = false ]; then
    print_ok "已存在可执行文件: $WORK_DIR/$BIN_NAME，跳过下载（传 -f 强制重下）"
else
    if [ -x "$BIN_NAME" ] && [ "$FORCE_REINSTALL" = true ]; then
        print_info "强制重新下载..."
    fi
    RELEASE_JSON=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")
    if [ -z "$RELEASE_JSON" ] || [ "$(echo "$RELEASE_JSON" | jq -r '.message')" = "Not Found" ]; then
        print_err "无法获取 release"
        exit 1
    fi

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH_FILTER="x86_64" ;;
        aarch64) ARCH_FILTER="arm64" ;;
        *)       ARCH_FILTER="" ;;
    esac

    DOWNLOAD_URL=""
    if [ -n "$ARCH_FILTER" ]; then
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r ".assets[] | select(.name | contains(\"linux\") and contains(\"$ARCH_FILTER\")) | .browser_download_url" | head -1)
    fi
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r ".assets[] | select(.name | contains(\"$ARCH_FILTER\")) | .browser_download_url" | head -1)
    fi
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r ".assets[0].browser_download_url")
    fi
    print_info "下载地址: $DOWNLOAD_URL"

    curl -L -o "$BIN_NAME" "$DOWNLOAD_URL"
    chmod +x "$BIN_NAME"
    if [ ! -x "$BIN_NAME" ]; then
        print_err "下载文件无法执行"
        exit 1
    fi
    print_ok "下载完成"
fi

# 验证二进制（至少能打印版本）
print_info "验证二进制..."
if ! ./"$BIN_NAME" --help 2>&1 | head -5; then
    print_warn "二进制 --help 无输出，可能不支持 --help 参数"
fi
print_ok "二进制有效"

# ========== 4. 创建 systemd 服务 ==========
echo -e "${GREEN}========== 4. 创建 systemd 服务 ==========${NC}"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Telegram Bot API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/$BIN_NAME \\
    --api-id=$TELEGRAM_API_ID \\
    --api-hash=$TELEGRAM_API_HASH \\
    --local \\
    --http-port=$HTTP_PORT \\
    --dir=$DATA_DIR \\
    --log=$LOG_FILE
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
print_ok "systemd 服务文件已创建: $SERVICE_FILE"

# ========== 5. 启动服务 ==========
echo -e "${GREEN}========== 5. 启动 telegram-bot-api 服务 ==========${NC}"

# 先停止旧进程
if pgrep -x "$BIN_NAME" &>/dev/null; then
    print_warn "检测到旧进程，正在停止..."
    pkill -x "$BIN_NAME" 2>/dev/null || true
    sleep 1
fi

# 清理旧日志
: > "$LOG_FILE"

systemctl start telegram-bot-api
sleep 2

if systemctl is-active --quiet telegram-bot-api; then
    print_ok "telegram-bot-api 服务已启动"
    systemctl status telegram-bot-api --no-pager -l | head -15
else
    print_err "服务启动失败"
    systemctl status telegram-bot-api --no-pager -l | tail -20
    if [ -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}--- 日志最后 30 行 ---${NC}"
        tail -30 "$LOG_FILE"
    fi
    exit 1
fi

# ========== 6. 测试 API ==========
echo -e "${GREEN}========== 6. 测试 API 本地访问 ==========${NC}"
sleep 2
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:"$HTTP_PORT" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" =~ ^[2-4][0-9][0-9]$ ]]; then
    print_ok "API 本地访问成功 (HTTP $HTTP_CODE)"
else
    print_err "API 本地访问失败 (HTTP $HTTP_CODE)"
    echo "日志: tail -f $LOG_FILE"
    exit 1
fi

# ========== 7. 配置 Caddy ==========
echo -e "${GREEN}========== 7. 配置 Caddy 反向代理 ==========${NC}"
mkdir -p "$(dirname "$CADDYFILE")"

if grep -q "^\s*$DOMAIN\s*{" "$CADDYFILE" 2>/dev/null; then
    print_ok "Caddyfile 中已存在 $DOMAIN 配置"
else
    if [ ! -f "$CADDYFILE" ]; then
        echo "# Telegram Bot API" > "$CADDYFILE"
    fi
    echo -e "\n$DOMAIN { reverse_proxy localhost:$HTTP_PORT }" >> "$CADDYFILE"
    print_ok "已添加配置到 $CADDYFILE"
fi

# 确保 Caddy 运行
if systemctl is-active --quiet caddy 2>/dev/null; then
    systemctl restart caddy
    print_ok "Caddy 服务已重启"
elif pgrep -x "caddy" >/dev/null; then
    # 非 systemd 方式运行的 caddy，重新加载
    caddy reload --config "$CADDYFILE" 2>/dev/null || true
    print_ok "Caddy 配置已重载"
else
    # 启动 caddy（systemd 优先）
    if systemctl list-units --type=service 2>/dev/null | grep -q caddy; then
        systemctl start caddy
        print_ok "Caddy systemd 服务已启动"
    else
        nohup caddy run --config "$CADDYFILE" >/dev/null 2>&1 &
        print_ok "Caddy 已启动 (nohup)"
    fi
fi

# ========== 8. 最终状态检查 ==========
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   最终运行状态${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

# telegram-bot-api 状态
if systemctl is-active --quiet telegram-bot-api; then
    print_ok "telegram-bot-api 服务: 运行中 (systemd)"
    systemctl is-enabled --quiet telegram-bot-api 2>/dev/null && print_ok "开机自启: 已启用" || print_warn "开机自启: 未启用"
else
    print_err "telegram-bot-api 服务: 未运行"
fi

# Caddy 状态
if systemctl is-active --quiet caddy 2>/dev/null; then
    print_ok "Caddy 服务: 运行中 (systemd)"
elif pgrep -x "caddy" >/dev/null; then
    print_ok "Caddy 服务: 运行中 (独立进程)"
else
    print_err "Caddy 服务: 未运行"
fi

# 端口监听
echo ""
print_info "端口监听状态:"
ss -tlnp 2>/dev/null | grep -E "(:$HTTP_PORT|:80|:443)" || netstat -tlnp 2>/dev/null | grep -E "(:$HTTP_PORT|:80|:443)"

# 域名访问
echo ""
print_info "域名访问测试:"
curl -s -o /dev/null -w "  http://127.0.0.1:$HTTP_PORT → %{http_code}\n" http://127.0.0.1:"$HTTP_PORT"
curl -s -o /dev/null -w "  https://$DOMAIN → %{http_code} (可能需要本地 hosts)\n" "https://$DOMAIN" --connect-timeout 3 2>/dev/null || echo "  https://$DOMAIN → 无法连接（域名 DNS 可能未指向本机）"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   🎉 部署完成！${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  管理命令:"
echo "    systemctl status telegram-bot-api    # 查看服务状态"
echo "    systemctl start/stop/restart telegram-bot-api"
echo "    journalctl -u telegram-bot-api -f    # 实时日志"
echo "    tail -f $LOG_FILE                     # 或查看日志文件"
echo ""
echo "  配置信息:"
echo "    API 端口:      $HTTP_PORT"
echo "    域名:          $DOMAIN"
echo "    数据目录:      $DATA_DIR"
echo "    日志文件:      $LOG_FILE"
echo ""
echo -e "${YELLOW}注意: 如果域名未指向本机，请在 DNS 管理面板添加 A 记录${NC}"
echo ""
