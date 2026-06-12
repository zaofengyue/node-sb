#!/bin/bash
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}========== node-sb 一键安装 ==========${NC}"

# ── 依赖检查 ────────────────────────────────────────────────────────────────
if command -v curl >/dev/null 2>&1; then
  DL="curl -sL"
  DL_O="-o"
elif command -v wget >/dev/null 2>&1; then
  DL="wget -q"
  DL_O="-O"
else
  echo -e "${RED}缺少 curl 或 wget${NC}"
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo -e "${RED}缺少 node，请先安装 Node.js${NC}"
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo -e "${RED}缺少 unzip，请先安装${NC}"
  exit 1
fi

REPO="zaofengyue/node-sb"
APP_DIR="$HOME/node-sb"
mkdir -p "$APP_DIR" && cd "$APP_DIR"

# ── 从 Releases 下载最新混淆包 ──────────────────────────────────────────────
echo -e "${GREEN}正在获取最新版本...${NC}"

RELEASE_URL="https://api.github.com/repos/${REPO}/releases/latest"
LATEST_ZIP_URL=$(curl -s "$RELEASE_URL" \
  | grep '"browser_download_url"' \
  | grep '\.zip"' \
  | head -1 \
  | sed 's/.*"browser_download_url": *"\(.*\)".*/\1/')

if [ -z "$LATEST_ZIP_URL" ]; then
  echo -e "${RED}获取 Release 失败，请检查网络或 Releases 是否已发布${NC}"
  exit 1
fi

echo -e "${GREEN}正在下载: $LATEST_ZIP_URL${NC}"
$DL "$LATEST_ZIP_URL" $DL_O node-sb-release.zip
unzip -qo node-sb-release.zip
rm -f node-sb-release.zip
echo -e "${GREEN}文件解压完成${NC}"

# ── 环境变量收集 ─────────────────────────────────────────────────────────────
INPUT_UUID="${UUID:-}"
INPUT_PORT="${PORT:-}"
INPUT_ARGO_PORT="${ARGO_PORT:-}"
INPUT_NAME="${NAME:-}"
INPUT_SUB="${SUB:-}"
INPUT_ARGO_DOMAIN="${ARGO_DOMAIN:-}"
INPUT_ARGO_AUTH="${ARGO_AUTH:-}"

if [ -n "$INPUT_UUID" ] || \
   [ -n "$INPUT_PORT" ] || \
   [ -n "$INPUT_ARGO_PORT" ] || \
   [ -n "$INPUT_NAME" ] || \
   [ -n "$INPUT_SUB" ] || \
   [ -n "$INPUT_ARGO_DOMAIN" ] || \
   [ -n "$INPUT_ARGO_AUTH" ]; then
  :
else
  echo ""
  echo -e "${YELLOW}========== 环境变量配置（留空使用默认值）==========${NC}"
  read -p "UUID（留空自动生成）: "              INPUT_UUID
  read -p "PORT（留空自动分配）: "              INPUT_PORT
  read -p "ARGO_PORT（留空默认 8001）: "        INPUT_ARGO_PORT
  read -p "NAME/节点名称前缀（留空自动识别）: " INPUT_NAME
  read -p "SUB/订阅路径（留空默认 sub）: "      INPUT_SUB
  echo ""
  echo -e "${YELLOW}--- Argo 隧道配置（留空使用临时隧道）---${NC}"
  read -p "ARGO_DOMAIN/固定隧道域名: " INPUT_ARGO_DOMAIN
  read -p "ARGO_AUTH/固定隧道 Token: " INPUT_ARGO_AUTH
fi

export UUID="$INPUT_UUID"
export PORT="$INPUT_PORT"
export ARGO_PORT="$INPUT_ARGO_PORT"
export NAME="$INPUT_NAME"
export SUB="$INPUT_SUB"
export ARGO_DOMAIN="$INPUT_ARGO_DOMAIN"
export ARGO_AUTH="$INPUT_ARGO_AUTH"

# ── 快捷命令 ────────────────────────────────────────────────────────────────
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

cat > "$LOCAL_BIN/sb-sub" << 'SUBCMD'
#!/bin/bash
SUB_FILE="$HOME/node-sb/sub.txt"
if [ -f "$SUB_FILE" ]; then
  cat "$SUB_FILE"
