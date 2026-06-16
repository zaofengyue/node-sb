#!/bin/bash
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${YELLOW}========== node-sb 安装 ==========${NC}"

if command -v curl >/dev/null 2>&1; then
  DL="curl -sL"; DL_O="-o"
elif command -v wget >/dev/null 2>&1; then
  DL="wget -q"; DL_O="-O"
else
  echo -e "${RED}缺少 curl 或 wget${NC}"; exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo -e "${YELLOW}未检测到 Node.js，尝试自动安装...${NC}"

  # 优先尝试 nvm（无需 root）
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

  # 其次尝试 apt（需要 root）
  elif command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
    echo -e "${YELLOW}正在通过 apt 安装 Node.js 20...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
    apt-get install -y nodejs >/dev/null 2>&1
    echo -e "${GREEN}Node.js $(node -v) 已通过 apt 安装${NC}"

  # 其次尝试 yum（需要 root）
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

  # 安装后再次检测
  if ! command -v node >/dev/null 2>&1; then
    echo -e "${RED}Node.js 安装失败，请手动安装后重试${NC}"
    exit 1
  fi
fi

APP_DIR="$HOME/node-sb"
mkdir -p "$APP_DIR" && cd "$APP_DIR"

BASE_URL="https://raw.githubusercontent.com/zaofengyue/node-sb/main"
echo -e "${GREEN}正在拉取源码...${NC}"
$DL "$BASE_URL/index.js"     $DL_O index.js
$DL "$BASE_URL/package.json" $DL_O package.json
$DL "$BASE_URL/index.html"   $DL_O index.html
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
INPUT_DISABLE_ARGO="${DISABLE_ARGO:-}"

HAS_ENV=false
for v in "$INPUT_UUID" "$INPUT_PORT" "$INPUT_ARGO_PORT" "$INPUT_NAME" "$INPUT_SUB" \
          "$INPUT_ARGO_DOMAIN" "$INPUT_ARGO_AUTH" "$INPUT_HY2_PORT" "$INPUT_TUIC_PORT" \
          "$INPUT_REALITY_PORT" "$INPUT_REALITY_DOMAIN" "$INPUT_SS_PORT" "$INPUT_DISABLE_ARGO"; do
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
  read -p "HY2_PORT/Hysteria2 端口(UDP): "        INPUT_HY2_PORT
  read -p "TUIC_PORT/TUIC v5 端口(UDP): "         INPUT_TUIC_PORT
  read -p "REALITY_PORT/VLESS Reality 端口(TCP): " INPUT_REALITY_PORT
  read -p "REALITY_DOMAIN/Reality 伪装域名（留空默认 www.iij.ad.jp）: " INPUT_REALITY_DOMAIN
  read -p "SS_PORT/Shadowsocks 2022 端口(TCP): "  INPUT_SS_PORT
  read -p "DISABLE_ARGO/禁用 Argo 隧道（填 true 禁用，留空启用）: " INPUT_DISABLE_ARGO
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
export DISABLE_ARGO="$INPUT_DISABLE_ARGO"

# ── 快捷命令 ────────────────────────────────────────────────────────────────
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

cat > "$LOCAL_BIN/sb" << 'SBMANAGER'
#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
GRAY='\033[0;90m'
WHITE='\033[0;97m'
RESET='\033[0m'

APP_DIR="$HOME/node-sb"
WRAPPER="$APP_DIR/start.sh"
SUB_FILE="$APP_DIR/sub.txt"
LOG_FILE="$APP_DIR/run.log"
SB_BIN="$HOME/sing-box/sing-box"

get_val() {
  grep "^export $1=" "$WRAPPER" 2>/dev/null | sed 's/.*="\(.*\)"/\1/' | head -1
}

set_val() {
  local key="$1" val="$2"
  if grep -q "^export $key=" "$WRAPPER" 2>/dev/null; then
    sed -i "s|^export $key=.*|export $key=\"$val\"|" "$WRAPPER"
  else
    sed -i "/^cd /i export $key=\"$val\"" "$WRAPPER"
  fi
}

