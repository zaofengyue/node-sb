// ========== 预留配置，留空则自动识别 ==========
const PRESET_UUID        = '';
const PRESET_PORT        = '';
const PRESET_ARGO_PORT   = '';
const PRESET_NAME        = '';
const PRESET_SUB         = '';
const PRESET_ARGO_DOMAIN = '';
const PRESET_ARGO_AUTH   = '';
// =============================================

const { execSync, spawn } = require('child_process');
const fs     = require('fs');
const os     = require('os');
const https  = require('https');
const http   = require('http');
const crypto = require('crypto');
const net    = require('net');

const HOME            = process.env.HOME || '/tmp';
const UUID_FILE       = `${HOME}/uuid.txt`;
const CONFIG_FILE     = `${HOME}/sb-config.json`;
const SB_DIR          = `${HOME}/sing-box`;
const SB_BIN_PATH     = `${SB_DIR}/sing-box`;
const CLOUDFLARED_BIN = `${HOME}/cloudflared`;

const WS_PATH_VMESS  = '/fengyue-vm';
const WS_PATH_VLESS  = '/fengyue-vl';
const WS_PATH_TROJAN = '/fengyue-tr';

// sing-box 三协议各自独立端口，监听 127.0.0.1
const V_VMESS_PORT  = 10000;
const V_VLESS_PORT  = 10001;
const V_TROJAN_PORT = 10002;

const CF_PREFER_HOST = 'cdns.doon.eu.org';

// ──────────────────────────────────────────────
// 工具函数
// ──────────────────────────────────────────────

function getFreePort() {
  return new Promise((resolve) => {
    const srv = net.createServer();
    srv.listen(0, '127.0.0.1', () => {
      const port = srv.address().port;
      srv.close(() => resolve(port));
    });
  });
}

function httpGet(url, timeout = 5000) {
  return new Promise((resolve) => {
    const mod = url.startsWith('https') ? https : http;
    const req = mod.get(url, { timeout }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data.trim()));
    });
    req.on('error', () => resolve(''));
    req.on('timeout', () => { req.destroy(); resolve(''); });
  });
}

function download(url, dest) {
  try { execSync(`curl -sL "${url}" -o "${dest}"`); return; } catch {}
  try { execSync(`wget -q "${url}" -O "${dest}"`); return; } catch {}
  throw new Error(`下载失败: ${url}`);
}

// ──────────────────────────────────────────────
// 下载 sing-box
// ──────────────────────────────────────────────

async function downloadSingBox() {
  if (fs.existsSync(SB_BIN_PATH)) {
    execSync(`chmod +x "${SB_BIN_PATH}"`);
    return SB_BIN_PATH;
  }

  const arch = os.arch();
  const archMap = { 'x64': 'amd64', 'arm64': 'arm64', 'arm': 'armv7' };
  const platform = archMap[arch] || 'amd64';

  console.log(`正在获取 sing-box 最新版本 (${platform})...`);

  let version = 'v1.11.6';
  try {
    const data = await httpGet('https://api.github.com/repos/SagerNet/sing-box/releases');
    if (data) {
      const releases = JSON.parse(data);
      const stable = releases.find(r => !r.prerelease && !r.draft);
      if (stable && stable.tag_name) version = stable.tag_name;
    }
  } catch {}

  console.log(`sing-box 版本: ${version}`);
  const verNum  = version.replace(/^v/, '');
  const tarName = `sing-box-${verNum}-linux-${platform}.tar.gz`;
  const url     = `https://github.com/SagerNet/sing-box/releases/download/${version}/${tarName}`;

  fs.mkdirSync(SB_DIR, { recursive: true });
  const tarPath = `${HOME}/sb.tar.gz`;
  console.log('正在下载 sing-box...');
  download(url, tarPath);
  execSync(`tar -xzf "${tarPath}" -C "${SB_DIR}" --strip-components=1`);
  execSync(`chmod +x "${SB_BIN_PATH}"`);
  fs.unlinkSync(tarPath);
  console.log('sing-box 下载完成');
  return SB_BIN_PATH;
}

// ──────────────────────────────────────────────
// 下载 cloudflared
// ──────────────────────────────────────────────

async function downloadCloudflared() {
  if (fs.existsSync(CLOUDFLARED_BIN)) {
    execSync(`chmod +x "${CLOUDFLARED_BIN}"`);
    return CLOUDFLARED_BIN;
  }

  const arch = os.arch();
  const archMap = { 'x64': 'linux-amd64', 'arm64': 'linux-arm64', 'arm': 'linux-arm' };
  const platform = archMap[arch] || 'linux-amd64';

  console.log(`正在下载 cloudflared (${platform})...`);
  const url = `https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-${platform}`;
  download(url, CLOUDFLARED_BIN);
  execSync(`chmod +x "${CLOUDFLARED_BIN}"`);
  console.log('cloudflared 下载完成');
  return CLOUDFLARED_BIN;
}