else
  echo "sub.txt 不存在，请等待服务启动完成"
fi
SUBCMD
chmod +x "$LOCAL_BIN/sb-sub"

cat > "$LOCAL_BIN/sb-log" << LOGCMD
#!/bin/bash
LOG_FILE="$APP_DIR/run.log"
if systemctl --user is-active node-sb >/dev/null 2>&1; then
  journalctl --user -u node-sb -f
elif [ -f "\$LOG_FILE" ]; then
  tail -f "\$LOG_FILE"
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

if [ -f "$APP_DIR/nodex.pid" ]; then
  PID=\$(cat "$APP_DIR/nodex.pid")
  kill "\$PID" 2>/dev/null || true
fi
pkill -f "node-sb/index.js" 2>/dev/null || true

for RC_FILE in "\$HOME/.bashrc" "\$HOME/.profile" "\$HOME/.bash_profile" "\$HOME/.zshrc"; do
  sed -i '/# node-sb PATH/d'      "\$RC_FILE" 2>/dev/null || true
  sed -i '/# node-sb autostart/d' "\$RC_FILE" 2>/dev/null || true
  sed -i '/node-sb/d'             "\$RC_FILE" 2>/dev/null || true
done

rm -rf "$APP_DIR"
rm -f "\$HOME/sb.tar.gz" "\$HOME/cloudflared"
rm -rf "\$HOME/sing-box"
rm -f "\$HOME/uuid.txt" "\$HOME/sb-config.json"
rm -f "$LOCAL_BIN/sb-sub" "$LOCAL_BIN/sb-log" "$LOCAL_BIN/sb-del"
echo "删除完成"
DELCMD
chmod +x "$LOCAL_BIN/sb-del"

# ── PATH 注入 ────────────────────────────────────────────────────────────────
if ! echo "$PATH" | grep -q "$LOCAL_BIN"; then
  for RC_FILE in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    if [ -f "$RC_FILE" ]; then
      echo "" >> "$RC_FILE"
      echo "# node-sb PATH" >> "$RC_FILE"
      echo "export PATH=\"$LOCAL_BIN:\$PATH\"" >> "$RC_FILE"
    fi
  done
  export PATH="$LOCAL_BIN:$PATH"
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

cd "$APP_DIR"
nohup $NODE_BIN "$APP_DIR/index.js" >> "$APP_DIR/run.log" 2>&1 &
echo \$! > "$APP_DIR/nodex.pid"
WRAPEOF
chmod +x "$WRAPPER"

# ── 开机自启：优先用户级 systemd，否则写入启动文件 ──────────────────────────
USER_SYSTEMD_OK=false
if command -v systemctl >/dev/null 2>&1 && systemctl --user status >/dev/null 2>&1; then
  USER_SYSTEMD_OK=true
fi

if $USER_SYSTEMD_OK; then
  SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_USER_DIR"

  cat > "$SYSTEMD_USER_DIR/node-sb.service" << EOF
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
ExecStart=$NODE_BIN $APP_DIR/index.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable node-sb
  systemctl --user start node-sb
  loginctl enable-linger "$USER" 2>/dev/null || true

  echo ""
  echo -e "${GREEN}服务已通过用户级 systemd 启动并设置开机自启${NC}"
  echo -e "${GREEN}查看日志: sb-log${NC}"

else
  bash "$WRAPPER"

  for RC_FILE in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    if [ -f "$RC_FILE" ] && ! grep -q "# node-sb autostart" "$RC_FILE" 2>/dev/null; then
      cat >> "$RC_FILE" << RCEOF

# node-sb autostart
if ! pgrep -f "node-sb/index.js" >/dev/null 2>&1; then
  bash "$WRAPPER" >/dev/null 2>&1
fi
RCEOF
    fi
  done

  echo ""
  echo -e "${GREEN}服务已通过 nohup 后台启动${NC}"
  echo -e "${GREEN}查看日志: sb-log${NC}"
fi

echo ""
echo -e "${GREEN}查看节点: sb-sub${NC}"
echo -e "${GREEN}彻底删除: sb-del${NC}"
echo ""
echo -e "${YELLOW}等待服务启动，节点链接将写入 $APP_DIR/sub.txt${NC}"