check_status() {
  local node_s sb_s cf_s
  pgrep -f "node.*index.js" >/dev/null 2>&1 && node_s="${GREEN}Node.js ✓${RESET}" || node_s="${RED}Node.js ✗${RESET}"
  pgrep -f "sing-box" >/dev/null 2>&1      && sb_s="${GREEN}sing-box ✓${RESET}"  || sb_s="${RED}sing-box ✗${RESET}"
  pgrep -f "cloudflared" >/dev/null 2>&1   && cf_s="${GREEN}cloudflared ✓${RESET}" || cf_s="${RED}cloudflared ✗${RESET}"
  echo -e "状态: $node_s  $sb_s  $cf_s"
}

restart_service() {
  echo -e "${YELLOW}正在重启服务...${RESET}"
  pkill -f "node.*node-sb/index.js" 2>/dev/null || true
  pkill -f "sing-box" 2>/dev/null || true
  pkill -f "cloudflared" 2>/dev/null || true
  sleep 1
  if systemctl --user is-enabled node-sb >/dev/null 2>&1; then
    systemctl --user restart node-sb
  else
    bash "$WRAPPER"
  fi
  echo -e "${GREEN}服务已重启${RESET}"
  sleep 2
}

press_any_key() {
  echo ""
  echo -e "${GRAY}按回车键返回...${RESET}"
  read -r
}

# ── 主界面 ───────────────────────────────────────────────────────────────────
main_menu() {
  while true; do
    clear
    echo -e "${GREEN}======= node-sb 管理面板 =======${RESET}"
    check_status
    echo -e "${GRAY}--------------------------------${RESET}"
    echo -e "${WHITE}1. 查看节点订阅${RESET}"
    echo -e "${WHITE}2. 查看运行日志${RESET}"
    echo -e "${WHITE}3. 修改配置${RESET}"
    echo -e "${WHITE}4. 重启服务${RESET}"
    echo -e "${WHITE}5. 更新 sing-box${RESET}"
    echo -e "${WHITE}6. 彻底删除${RESET}"
    echo -e "${WHITE}0. 退出${RESET}"
    echo -e "${GRAY}--------------------------------${RESET}"
    echo -ne "${GRAY}请输入选项: ${RESET}"
    read -r opt
    case "$opt" in
      1) menu_sub ;;
      2) menu_log ;;
      3) menu_config ;;
      4) restart_service ;;
      5) menu_update ;;
      6) menu_delete ;;
      0) exit 0 ;;
      *) ;;
    esac
  done
}

# ── 查看节点订阅 ─────────────────────────────────────────────────────────────
menu_sub() {
  clear
  echo -e "${GREEN}======= 节点订阅 =======${RESET}"

  if [ ! -f "$SUB_FILE" ]; then
    echo -e "${RED}sub.txt 不存在，请等待服务启动完成${RESET}"
    press_any_key; return
  fi

  local decoded
  decoded=$(cat "$SUB_FILE" | base64 -d 2>/dev/null)
  if [ -z "$decoded" ]; then
    echo -e "${RED}订阅内容为空${RESET}"
    press_any_key; return
  fi

  echo -e "${GRAY}已启用协议:${RESET}"
  echo "$decoded" | while IFS= read -r line; do
    case "$line" in
      vmess://*)    echo -e "${GREEN}✓ VMess${RESET}" ;;
      vless://*Argo*|vless://*ws*) ;;
      trojan://*)   echo -e "${GREEN}✓ Trojan${RESET}" ;;
      hysteria2://*)echo -e "${GREEN}✓ Hysteria2${RESET}" ;;
      tuic://*)     echo -e "${GREEN}✓ TUIC v5${RESET}" ;;
      ss://*)       echo -e "${GREEN}✓ Shadowsocks${RESET}" ;;
    esac
  done

  # 更友好：按协议逐行显示完整链接
  echo -e "${GRAY}--------------------------------${RESET}"
  echo -e "${GRAY}节点链接:${RESET}"
  echo "$decoded" | while IFS= read -r line; do
    [ -n "$line" ] && echo -e "${CYAN}$line${RESET}"
  done

  press_any_key
}

