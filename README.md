# nodex-sb

基于 Node.js + [sing-box](https://github.com/SagerNet/sing-box) 的一键代理节点部署工具，内存占用更低，适合小内存机器。

支持 VMess / VLESS / Trojan + WebSocket + Argo 隧道，自动生成订阅链接。

---

## 特性

- 内核使用 sing-box，内存占用远低于 xray
- 三协议并存：VMess、VLESS、Trojan，均走 WebSocket
- Argo 隧道：支持临时隧道（自动域名）和固定隧道（自定义域名）
- 订阅内容统一 base64，兼容主流客户端
- 节点名称自动识别国家 + ASN
- 支持源码部署、Docker 部署、一键脚本部署，含开机自启

---

## 快速开始

### 一键脚本（推荐）

```bash
bash <(curl -sL https://raw.githubusercontent.com/zaofengyue/nodex-sb/main/install.sh)
```

指定环境变量（跳过交互）：

```bash
UUID=your-uuid ARGO_DOMAIN=your.domain ARGO_AUTH=your-token \
  bash <(curl -sL https://raw.githubusercontent.com/zaofengyue/nodex-sb/main/install.sh)
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
  -e ARGO_AUTH=your-token \
  -p 3000:3000 \
  ghcr.io/zaofengyue/nodex-sb:latest
```

不指定 `UUID` 时自动生成并持久化到容器内，建议挂载目录保留：

```bash
docker run -d --restart=always \
  -e ARGO_DOMAIN=your.domain \
  -e ARGO_AUTH=your-token \
  -v $HOME/nodex-sb-data:/root \
  -p 3000:3000 \
  ghcr.io/zaofengyue/nodex-sb:latest
```

---

### 源码部署（手动）

```bash
git clone https://github.com/zaofengyue/nodex-sb.git
cd nodex-sb
node index.js
```

---

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `UUID` | 节点 UUID，Trojan 密码同此 | 自动生成并持久化 |
| `PORT` | HTTP 服务对外端口 | 自动分配 |
| `ARGO_PORT` | Argo 转发内部端口 | 固定隧道默认 8001，临时随机 |
| `NAME` | 节点名称前缀 | 自动识别 国家-ASN |
| `SUB` | 订阅路径 | `sub`（即 `/sub`） |
| `ARGO_DOMAIN` | 固定隧道域名 | 空则使用临时隧道 |
| `ARGO_AUTH` | 固定隧道 Token | 空则使用临时隧道 |

---

## 订阅

服务启动后，订阅地址为：

```
https://<argo-domain>/sub
```

订阅内容同时写入 `~/nodex-sb/sub.txt`，可用 `sb-sub` 命令查看。

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
bash <(curl -sL https://raw.githubusercontent.com/zaofengyue/nodex-sb/main/install-dev.sh)
```

---

## License

MIT
