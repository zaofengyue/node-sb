# node-sb

基于 Node.js + [sing-box](https://github.com/SagerNet/sing-box) 的一键代理节点部署工具，内存占用低，适合小内存机器。

支持 VMess / VLESS / Trojan + WebSocket + Argo 隧道（必选），以及 Hysteria2 / TUIC v5 / VLESS Reality / Shadowsocks 2022（可选，按需启用）。

---

## 特性

- 内核使用 sing-box，内存占用远低于 xray
- 三协议（VMess、VLESS、Trojan）走 WebSocket + Argo 隧道，无需公网 IP
- 可选四协议（Hysteria2、TUIC v5、VLESS Reality、Shadowsocks 2022），设置端口变量即启用
- 订阅内容统一 base64，兼容主流客户端
- 节点名称自动识别国家 + ASN
- 支持源码部署、Docker 部署、一键脚本部署，含开机自启

---

## 快速开始

### 一键脚本（推荐）

```bash
bash <(curl -sL https://raw.githubusercontent.com/zaofengyue/node-sb/main/install.sh)
```

指定环境变量（跳过交互）：

```bash
UUID=your-uuid ARGO_DOMAIN=your.domain ARGO_AUTH="your-token" \
  bash <(curl -sL https://raw.githubusercontent.com/zaofengyue/node-sb/main/install.sh)
```

启用可选协议示例：

```bash
UUID=your-uuid \
HY2_PORT=8443 \
TUIC_PORT=9443 \
REALITY_PORT=7443 \
SS_PORT=6443 \
  bash <(curl -sL https://raw.githubusercontent.com/zaofengyue/node-sb/main/install.sh)
```

安装完成后：

| 命令 | 说明 |
|------|------|
| `sb-sub` | 查看订阅内容（base64） |
| `sb-log` | 查看运行日志 |
| `sb-del` | 彻底删除节点及所有文件 |

---

### Docker 部署

```bash
docker run -d --restart=always \
  -e UUID=your-uuid \
  -e ARGO_DOMAIN=your.domain \
  -e ARGO_AUTH="your-token" \
  -p 3000:3000 \
  ghcr.io/zaofengyue/node-sb:latest
```

启用可选协议（需开放对应端口）：

```bash
docker run -d --restart=always \
  -e UUID=your-uuid \
  -e ARGO_DOMAIN=your.domain \
  -e ARGO_AUTH="your-token" \
  -e HY2_PORT=8443 \
  -e TUIC_PORT=9443 \
  -e REALITY_PORT=7443 \
  -e SS_PORT=6443 \
  -p 3000:3000 \
  -p 8443:8443/udp \
  -p 9443:9443/udp \
  -p 7443:7443 \
  -p 6443:6443 \
  ghcr.io/zaofengyue/node-sb:latest
```

持久化 UUID 和 Reality 密钥：

```bash
docker run -d --restart=always \
  -e ARGO_DOMAIN=your.domain \
  -e ARGO_AUTH="your-token" \
  -v $HOME/node-sb-data:/root \
  -p 3000:3000 \
  ghcr.io/zaofengyue/node-sb:latest
```

---

### 源码部署（手动）

```bash
git clone https://github.com/zaofengyue/node-sb.git
cd node-sb && node index.js
```

---

## 环境变量

### 基础变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `UUID` | 节点 UUID，Trojan/Hysteria2/TUIC/Reality 密码同此 | 自动生成并持久化 |
| `PORT` | HTTP 服务对外端口（伪装页 + 订阅） | 自动分配 |
| `ARGO_PORT` | Argo 内部转发端口 | 固定隧道默认 8001，临时随机 |
| `NAME` | 节点名称前缀 | 自动识别 国家-ASN |
| `SUB` | 订阅路径 | `sub`（即 `/sub`） |
| `ARGO_DOMAIN` | 固定隧道域名 | 空则使用临时隧道 |
| `ARGO_AUTH` | 固定隧道 Token | 空则使用临时隧道 |

### 可选协议变量

| 变量 | 协议 | 说明 |
|------|------|------|
| `HY2_PORT` | Hysteria2 | 设置端口启用，需开放 UDP |
| `TUIC_PORT` | TUIC v5 | 设置端口启用，需开放 UDP |
| `REALITY_PORT` | VLESS Reality | 设置端口启用，需开放 TCP |
| `REALITY_DOMAIN` | VLESS Reality 伪装域名 | 默认 `addons.mozilla.org` |
| `SS_PORT` | Shadowsocks 2022 | 设置端口启用，需开放 TCP |

> Hysteria2 / TUIC 使用自签证书，客户端需开启跳过证书验证。
> Reality 密钥对自动生成并持久化，重启后 PublicKey 不变。
> Shadowsocks 密码由 UUID 自动派生，加密方式 `2022-blake3-aes-128-gcm`。

---

## 订阅

服务启动后，订阅地址为：

```
https://<argo-domain>/sub
```

订阅内容同时写入 `~/node-sb/sub.txt`，可用 `sb-sub` 命令查看。

---

## 伪装页

默认伪装页为简单 Hello World，将自定义 `index.html` 放入运行目录即可替换。

Docker 部署时挂载文件：

```bash
-v /your/path/index.html:/app/index.html
```

---

## 开发调试

拉取未混淆源码安装：

```bash
bash <(curl -sL https://raw.githubusercontent.com/zaofengyue/node-sb/main/install-dev.sh)
```

---

## License

MIT