# ── 查看运行日志 ─────────────────────────────────────────────────────────────
menu_log() {
  clear
  echo -e "${GREEN}======= 运行日志（最近 50 条，Ctrl+C 退出）=======${RESET}"
  echo ""
  if systemctl --user is-active node-sb >/dev/null 2>&1; then
    journalctl --user -u node-sb -n 50 -f
  elif [ -f "$LOG_FILE" ]; then
    tail -n 50 -f "$LOG_FILE"
  else
    echo -e "${RED}未找到日志文件${RESET}"
    press_any_key
  fi
}

# ── 修改配置二级菜单 ─────────────────────────────────────────────────────────
menu_config() {
  while true; do
    clear
    echo -e "${GREEN}======= 修改配置 =======${RESET}"
    echo -e "${GRAY}--------------------------------${RESET}"
    echo -e "${WHITE}1. UUID${RESET}"
    echo -e "${WHITE}2. Argo 隧道模式${RESET}"
    echo -e "${WHITE}3. 可选协议端口${RESET}"
    echo -e "${WHITE}0. 返回${RESET}"
    echo -e "${GRAY}--------------------------------${RESET}"
    echo -ne "${GRAY}请输入选项: ${RESET}"
    read -r opt
    case "$opt" in
      1) config_uuid ;;
      2) config_argo ;;
      3) config_proto ;;
      0) return ;;
      *) ;;
    esac
  done
}

# ── 修改 UUID（三级）────────────────────────────────────────────────────────
config_uuid() {
  clear
  echo -e "${GREEN}======= 修改 UUID =======${RESET}"
  local cur
  cur=$(get_val UUID)
  echo -e "${GRAY}当前: ${CYAN}${cur:-未设置}${RESET}"
  echo -e "${GRAY}--------------------------------${RESET}"
  echo -e "${WHITE}新 UUID（留空自动生成，回车确认）:${RESET}"
  echo -ne "${CYAN}"
  read -r new_uuid
  echo -ne "${RESET}"

  if [ -z "$new_uuid" ]; then
    new_uuid=$(node -e "console.log(require('crypto').randomUUID())" 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null)
  fi

  echo ""
  echo -e "${YELLOW}⚠ 修改后将自动:${RESET}"
  echo -e "${YELLOW}  · 删除 reality-keys.json 重新生成密钥${RESET}"
  echo -e "${YELLOW}  · 重启所有服务${RESET}"
  echo -e "${YELLOW}  · 更新订阅链接${RESET}"
  echo ""
  echo -e "${GRAY}新 UUID: ${CYAN}$new_uuid${RESET}"
  echo -ne "${GRAY}确认修改并重启? [y/N]: ${RESET}"
  read -r confirm
  if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    set_val UUID "$new_uuid"
    rm -f "$HOME/reality-keys.json"
    restart_service
    echo -e "${GREEN}UUID 已更新${RESET}"
    press_any_key
  fi
}