// ──────────────────────────────────────────────
// Argo 隧道
// ──────────────────────────────────────────────

function startArgoTunnel(cfBin, argoPort, argoDomain, argoAuth) {
  return new Promise((resolve) => {
    let argoHost = '';

    if (argoDomain && argoAuth) {
      console.log('启动固定 Argo 隧道...');
      const cf = spawn(cfBin, [
        'tunnel', '--edge-ip-version', 'auto', '--no-autoupdate',
        'run', '--token', argoAuth
      ], { stdio: 'pipe' });
      cf.on('error', err => console.error('cloudflared error:', err));
      argoHost = argoDomain;
      setTimeout(() => resolve(argoHost), 3000);
    } else {
      console.log('启动临时 Argo 隧道...');
      const cf = spawn(cfBin, [
        'tunnel', '--edge-ip-version', 'auto', '--no-autoupdate',
        '--url', `http://127.0.0.1:${argoPort}`
      ], { stdio: 'pipe' });

      cf.stderr.on('data', (data) => {
        const str   = data.toString();
        const match = str.match(/https:\/\/([a-z0-9-]+\.trycloudflare\.com)/);
        if (match && !argoHost) {
          argoHost = match[1];
          console.log(`临时隧道域名: ${argoHost}`);
          resolve(argoHost);
        }
      });
      cf.on('error', err => console.error('cloudflared error:', err));
      setTimeout(() => {
        if (!argoHost) { console.log('临时隧道域名获取超时'); resolve(''); }
      }, 30000);
    }
  });
}

// ──────────────────────────────────────────────
// 主流程
// ──────────────────────────────────────────────

