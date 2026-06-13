#!/bin/bash
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}========== node-sb 一键安装 ==========${NC}"

if command -v curl >/dev/null 2>&1; then
  DL="curl -sL"; DL_O="-o"
elif command -v wget >/dev/null 2>&1; then
  DL="wget -q"; DL_O="-O"
else
  echo -e "${RED}缺少 curl 或 wget${NC}"; exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo -e "${RED}缺少 node，请先安装 Node.js${NC}"; exit 1
fi

REPO="zaofengyue/node-sb"
APP_DIR="$HOME/node-sb"
mkdir -p "$APP_DIR" && cd "$APP_DIR"

echo -e "${GREEN}正在获取最新版本...${NC}"
LATEST_ZIP_URL=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep '"browser_download_url"' | grep '\.zip"' | head -1 \
  | sed 's/.*"browser_download_url": *"\(.*\)".*/\1/')

if [ -z "$LATEST_ZIP_URL" ]; then
  echo -e "${RED}获取 Release 失败${NC}"; exit 1
fi

echo -e "${GREEN}正在下载: $LATEST_ZIP_URL${NC}"
$DL "$LATEST_ZIP_URL" $DL_O node-sb-release.zip
unzip -qo node-sb-release.zip && rm -f node-sb-release.zip
echo -e "${GREEN}文件解压完成${NC}"

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

HAS_ENV=false
for v in "$INPUT_UUID" "$INPUT_PORT" "$INPUT_ARGO_PORT" "$INPUT_NAME" "$INPUT_SUB" \
          "$INPUT_ARGO_DOMAIN" "$INPUT_ARGO_AUTH" "$INPUT_HY2_PORT" "$INPUT_TUIC_PORT" \
          "$INPUT_REALITY_PORT" "$INPUT_REALITY_DOMAIN" "$INPUT_SS_PORT"; do
  [ -n "$v" ] && HAS_ENV=true && break
done

if ! $HAS_ENV; then
  echo ""
  echo -e "${YELLOW}========== 基础配置（留空使用默认值）==========${NC}"
  read -p "UUID（留空自动生成）: "              INPUT_UUID
  read -p "PORT（留空自动分配）: "              INPUT_PORT
  read -p "ARGO_PORT（留空默认 8001）: "        INPUT_ARGO_PORT
  read -p "NAME/节点名称前缀（留空自动识别）: " INPUT_NAME
  read -p "SUB/订阅路径（留空默认 sub）: "      INPUT_SUB
  echo ""
  echo -e "${YELLOW}--- Argo 隧道（留空使用临时隧道）---${NC}"
  read -p "ARGO_DOMAIN/固定隧道域名: "  INPUT_ARGO_DOMAIN
  read -p "ARGO_AUTH/固定隧道 Token: "  INPUT_ARGO_AUTH
  echo ""
  echo -e "${YELLOW}--- 可选协议（留空不启用）---${NC}"
  read -p "HY2_PORT/Hysteria2 端口: "         INPUT_HY2_PORT
  read -p "TUIC_PORT/TUIC v5 端口: "          INPUT_TUIC_PORT
  read -p "REALITY_PORT/VLESS Reality 端口: " INPUT_REALITY_PORT
  read -p "REALITY_DOMAIN/Reality 伪装域名（留空默认 addons.mozilla.org）: " INPUT_REALITY_DOMAIN
  read -p "SS_PORT/Shadowsocks 端口: "        INPUT_SS_PORT
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

LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

cat > "$LOCAL_BIN/sb-sub" << 'SUBCMD'
#!/bin/bash
SUB_FILE="$HOME/node-sb/sub.txt"
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
for RC in "\$HOME/.bashrc" "\$HOME/.profile" "\$HOME/.bash_profile" "\$HOME/.zshrc"; do
  sed -i '/# node-sb/d' "\$RC" 2>/dev/null || true
  sed -i '/node-sb/d'   "\$RC" 2>/dev/null || true
done
rm -rf "$APP_DIR" "\$HOME/sb.tar.gz" "\$HOME/cloudflared" "\$HOME/sing-box"
rm -f "\$HOME/uuid.txt" "\$HOME/sb-config.json" "\$HOME/reality-keys.json"
rm -rf "\$HOME/certs"
rm -f "$LOCAL_BIN/sb-sub" "$LOCAL_BIN/sb-log" "$LOCAL_BIN/sb-del"
echo "删除完成"
DELCMD
chmod +x "$LOCAL_BIN/sb-del"

if ! echo "$PATH" | grep -q "$LOCAL_BIN"; then
  for RC in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    if [ -f "$RC" ]; then
      printf '\n# node-sb PATH\nexport PATH="%s:$PATH"\n' "$LOCAL_BIN" >> "$RC"
    fi
  done
  export PATH="$LOCAL_BIN:$PATH"
fi

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
cd "$APP_DIR"
nohup $NODE_BIN "$APP_DIR/index.js" >> "$APP_DIR/run.log" 2>&1 &
echo \$! > "$APP_DIR/nodex.pid"
WRAPEOF
chmod +x "$WRAPPER"

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
echo -e "${GREEN}查看节点: sb-sub${NC}"
echo -e "${GREEN}彻底删除: sb-del${NC}"
echo ""
echo -e "${YELLOW}等待服务启动，节点链接将写入 $APP_DIR/sub.txt${NC}"