# ── Argo 隧道模式（三级）────────────────────────────────────────────────────
config_argo() {
  while true; do
    clear
    echo -e "${GREEN}======= Argo 隧道模式 =======${RESET}"
    local cur_domain cur_auth cur_port cur_disable
    cur_domain=$(get_val ARGO_DOMAIN)
    cur_auth=$(get_val ARGO_AUTH)
    cur_port=$(get_val ARGO_PORT)
    cur_disable=$(get_val DISABLE_ARGO)

    if [ "$cur_disable" = "true" ]; then
      echo -e "${GRAY}当前: ${RED}已禁用${RESET}"
    elif [ -n "$cur_domain" ] && [ -n "$cur_auth" ]; then
      echo -e "${GRAY}当前: ${CYAN}固定隧道 ($cur_domain)${RESET}"
    else
      echo -e "${GRAY}当前: ${CYAN}临时隧道${RESET}"
    fi

    echo -e "${GRAY}--------------------------------${RESET}"
    echo -e "${WHITE}1. 临时隧道（自动获取域名）${RESET}"
    echo -e "${WHITE}2. 固定隧道${RESET}"
    echo -e "${WHITE}3. 禁用 Argo${RESET}"
    echo -e "${WHITE}0. 返回${RESET}"
    echo -e "${GRAY}--------------------------------${RESET}"
    echo -ne "${GRAY}请输入选项: ${RESET}"
    read -r opt

    case "$opt" in
      1)
        echo -ne "${GRAY}确认切换为临时隧道并重启? [y/N]: ${RESET}"
        read -r confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
          set_val ARGO_DOMAIN ""
          set_val ARGO_AUTH ""
          set_val DISABLE_ARGO ""
          restart_service
          press_any_key
        fi
        ;;
      2)
        echo ""
        echo -e "${GRAY}→ 固定隧道配置:${RESET}"
        echo -ne "${WHITE}ARGO_DOMAIN [当前: ${CYAN}${cur_domain:-空}${WHITE}]: ${RESET}"
        read -r new_domain
        echo -ne "${WHITE}ARGO_AUTH   [当前: ${CYAN}${cur_auth:0:12}...${WHITE}]: ${RESET}"
        read -r new_auth
        echo -ne "${WHITE}ARGO_PORT   [当前: ${CYAN}${cur_port:-8001}${WHITE}]: ${RESET}"
        read -r new_port
        new_domain="${new_domain:-$cur_domain}"
        new_auth="${new_auth:-$cur_auth}"
        new_port="${new_port:-${cur_port:-8001}}"
        echo ""
        echo -ne "${GRAY}确认修改并重启? [y/N]: ${RESET}"
        read -r confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
          set_val ARGO_DOMAIN "$new_domain"
          set_val ARGO_AUTH "$new_auth"
          set_val ARGO_PORT "$new_port"
          set_val DISABLE_ARGO ""
          restart_service
          press_any_key
        fi
        ;;
      3)
        echo -ne "${GRAY}确认禁用 Argo 并重启? [y/N]: ${RESET}"
        read -r confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
          set_val DISABLE_ARGO "true"
          set_val ARGO_DOMAIN ""
          set_val ARGO_AUTH ""
          restart_service
          press_any_key
        fi
        ;;
      0) return ;;
      *) ;;
    esac
  done
}