async function main() {
  // UUID
  let UUID = PRESET_UUID || process.env.UUID || '';
  if (UUID) {
    fs.writeFileSync(UUID_FILE, UUID);
  } else if (fs.existsSync(UUID_FILE)) {
    UUID = fs.readFileSync(UUID_FILE, 'utf8').trim();
  } else {
    UUID = crypto.randomUUID();
    fs.writeFileSync(UUID_FILE, UUID);
  }

  const TROJAN_PASS = UUID;

  // 对外端口（伪装页 + 订阅）
  const INBOUND_PORT = PRESET_PORT
    ? parseInt(PRESET_PORT)
    : process.env.PORT
      ? parseInt(process.env.PORT)
      : await getFreePort();

  const SUB_RAW  = PRESET_SUB || process.env.SUB || 'sub';
  const SUB_PATH = '/' + SUB_RAW.replace(/^\//, '');

  const ARGO_DOMAIN = PRESET_ARGO_DOMAIN || process.env.ARGO_DOMAIN || '';
  const ARGO_AUTH   = PRESET_ARGO_AUTH   || process.env.ARGO_AUTH   || '';

  // Argo 转发端口：Node.js WS 反向代理监听此端口，cloudflared 指向它
  const ARGO_PORT = (ARGO_DOMAIN && ARGO_AUTH)
    ? parseInt(PRESET_ARGO_PORT || process.env.ARGO_PORT || '8001')
    : await getFreePort();

  // 节点名称
  const COUNTRY = await httpGet('https://ipinfo.io/country') ||
                  await httpGet('https://ifconfig.co/country-iso') || '';

  let NAME = PRESET_NAME || process.env.NAME || '';
  if (!NAME) {
    let ASN_ORG = await httpGet('https://ipinfo.io/org') ||
                  await httpGet('https://ifconfig.co/org') || '';
    ASN_ORG = ASN_ORG
      .replace(/^AS\d+\s+/, '')
      .replace(/,?\s*Inc\.?$/, '').replace(/,?\s*LLC\.?/g, '')
      .replace(/,?\s*Ltd\.?/g, '').replace(/,?\s*Corp\.?/g, '')
      .trim().substring(0, 20);
    NAME = COUNTRY && ASN_ORG ? `${COUNTRY}-${ASN_ORG}` :
           COUNTRY ? `${COUNTRY}-sb` : 'sb';
  }

  // ── sing-box 配置：三协议各自独立端口 ────────
  const config = {
    log: { level: 'warn', timestamp: false },
    inbounds: [
      {
        type: 'vmess',
        tag: 'vmess-in',
        listen: '127.0.0.1',
        listen_port: V_VMESS_PORT,
        users: [{ uuid: UUID, alterId: 0 }],
        transport: { type: 'ws', path: WS_PATH_VMESS }
      },
      {
        type: 'vless',
        tag: 'vless-in',
        listen: '127.0.0.1',
        listen_port: V_VLESS_PORT,
        users: [{ uuid: UUID, flow: '' }],
        transport: { type: 'ws', path: WS_PATH_VLESS }
      },
      {
        type: 'trojan',
        tag: 'trojan-in',
        listen: '127.0.0.1',
        listen_port: V_TROJAN_PORT,
        users: [{ password: TROJAN_PASS }],
        transport: { type: 'ws', path: WS_PATH_TROJAN }
      }
    ],
    outbounds: [{ type: 'direct', tag: 'direct' }]
  };

  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));

  // ── 启动 sing-box ──────────────────────────
  let sbBin = '';
  for (const p of ['sing-box', '/usr/local/bin/sing-box', '/usr/bin/sing-box']) {
    try { execSync(`which ${p} 2>/dev/null || test -x ${p}`); sbBin = p; break; } catch {}
  }
  if (!sbBin) sbBin = await downloadSingBox();

  const sbEnv = { ...process.env };
  delete sbEnv.PORT;

  const sb = spawn(sbBin, ['run', '-c', CONFIG_FILE], { stdio: 'inherit', env: sbEnv });
  sb.on('exit', code => process.exit(code));

  // ── Node.js WS 反向代理：按路径分发到各协议端口 ──
  // cloudflared → ARGO_PORT → Node.js → sing-box 各协议端口
  const argoServer = http.createServer((req, res) => {
    res.writeHead(400);
    res.end('Bad Request');
  });

  argoServer.on('upgrade', (req, socket, head) => {
    const path = req.url.split('?')[0];
    let targetPort;

    if (path === WS_PATH_VMESS)       targetPort = V_VMESS_PORT;
    else if (path === WS_PATH_VLESS)  targetPort = V_VLESS_PORT;
    else if (path === WS_PATH_TROJAN) targetPort = V_TROJAN_PORT;
    else { socket.destroy(); return; }

    const proxy = net.connect(targetPort, '127.0.0.1', () => {
      proxy.write(
        `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n` +
        Object.entries(req.headers).map(([k, v]) => `${k}: ${v}`).join('\r\n') +
        '\r\n\r\n'
      );
      proxy.write(head);
      socket.pipe(proxy);
      proxy.pipe(socket);
    });
    proxy.on('error', () => socket.destroy());
    socket.on('error', () => proxy.destroy());
  });

  argoServer.listen(ARGO_PORT, '127.0.0.1', () => {
    console.log(`Argo 转发服务启动，端口 ${ARGO_PORT}`);
  });

  // ── HTTP 服务（伪装页 + 订阅）──────────────
  const INDEX_HTML = fs.existsSync('./index.html')
    ? fs.readFileSync('./index.html', 'utf8')
    : '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Welcome</title></head>' +
      '<body><h1>Hello World</h1></body></html>';

  const server = http.createServer((req, res) => {
    const url = req.url.split('?')[0];
    if (url === SUB_PATH) {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(global.SUB_CONTENT || '');
    } else {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(INDEX_HTML);
    }
  });

  server.listen(INBOUND_PORT, '0.0.0.0', () => {
    console.log(`HTTP 服务启动，端口 ${INBOUND_PORT}`);
  });

  // ── 启动 cloudflared，指向 Node.js WS 转发端口 ──
  const cfBin    = await downloadCloudflared();
  const argoHost = await startArgoTunnel(cfBin, ARGO_PORT, ARGO_DOMAIN, ARGO_AUTH);
  const HOST     = argoHost || 'your-domain.com';

  // ── 生成订阅链接 ───────────────────────────
  const VMESS_OBJ = {
    v: '2', ps: NAME, add: CF_PREFER_HOST, port: '443',
    id: UUID, aid: '0', scy: 'auto', net: 'ws', type: 'none',
    host: HOST, path: WS_PATH_VMESS, tls: 'tls', sni: HOST
  };
  const VMESS_LINK = 'vmess://' + Buffer.from(JSON.stringify(VMESS_OBJ)).toString('base64');

  const VLESS_LINK = `vless://${UUID}@${CF_PREFER_HOST}:443` +
    `?encryption=none&security=tls&sni=${HOST}&type=ws&host=${HOST}` +
    `&path=${encodeURIComponent(WS_PATH_VLESS)}#${encodeURIComponent(NAME)}`;

  const TROJAN_LINK = `trojan://${TROJAN_PASS}@${CF_PREFER_HOST}:443` +
    `?security=tls&sni=${HOST}&type=ws&host=${HOST}` +
    `&path=${encodeURIComponent(WS_PATH_TROJAN)}#${encodeURIComponent(NAME)}`;

  const ALL_LINKS  = [VMESS_LINK, VLESS_LINK, TROJAN_LINK].join('\n');
  const SUB_BASE64 = Buffer.from(ALL_LINKS).toString('base64');
  global.SUB_CONTENT = SUB_BASE64;

  const SUB_FILE = `${process.cwd()}/sub.txt`;
  fs.writeFileSync(SUB_FILE, SUB_BASE64);

  console.log('================= 订阅内容 =================');
  console.log(SUB_BASE64);
  console.log('============================================');
  console.log(`订阅地址: https://${HOST}${SUB_PATH}`);
  console.log(`节点文件: ${SUB_FILE}`);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
