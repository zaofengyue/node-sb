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
      vmess://*)     echo -e "${GREEN}✓ VMess${RESET}" ;;
      trojan://*)    echo -e "${GREEN}✓ Trojan${RESET}" ;;
      hysteria2://*) echo -e "${GREEN}✓ Hysteria2${RESET}" ;;
      tuic://*)      echo -e "${GREEN}✓ TUIC v5${RESET}" ;;
      ss://*)        echo -e "${GREEN}✓ Shadowsocks${RESET}" ;;
      socks5://*)    echo -e "${GREEN}✓ Socks5${RESET}" ;;
      anytls://*)    echo -e "${GREEN}✓ AnyTLS${RESET}" ;;
      vless://*)     echo -e "${GREEN}✓ VLESS${RESET}" ;;
    esac
  done

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
    local hy2 tuic reality reality_domain ss s5 anytls
    hy2=$(get_val HY2_PORT)
    tuic=$(get_val TUIC_PORT)
    reality=$(get_val REALITY_PORT)
    reality_domain=$(get_val REALITY_DOMAIN)
    ss=$(get_val SS_PORT)
    s5=$(get_val S5_PORT)
    anytls=$(get_val ANYTLS_PORT)

    echo -e "${GRAY}--------------------------------${RESET}"
    echo -e "${WHITE}1. Hysteria2    (UDP) [${CYAN}${hy2:-未启用}${WHITE}]${RESET}"
    echo -e "${WHITE}2. TUIC         (UDP) [${CYAN}${tuic:-未启用}${WHITE}]${RESET}"
    echo -e "${WHITE}3. VLESS Reality(TCP) [${CYAN}${reality:-未启用}${WHITE}]${RESET}"
    echo -e "${WHITE}4. Reality Domain     [${CYAN}${reality_domain:-www.iij.ad.jp}${WHITE}]${RESET}"
    echo -e "${WHITE}5. Shadowsocks  (TCP) [${CYAN}${ss:-未启用}${WHITE}]${RESET}"
    echo -e "${WHITE}6. Socks5       (TCP) [${CYAN}${s5:-未启用}${WHITE}]${RESET}"
    echo -e "${WHITE}7. AnyTLS       (TCP) [${CYAN}${anytls:-未启用}${WHITE}]${RESET}"
    echo -e "${GRAY}--------------------------------${RESET}"
    echo -e "${WHITE}0. 确认修改并重启${RESET}"
    echo -e "${GRAY}--------------------------------${RESET}"
    echo -ne "${GRAY}请输入选项: ${RESET}"
    read -r opt

    case "$opt" in
      1)
        echo -ne "${GRAY}HY2_PORT（留空禁用）[当前: ${CYAN}${hy2:-未启用}${GRAY}]: ${RESET}"
        read -r val
        if [ -z "$val" ] && [ -n "$hy2" ]; then
          set_val HY2_PORT ""; echo -e "${YELLOW}Hysteria2 已禁用${RESET}"
        elif [ -n "$val" ]; then
          set_val HY2_PORT "$val"; echo -e "${GREEN}已更新为: $val${RESET}"
        fi
        sleep 1 ;;
      2)
        echo -ne "${GRAY}TUIC_PORT（留空禁用）[当前: ${CYAN}${tuic:-未启用}${GRAY}]: ${RESET}"
        read -r val
        if [ -z "$val" ] && [ -n "$tuic" ]; then
          set_val TUIC_PORT ""; echo -e "${YELLOW}TUIC 已禁用${RESET}"
        elif [ -n "$val" ]; then
          set_val TUIC_PORT "$val"; echo -e "${GREEN}已更新为: $val${RESET}"
        fi
        sleep 1 ;;
      3)
        echo -ne "${GRAY}REALITY_PORT（留空禁用）[当前: ${CYAN}${reality:-未启用}${GRAY}]: ${RESET}"
        read -r val
        if [ -z "$val" ] && [ -n "$reality" ]; then
          set_val REALITY_PORT ""; echo -e "${YELLOW}VLESS Reality 已禁用${RESET}"
        elif [ -n "$val" ]; then
          set_val REALITY_PORT "$val"; echo -e "${GREEN}已更新为: $val${RESET}"
        fi
        sleep 1 ;;
      4)
        echo -ne "${GRAY}REALITY_DOMAIN [当前: ${CYAN}${reality_domain:-www.iij.ad.jp}${GRAY}]: ${RESET}"
        read -r val
        if [ -n "$val" ]; then
          set_val REALITY_DOMAIN "$val"
          rm -f "$HOME/reality-keys.json"
          echo -e "${GREEN}已更新为: $val${RESET}"
          echo -e "${YELLOW}已清除 Reality 密钥，重启后重新生成${RESET}"
        fi
        sleep 1 ;;
      5)
        echo -ne "${GRAY}SS_PORT（留空禁用）[当前: ${CYAN}${ss:-未启用}${GRAY}]: ${RESET}"
        read -r val
        if [ -z "$val" ] && [ -n "$ss" ]; then
          set_val SS_PORT ""; echo -e "${YELLOW}Shadowsocks 已禁用${RESET}"
        elif [ -n "$val" ]; then
          set_val SS_PORT "$val"; echo -e "${GREEN}已更新为: $val${RESET}"
        fi
        sleep 1 ;;
      6)
        echo -ne "${GRAY}S5_PORT（留空禁用）[当前: ${CYAN}${s5:-未启用}${GRAY}]: ${RESET}"
        read -r val
        if [ -z "$val" ] && [ -n "$s5" ]; then
          set_val S5_PORT ""; echo -e "${YELLOW}Socks5 已禁用${RESET}"
        elif [ -n "$val" ]; then
          set_val S5_PORT "$val"; echo -e "${GREEN}已更新为: $val${RESET}"
        fi
        sleep 1 ;;
      7)
        echo -ne "${GRAY}ANYTLS_PORT（留空禁用）[当前: ${CYAN}${anytls:-未启用}${GRAY}]: ${RESET}"
        read -r val
        if [ -z "$val" ] && [ -n "$anytls" ]; then
          set_val ANYTLS_PORT ""; echo -e "${YELLOW}AnyTLS 已禁用${RESET}"
        elif [ -n "$val" ]; then
          set_val ANYTLS_PORT "$val"; echo -e "${GREEN}已更新为: $val${RESET}"
        fi
        sleep 1 ;;
      0)
        echo -ne "${GRAY}确认修改并重启? [y/N]: ${RESET}"
        read -r confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
          restart_service
        fi
        return ;;
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