# ── 可选协议端口（三级）─────────────────────────────────────────────────────
config_proto() {
  while true; do
    clear
    echo -e "${GREEN}======= 可选协议端口 =======${RESET}"
    local hy2 tuic reality reality_domain ss
    hy2=$(get_val HY2_PORT)
    tuic=$(get_val TUIC_PORT)
    reality=$(get_val REALITY_PORT)
    reality_domain=$(get_val REALITY_DOMAIN)
    ss=$(get_val SS_PORT)

    echo -e "${GRAY}--------------------------------${RESET}"
    echo -e "${WHITE}1. Hysteria2    (UDP) [${CYAN}${hy2:-未启用}${WHITE}]${RESET}"
    echo -e "${WHITE}2. TUIC         (UDP) [${CYAN}${tuic:-未启用}${WHITE}]${RESET}"
    echo -e "${WHITE}3. VLESS Reality(TCP) [${CYAN}${reality:-未启用}${WHITE}]${RESET}"
    echo -e "${WHITE}4. Reality Domain     [${CYAN}${reality_domain:-www.iij.ad.jp}${WHITE}]${RESET}"
    echo -e "${WHITE}5. Shadowsocks  (TCP) [${CYAN}${ss:-未启用}${WHITE}]${RESET}"
    echo -e "${GRAY}--------------------------------${RESET}"
    echo -e "${WHITE}0. 确认修改并重启${RESET}"
    echo -e "${GRAY}--------------------------------${RESET}"
    echo -ne "${GRAY}请输入选项: ${RESET}"
    read -r opt

    case "$opt" in
      1)
        echo -ne "${GRAY}HY2_PORT（留空禁用）[当前: ${CYAN}${hy2:-未启用}${GRAY}]: ${RESET}"
        read -r val
        if [ "$val" = " " ] || [ -z "$val" ] && [ -n "$hy2" ]; then
          set_val HY2_PORT ""
          echo -e "${YELLOW}Hysteria2 已禁用${RESET}"
        elif [ -n "$val" ]; then
          set_val HY2_PORT "$val"
          echo -e "${GREEN}已更新为: $val${RESET}"
        fi
        sleep 1
        ;;
      2)
        echo -ne "${GRAY}TUIC_PORT（留空禁用）[当前: ${CYAN}${tuic:-未启用}${GRAY}]: ${RESET}"
        read -r val
        if [ "$val" = " " ] || [ -z "$val" ] && [ -n "$tuic" ]; then
          set_val TUIC_PORT ""
          echo -e "${YELLOW}TUIC 已禁用${RESET}"
        elif [ -n "$val" ]; then
          set_val TUIC_PORT "$val"
          echo -e "${GREEN}已更新为: $val${RESET}"
        fi
        sleep 1
        ;;
      3)
        echo -ne "${GRAY}REALITY_PORT（留空禁用）[当前: ${CYAN}${reality:-未启用}${GRAY}]: ${RESET}"
        read -r val
        if [ "$val" = " " ] || [ -z "$val" ] && [ -n "$reality" ]; then
          set_val REALITY_PORT ""
          echo -e "${YELLOW}VLESS Reality 已禁用${RESET}"
        elif [ -n "$val" ]; then
          set_val REALITY_PORT "$val"
          echo -e "${GREEN}已更新为: $val${RESET}"
        fi
        sleep 1
        ;;
      4)
        echo -ne "${GRAY}REALITY_DOMAIN [当前: ${CYAN}${reality_domain:-www.iij.ad.jp}${GRAY}]: ${RESET}"
        read -r val
        if [ -n "$val" ]; then
          set_val REALITY_DOMAIN "$val"
          rm -f "$HOME/reality-keys.json"
          echo -e "${GREEN}已更新为: $val${RESET}"
          echo -e "${YELLOW}已清除 Reality 密钥，重启后重新生成${RESET}"
        fi
        sleep 1
        ;;
      5)
        echo -ne "${GRAY}SS_PORT（留空禁用）[当前: ${CYAN}${ss:-未启用}${GRAY}]: ${RESET}"
        read -r val
        if [ "$val" = " " ] || [ -z "$val" ] && [ -n "$ss" ]; then
          set_val SS_PORT ""
          echo -e "${YELLOW}Shadowsocks 已禁用${RESET}"
        elif [ -n "$val" ]; then
          set_val SS_PORT "$val"
          echo -e "${GREEN}已更新为: $val${RESET}"
        fi
        sleep 1
        ;;
      0)
        echo -ne "${GRAY}确认修改并重启? [y/N]: ${RESET}"
        read -r confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
          restart_service
        fi
        return
        ;;
      *) ;;
    esac
  done
}

