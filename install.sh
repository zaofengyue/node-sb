#!/bin/bash
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${YELLOW}========== node-sb 面板安装 ==========${NC}"

if command -v curl >/dev/null 2>&1; then
  DL="curl -fsSL"; DL_O="-o"
elif command -v wget >/dev/null 2>&1; then
  DL="wget -q"; DL_O="-O"
else
  echo -e "${RED}缺少 curl 或 wget${NC}"; exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo -e "${YELLOW}未检测到 Node.js，尝试自动安装...${NC}"

  if [ ! -f "$HOME/.nvm/nvm.sh" ]; then
    echo -e "${YELLOW}正在安装 nvm...${NC}"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash >/dev/null 2>&1
  fi

  if [ -f "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    source "$NVM_DIR/nvm.sh"
    nvm install 20 >/dev/null 2>&1
    nvm use 20 >/dev/null 2>&1
    echo -e "${GREEN}Node.js $(node -v) 已通过 nvm 安装${NC}"

  elif command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
    echo -e "${YELLOW}正在通过 apt 安装 Node.js 20...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
    apt-get install -y nodejs >/dev/null 2>&1
    echo -e "${GREEN}Node.js $(node -v) 已通过 apt 安装${NC}"

  elif command -v yum >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
    echo -e "${YELLOW}正在通过 yum 安装 Node.js 20...${NC}"
    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
    yum install -y nodejs >/dev/null 2>&1
    echo -e "${GREEN}Node.js $(node -v) 已通过 yum 安装${NC}"

  else
    echo -e "${RED}自动安装失败，请手动安装 Node.js 后重试${NC}"
    echo -e "${YELLOW}参考: https://nodejs.org/en/download${NC}"
    exit 1
  fi

  if ! command -v node >/dev/null 2>&1; then
    echo -e "${RED}Node.js 安装失败，请手动安装后重试${NC}"
    exit 1
  fi
fi

APP_DIR="$HOME/node-sb"
mkdir -p "$APP_DIR" && cd "$APP_DIR"

# ── 源码拉取（直连 + 镜像双源）────────────────────────────────────────────
BASE_URL="https://raw.githubusercontent.com/zaofengyue/node-sb/main"
BASE_URL_MIRROR="https://ghproxy.net/https://raw.githubusercontent.com/zaofengyue/node-sb/main"

download_file() {
  local name="$1"
  echo -e "${GREEN}正在拉取 $name ...${NC}"
  curl -fsSL "$BASE_URL/$name" -o "$name" 2>/dev/null || \
  curl -fsSL "$BASE_URL_MIRROR/$name" -o "$name" 2>/dev/null || \
  wget -q "$BASE_URL/$name" -O "$name" 2>/dev/null || \
  wget -q "$BASE_URL_MIRROR/$name" -O "$name" 2>/dev/null || \
  { echo -e "${RED}$name 下载失败，所有源均不可用${NC}"; exit 1; }
}

download_file index.js
download_file package.json
download_file index.html
download_file sb_manager.sh
echo -e "${GREEN}文件拉取完成${NC}"

# ── 环境变量收集 ─────────────────────────────────────────────────────────────
INPUT_UUID="${UUID:-}"
INPUT_PORT="${PORT:-}"
INPUT_ARGO_PORT="${ARGO_PORT:-}"
INPUT_NAME="${NAME:-}"
INPUT_SUB="${SUB:-}"
INPUT_ARGO_DOMAIN="${ARGO_DOMAIN:-}"
INPUT_ARGO_AUTH="${ARGO_AUTH:-}"
INPUT_HY2_PORT="${HY2_PORT:-}"
INPUT_TUIC_PORT="${TUIC_PORT:-}"
INPUT_REALITY_PORT="${REALITY_PORT:-}"
INPUT_REALITY_DOMAIN="${REALITY_DOMAIN:-}"
INPUT_SS_PORT="${SS_PORT:-}"
INPUT_S5_PORT="${S5_PORT:-}"
INPUT_ANYTLS_PORT="${ANYTLS_PORT:-}"
INPUT_DISABLE_ARGO="${DISABLE_ARGO:-}"
INPUT_CLEANUP_AFTER_DEPLOY="${CLEANUP_AFTER_DEPLOY:-}"

HAS_ENV=false
for v in "$INPUT_UUID" "$INPUT_PORT" "$INPUT_ARGO_PORT" "$INPUT_NAME" "$INPUT_SUB" \
          "$INPUT_ARGO_DOMAIN" "$INPUT_ARGO_AUTH" "$INPUT_HY2_PORT" "$INPUT_TUIC_PORT" \
          "$INPUT_REALITY_PORT" "$INPUT_REALITY_DOMAIN" "$INPUT_SS_PORT" \
          "$INPUT_S5_PORT" "$INPUT_ANYTLS_PORT" "$INPUT_DISABLE_ARGO" "$INPUT_CLEANUP_AFTER_DEPLOY"; do
  [ -n "$v" ] && HAS_ENV=true && break
done

if ! $HAS_ENV; then
  echo ""
  echo -e "${YELLOW}========== 基础配置（留空使用默认值）==========${NC}"
  read -p "UUID（留空自动生成）: "              INPUT_UUID
  INPUT_UUID="$(echo "$INPUT_UUID" | tr -d '[:space:]')"
  read -p "NAME/节点名称前缀（留空自动识别）: " INPUT_NAME
  INPUT_NAME="$(echo "$INPUT_NAME" | tr -d '[:space:]')"

  echo ""
  echo -e "${YELLOW}--- Argo 隧道 ---${NC}"
  read -p "是否启用 Argo 隧道？[Y/n]: " _ARGO_CHOICE
  _ARGO_CHOICE="$(echo "$_ARGO_CHOICE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  if [ "$_ARGO_CHOICE" = "n" ]; then
    INPUT_DISABLE_ARGO="true"
    echo -e "${YELLOW}Argo 已禁用${NC}"
  else
    INPUT_DISABLE_ARGO=""
    echo -e "${GREEN}Argo 已启用（临时隧道），如需固定隧道可通过管理面板 sb 配置${NC}"
  fi

  echo ""
  echo -e "${YELLOW}--- 可选协议（留空跳过）---${NC}"
  echo -e "  ${GREEN}a${NC}. Hysteria2     (UDP)"
  echo -e "  ${GREEN}b${NC}. TUIC v5       (UDP)"
  echo -e "  ${GREEN}c${NC}. VLESS Reality (TCP)"
  echo -e "  ${GREEN}d${NC}. Shadowsocks   (TCP)"
  echo -e "  ${GREEN}e${NC}. Socks5        (TCP)"
  echo -e "  ${GREEN}f${NC}. AnyTLS        (TCP)"
  read -p "选择协议（如 ac 表示启用 a 和 c，留空跳过）: " _PROTO_CHOICE

  if echo "$_PROTO_CHOICE" | grep -qi "a"; then
    read -p "HY2_PORT/Hysteria2 端口(UDP): " INPUT_HY2_PORT
    INPUT_HY2_PORT="$(echo "$INPUT_HY2_PORT" | tr -d '[:space:]')"
  fi
  if echo "$_PROTO_CHOICE" | grep -qi "b"; then
    read -p "TUIC_PORT/TUIC v5 端口(UDP): " INPUT_TUIC_PORT
    INPUT_TUIC_PORT="$(echo "$INPUT_TUIC_PORT" | tr -d '[:space:]')"
  fi
  if echo "$_PROTO_CHOICE" | grep -qi "c"; then
    read -p "REALITY_PORT/VLESS Reality 端口(TCP): " INPUT_REALITY_PORT
    INPUT_REALITY_PORT="$(echo "$INPUT_REALITY_PORT" | tr -d '[:space:]')"
    read -p "REALITY_DOMAIN/Reality 伪装域名（留空默认 www.iij.ad.jp）: " INPUT_REALITY_DOMAIN
    INPUT_REALITY_DOMAIN="$(echo "$INPUT_REALITY_DOMAIN" | tr -d '[:space:]')"
  fi
  if echo "$_PROTO_CHOICE" | grep -qi "d"; then
    read -p "SS_PORT/Shadowsocks 端口(TCP): " INPUT_SS_PORT
    INPUT_SS_PORT="$(echo "$INPUT_SS_PORT" | tr -d '[:space:]')"
  fi
  if echo "$_PROTO_CHOICE" | grep -qi "e"; then
    read -p "S5_PORT/Socks5 端口(TCP): " INPUT_S5_PORT
    INPUT_S5_PORT="$(echo "$INPUT_S5_PORT" | tr -d '[:space:]')"
  fi
  if echo "$_PROTO_CHOICE" | grep -qi "f"; then
    read -p "ANYTLS_PORT/AnyTLS 端口(TCP): " INPUT_ANYTLS_PORT
    INPUT_ANYTLS_PORT="$(echo "$INPUT_ANYTLS_PORT" | tr -d '[:space:]')"
  fi
fi

export UUID="$INPUT_UUID"
export PORT="$INPUT_PORT"
export ARGO_PORT="$INPUT_ARGO_PORT"
export NAME="$INPUT_NAME"
export SUB="$INPUT_SUB"
export ARGO_DOMAIN="$INPUT_ARGO_DOMAIN"
export ARGO_AUTH="$INPUT_ARGO_AUTH"
export HY2_PORT="$INPUT_HY2_PORT"
export TUIC_PORT="$INPUT_TUIC_PORT"
export REALITY_PORT="$INPUT_REALITY_PORT"
export REALITY_DOMAIN="$INPUT_REALITY_DOMAIN"
export SS_PORT="$INPUT_SS_PORT"
export S5_PORT="$INPUT_S5_PORT"
export ANYTLS_PORT="$INPUT_ANYTLS_PORT"
export DISABLE_ARGO="$INPUT_DISABLE_ARGO"
export CLEANUP_AFTER_DEPLOY="$INPUT_CLEANUP_AFTER_DEPLOY"

# ── 快捷命令 ────────────────────────────────────────────────────────────────
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

# sb 管理面板：直接安装已下载的 sb_manager.sh，
# 不再内嵌重复副本，避免两份逻辑分叉维护
cp "$APP_DIR/sb_manager.sh" "$LOCAL_BIN/sb"
chmod +x "$LOCAL_BIN/sb"

cat > "$LOCAL_BIN/sb-sub" << 'SUBCMD'
#!/bin/bash
SUB_FILE="$HOME/world/sub.txt"
[ -f "$SUB_FILE" ] && cat "$SUB_FILE" || echo "sub.txt 不存在，请等待服务启动完成"
SUBCMD
chmod +x "$LOCAL_BIN/sb-sub"

cat > "$LOCAL_BIN/sb-log" << LOGCMD
#!/bin/bash
if systemctl --user is-active node-sb >/dev/null 2>&1; then
  journalctl --user -u node-sb -f
elif [ -f "$APP_DIR/run.log" ]; then
  tail -f "$APP_DIR/run.log"
else
  echo "服务未运行"
fi
LOGCMD
chmod +x "$LOCAL_BIN/sb-log"

cat > "$LOCAL_BIN/sb-del" << DELCMD
#!/bin/bash
echo "正在彻底删除 node-sb..."
systemctl --user stop node-sb 2>/dev/null || true
systemctl --user disable node-sb 2>/dev/null || true
rm -f "\$HOME/.config/systemd/user/node-sb.service"
systemctl --user daemon-reload 2>/dev/null || true
[ -f "$APP_DIR/nodex.pid" ] && kill \$(cat "$APP_DIR/nodex.pid") 2>/dev/null || true
pkill -f "node-sb/index.js" 2>/dev/null || true
pkill -f "sing-box" 2>/dev/null || true
pkill -f "cloudflared" 2>/dev/null || true
for RC in "\$HOME/.bashrc" "\$HOME/.profile" "\$HOME/.bash_profile" "\$HOME/.zshrc"; do
  sed -i '/# node-sb/d' "\$RC" 2>/dev/null || true
  sed -i '/node-sb/d'   "\$RC" 2>/dev/null || true
done
rm -rf "$APP_DIR"
rm -rf "\$HOME/world"
rm -f "$LOCAL_BIN/sb" "$LOCAL_BIN/sb-sub" "$LOCAL_BIN/sb-log" "$LOCAL_BIN/sb-del" "$LOCAL_BIN/sb-edit"
echo "删除完成"
DELCMD
chmod +x "$LOCAL_BIN/sb-del"

cat > "$LOCAL_BIN/sb-edit" << 'EDITCMD'
#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

APP_DIR="$HOME/node-sb"
WRAPPER="$APP_DIR/start.sh"

if [ ! -f "$WRAPPER" ]; then
  echo "未找到 $WRAPPER，请先运行安装脚本"
  exit 1
fi

get_val() {
  grep "^export $1=" "$WRAPPER" | sed 's/.*="\(.*\)"/\1/' | head -1
}

CUR_UUID=$(get_val UUID)
CUR_PORT=$(get_val PORT)
CUR_ARGO_PORT=$(get_val ARGO_PORT)
CUR_NAME=$(get_val NAME)
CUR_SUB=$(get_val SUB)
CUR_ARGO_DOMAIN=$(get_val ARGO_DOMAIN)
CUR_ARGO_AUTH=$(get_val ARGO_AUTH)
CUR_HY2_PORT=$(get_val HY2_PORT)
CUR_TUIC_PORT=$(get_val TUIC_PORT)
CUR_REALITY_PORT=$(get_val REALITY_PORT)
CUR_REALITY_DOMAIN=$(get_val REALITY_DOMAIN)
CUR_SS_PORT=$(get_val SS_PORT)
CUR_S5_PORT=$(get_val S5_PORT)
CUR_ANYTLS_PORT=$(get_val ANYTLS_PORT)
CUR_DISABLE_ARGO=$(get_val DISABLE_ARGO)
CUR_CLEANUP_AFTER_DEPLOY=$(get_val CLEANUP_AFTER_DEPLOY)

echo -e "${GREEN}========== node-sb 配置修改 ==========${NC}"
echo -e "${YELLOW}直接回车保留当前值，输入新值后回车修改${NC}"
echo ""
echo -e "${YELLOW}--- 基础配置 ---${NC}"
read -p "UUID [${CUR_UUID:-自动生成}]: "               IN_UUID
read -p "PORT [${CUR_PORT:-自动分配}]: "               IN_PORT
read -p "ARGO_PORT [${CUR_ARGO_PORT:-8001}]: "         IN_ARGO_PORT
read -p "NAME [${CUR_NAME:-自动识别}]: "               IN_NAME
read -p "SUB [${CUR_SUB:-sub}]: "                      IN_SUB
echo ""
echo -e "${YELLOW}--- Argo 隧道 ---${NC}"
read -p "ARGO_DOMAIN [${CUR_ARGO_DOMAIN:-临时隧道}]: "  IN_ARGO_DOMAIN
read -p "ARGO_AUTH [${CUR_ARGO_AUTH:-临时隧道}]: "      IN_ARGO_AUTH
echo ""
echo -e "${YELLOW}--- 可选协议（直接回车保留当前值，输入空格清除）---${NC}"
read -p "HY2_PORT(UDP)     [${CUR_HY2_PORT:-未启用}]: "         IN_HY2_PORT
read -p "TUIC_PORT(UDP)    [${CUR_TUIC_PORT:-未启用}]: "        IN_TUIC_PORT
read -p "REALITY_PORT(TCP) [${CUR_REALITY_PORT:-未启用}]: "     IN_REALITY_PORT
read -p "REALITY_DOMAIN    [${CUR_REALITY_DOMAIN:-www.iij.ad.jp}]: " IN_REALITY_DOMAIN
read -p "SS_PORT(TCP)      [${CUR_SS_PORT:-未启用}]: "          IN_SS_PORT
read -p "S5_PORT(TCP)      [${CUR_S5_PORT:-未启用}]: "          IN_S5_PORT
read -p "ANYTLS_PORT(TCP)  [${CUR_ANYTLS_PORT:-未启用}]: "      IN_ANYTLS_PORT
read -p "DISABLE_ARGO      [${CUR_DISABLE_ARGO:-false}]: "       IN_DISABLE_ARGO
read -p "CLEANUP_AFTER_DEPLOY（0/false/no 关闭）[${CUR_CLEANUP_AFTER_DEPLOY:-true}]: " IN_CLEANUP_AFTER_DEPLOY

NEW_UUID="${IN_UUID:-$CUR_UUID}"
NEW_PORT="${IN_PORT:-$CUR_PORT}"
NEW_ARGO_PORT="${IN_ARGO_PORT:-$CUR_ARGO_PORT}"
NEW_NAME="${IN_NAME:-$CUR_NAME}"
NEW_SUB="${IN_SUB:-$CUR_SUB}"
NEW_ARGO_DOMAIN="${IN_ARGO_DOMAIN:-$CUR_ARGO_DOMAIN}"
NEW_ARGO_AUTH="${IN_ARGO_AUTH:-$CUR_ARGO_AUTH}"
NEW_HY2_PORT="${IN_HY2_PORT:-$CUR_HY2_PORT}"
NEW_TUIC_PORT="${IN_TUIC_PORT:-$CUR_TUIC_PORT}"
NEW_REALITY_PORT="${IN_REALITY_PORT:-$CUR_REALITY_PORT}"
NEW_REALITY_DOMAIN="${IN_REALITY_DOMAIN:-$CUR_REALITY_DOMAIN}"
NEW_SS_PORT="${IN_SS_PORT:-$CUR_SS_PORT}"
NEW_S5_PORT="${IN_S5_PORT:-$CUR_S5_PORT}"
NEW_ANYTLS_PORT="${IN_ANYTLS_PORT:-$CUR_ANYTLS_PORT}"
NEW_DISABLE_ARGO="${IN_DISABLE_ARGO:-$CUR_DISABLE_ARGO}"
NEW_CLEANUP_AFTER_DEPLOY="${IN_CLEANUP_AFTER_DEPLOY:-$CUR_CLEANUP_AFTER_DEPLOY}"

NODE_BIN="$(command -v node)"

cat > "$WRAPPER" << WRAPEOF
#!/bin/bash
export UUID="$NEW_UUID"
export PORT="$NEW_PORT"
export ARGO_PORT="$NEW_ARGO_PORT"
export NAME="$NEW_NAME"
export SUB="$NEW_SUB"
export ARGO_DOMAIN="$NEW_ARGO_DOMAIN"
export ARGO_AUTH="$NEW_ARGO_AUTH"
export HY2_PORT="$NEW_HY2_PORT"
export TUIC_PORT="$NEW_TUIC_PORT"
export REALITY_PORT="$NEW_REALITY_PORT"
export REALITY_DOMAIN="$NEW_REALITY_DOMAIN"
export SS_PORT="$NEW_SS_PORT"
export S5_PORT="$NEW_S5_PORT"
export ANYTLS_PORT="$NEW_ANYTLS_PORT"
export DISABLE_ARGO="$NEW_DISABLE_ARGO"
export CLEANUP_AFTER_DEPLOY="$NEW_CLEANUP_AFTER_DEPLOY"
cd "$APP_DIR"
nohup $NODE_BIN "$APP_DIR/index.js" >> "$APP_DIR/run.log" 2>&1 &
echo \$! > "$APP_DIR/nodex.pid"
WRAPEOF
chmod +x "$WRAPPER"

SVCFILE="$HOME/.config/systemd/user/node-sb.service"
if [ -f "$SVCFILE" ]; then
  cat > "$SVCFILE" << SVCEOF
[Unit]
Description=node-sb service
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
Environment=UUID=$NEW_UUID
Environment=PORT=$NEW_PORT
Environment=ARGO_PORT=$NEW_ARGO_PORT
Environment=NAME=$NEW_NAME
Environment=SUB=$NEW_SUB
Environment=ARGO_DOMAIN=$NEW_ARGO_DOMAIN
Environment=ARGO_AUTH=$NEW_ARGO_AUTH
Environment=HY2_PORT=$NEW_HY2_PORT
Environment=TUIC_PORT=$NEW_TUIC_PORT
Environment=REALITY_PORT=$NEW_REALITY_PORT
Environment=REALITY_DOMAIN=$NEW_REALITY_DOMAIN
Environment=SS_PORT=$NEW_SS_PORT
Environment=S5_PORT=$NEW_S5_PORT
Environment=ANYTLS_PORT=$NEW_ANYTLS_PORT
Environment=DISABLE_ARGO=$NEW_DISABLE_ARGO
Environment=CLEANUP_AFTER_DEPLOY=$NEW_CLEANUP_AFTER_DEPLOY
ExecStart=$NODE_BIN $APP_DIR/index.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
SVCEOF
  systemctl --user daemon-reload
  systemctl --user restart node-sb
  echo -e "${GREEN}配置已更新，systemd 服务已重启${NC}"
else
  pkill -f "node-sb/index.js" 2>/dev/null || true
  pkill -f "sing-box" 2>/dev/null || true
  pkill -f "cloudflared" 2>/dev/null || true
  sleep 1
  bash "$WRAPPER"
  echo -e "${GREEN}配置已更新，服务已重启${NC}"
fi
echo -e "${GREEN}管理面板: sb${NC}"
echo -e "${GREEN}查看日志: sb-log${NC}"
EDITCMD
chmod +x "$LOCAL_BIN/sb-edit"

# ── PATH 注入 ────────────────────────────────────────────────────────────────
export PATH="$LOCAL_BIN:$PATH"
if ! grep -q "node-sb PATH" "$HOME/.bashrc" 2>/dev/null; then
  for RC in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    if [ -f "$RC" ]; then
      printf '\n# node-sb PATH\nexport PATH="%s:$PATH"\n' "$LOCAL_BIN" >> "$RC"
    fi
  done
fi

# ── 启动包装脚本 ─────────────────────────────────────────────────────────────
WRAPPER="$APP_DIR/start.sh"
NODE_BIN="$(command -v node)"

cat > "$WRAPPER" << WRAPEOF
#!/bin/bash
export UUID="$INPUT_UUID"
export PORT="$INPUT_PORT"
export ARGO_PORT="$INPUT_ARGO_PORT"
export NAME="$INPUT_NAME"
export SUB="$INPUT_SUB"
export ARGO_DOMAIN="$INPUT_ARGO_DOMAIN"
export ARGO_AUTH="$INPUT_ARGO_AUTH"
export HY2_PORT="$INPUT_HY2_PORT"
export TUIC_PORT="$INPUT_TUIC_PORT"
export REALITY_PORT="$INPUT_REALITY_PORT"
export REALITY_DOMAIN="$INPUT_REALITY_DOMAIN"
export SS_PORT="$INPUT_SS_PORT"
export S5_PORT="$INPUT_S5_PORT"
export ANYTLS_PORT="$INPUT_ANYTLS_PORT"
export DISABLE_ARGO="$INPUT_DISABLE_ARGO"
export CLEANUP_AFTER_DEPLOY="$INPUT_CLEANUP_AFTER_DEPLOY"
cd "$APP_DIR"
nohup $NODE_BIN "$APP_DIR/index.js" >> "$APP_DIR/run.log" 2>&1 &
echo \$! > "$APP_DIR/nodex.pid"
WRAPEOF
chmod +x "$WRAPPER"

# ── 开机自启 ─────────────────────────────────────────────────────────────────
USER_SYSTEMD_OK=false
if command -v systemctl >/dev/null 2>&1 && systemctl --user status >/dev/null 2>&1; then
  USER_SYSTEMD_OK=true
fi

if $USER_SYSTEMD_OK; then
  SYSTEMD_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_DIR"
  cat > "$SYSTEMD_DIR/node-sb.service" << SVCEOF
[Unit]
Description=node-sb service
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
Environment=UUID=$INPUT_UUID
Environment=PORT=$INPUT_PORT
Environment=ARGO_PORT=$INPUT_ARGO_PORT
Environment=NAME=$INPUT_NAME
Environment=SUB=$INPUT_SUB
Environment=ARGO_DOMAIN=$INPUT_ARGO_DOMAIN
Environment=ARGO_AUTH=$INPUT_ARGO_AUTH
Environment=HY2_PORT=$INPUT_HY2_PORT
Environment=TUIC_PORT=$INPUT_TUIC_PORT
Environment=REALITY_PORT=$INPUT_REALITY_PORT
Environment=REALITY_DOMAIN=$INPUT_REALITY_DOMAIN
Environment=SS_PORT=$INPUT_SS_PORT
Environment=S5_PORT=$INPUT_S5_PORT
Environment=ANYTLS_PORT=$INPUT_ANYTLS_PORT
Environment=DISABLE_ARGO=$INPUT_DISABLE_ARGO
Environment=CLEANUP_AFTER_DEPLOY=$INPUT_CLEANUP_AFTER_DEPLOY
ExecStart=$NODE_BIN $APP_DIR/index.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
SVCEOF
  systemctl --user daemon-reload
  systemctl --user enable node-sb
  systemctl --user start node-sb
  loginctl enable-linger "$USER" 2>/dev/null || true
  echo ""
  echo -e "${GREEN}服务已通过用户级 systemd 启动并设置开机自启${NC}"
  echo -e "${GREEN}查看日志: sb-log${NC}"
else
  bash "$WRAPPER"
  for RC in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    if [ -f "$RC" ] && ! grep -q "# node-sb autostart" "$RC" 2>/dev/null; then
      printf '\n# node-sb autostart\nif ! pgrep -f "node-sb/index.js" >/dev/null 2>&1; then\n  bash "%s" >/dev/null 2>&1\nfi\n' "$WRAPPER" >> "$RC"
    fi
  done
  echo ""
  echo -e "${GREEN}服务已通过 nohup 后台启动${NC}"
  echo -e "${GREEN}查看日志: sb-log${NC}"
fi

echo ""
echo -e "${GREEN}管理面板: sb${NC}"
echo -e "${GREEN}查看节点: sb-sub${NC}"
echo -e "${GREEN}彻底删除: sb-del${NC}"
echo ""
echo -e "${YELLOW}等待服务启动，节点链接将写入 $APP_DIR/sub.txt${NC}"