# ── 更新 sing-box ────────────────────────────────────────────────────────────
menu_update() {
  clear
  echo -e "${GREEN}======= 更新 sing-box =======${RESET}"

  local cur_ver latest_ver
  if [ -f "$SB_BIN" ]; then
    cur_ver=$("$SB_BIN" version 2>/dev/null | grep -oP 'sing-box version \K[\d.]+' | head -1)
    echo -e "${GRAY}当前版本: ${CYAN}${cur_ver:-未知}${RESET}"
  else
    echo -e "${GRAY}当前版本: ${RED}未安装${RESET}"
  fi

  echo -e "${GRAY}正在获取最新版本...${RESET}"
  latest_ver=$(curl -sL "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/' | head -1)
  echo -e "${GRAY}最新版本: ${GREEN}v${latest_ver:-获取失败}${RESET}"

  echo -e "${GRAY}--------------------------------${RESET}"
  echo -e "${WHITE}1. 确认更新${RESET}"
  echo -e "${WHITE}0. 取消返回${RESET}"
  echo -e "${GRAY}--------------------------------${RESET}"
  echo -ne "${GRAY}请输入选项: ${RESET}"
  read -r opt

  if [ "$opt" = "1" ] && [ -n "$latest_ver" ]; then
    echo -e "${YELLOW}正在下载 sing-box v${latest_ver}...${RESET}"
    local arch
    arch=$(uname -m)
    case "$arch" in
      x86_64)  arch="amd64" ;;
      aarch64) arch="arm64" ;;
      armv7*)  arch="armv7" ;;
      *)       arch="amd64" ;;
    esac
    local url="https://github.com/SagerNet/sing-box/releases/download/v${latest_ver}/sing-box-${latest_ver}-linux-${arch}.tar.gz"
    local tmp="$HOME/sb_update.tar.gz"
    curl -sL "$url" -o "$tmp" && \
    tar -xzf "$tmp" -C "$HOME/sing-box" --strip-components=1 && \
    chmod +x "$SB_BIN" && \
    rm -f "$tmp"
    echo -e "${GREEN}更新完成，正在重启...${RESET}"
    restart_service
  fi
  press_any_key
}

# ── 彻底删除 ─────────────────────────────────────────────────────────────────
menu_delete() {
  clear
  echo -e "${RED}======= 彻底删除 =======${RESET}"
  echo -e "${YELLOW}⚠ 将删除所有文件、进程和自启配置${RESET}"
  echo -e "${GRAY}--------------------------------${RESET}"
  echo -e "${WHITE}1. 确认删除${RESET}"
  echo -e "${WHITE}0. 取消返回${RESET}"
  echo -e "${GRAY}--------------------------------${RESET}"
  echo -ne "${GRAY}请输入选项: ${RESET}"
  read -r opt
  if [ "$opt" = "1" ]; then
    echo -ne "${RED}再次确认，输入 yes 继续: ${RESET}"
    read -r confirm
    if [ "$confirm" = "yes" ]; then
      sb-del
      exit 0
    fi
  fi
}

main_menu
SBMANAGER
chmod +x "$LOCAL_BIN/sb"

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
pkill -f "sing-box" 2>/dev/null || true
pkill -f "cloudflared" 2>/dev/null || true
for RC in "\$HOME/.bashrc" "\$HOME/.profile" "\$HOME/.bash_profile" "\$HOME/.zshrc"; do
  sed -i '/# node-sb/d' "\$RC" 2>/dev/null || true
  sed -i '/node-sb/d'   "\$RC" 2>/dev/null || true
done
rm -rf "$APP_DIR"
rm -f "\$HOME/cloudflared"
rm -rf "\$HOME/sing-box"
rm -f "\$HOME/uuid.txt" "\$HOME/sb-config.json" "\$HOME/reality-keys.json"
rm -rf "\$HOME/certs"
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
CUR_DISABLE_ARGO=$(get_val DISABLE_ARGO)

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
read -p "DISABLE_ARGO      [${CUR_DISABLE_ARGO:-false}]: "        IN_DISABLE_ARGO

# 直接回车保留当前值；输入空格再回车则清空
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
NEW_DISABLE_ARGO="${IN_DISABLE_ARGO:-$CUR_DISABLE_ARGO}"

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
export DISABLE_ARGO="$NEW_DISABLE_ARGO"
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
Environment=DISABLE_ARGO=$NEW_DISABLE_ARGO
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
export DISABLE_ARGO="$INPUT_DISABLE_ARGO"
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
Environment=DISABLE_ARGO=$INPUT_DISABLE_ARGO
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
