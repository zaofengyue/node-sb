// ========== 预留配置，留空则自动识别 ==========
const PRESET_UUID           = '';
const PRESET_PORT           = '';
const PRESET_ARGO_PORT      = '';
const PRESET_NAME           = '';
const PRESET_SUB            = '';
const PRESET_ARGO_DOMAIN    = '';
const PRESET_ARGO_AUTH      = '';
// ── 可选协议，填写端口则启动对应协议，留空不启动 ──
const PRESET_HY2_PORT       = '';
const PRESET_TUIC_PORT      = '';
const PRESET_REALITY_PORT   = '';
const PRESET_REALITY_DOMAIN = '';
const PRESET_SS_PORT        = '';
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

// Argo 三协议 WS 路径
const WS_PATH_VMESS  = '/fengyue-vm';
const WS_PATH_VLESS  = '/fengyue-vl';
const WS_PATH_TROJAN = '/fengyue-tr';

// Argo 三协议固定内部端口
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

// SS2022 密码：需要 base64(32字节)，从 UUID 派生
function deriveSSPassword(uuid) {
  const hex = uuid.replace(/-/g, '');
  const buf = Buffer.from(hex.padEnd(64, '0').slice(0, 64), 'hex');
  return buf.toString('base64');
}

// 生成自签证书（Hysteria2 / TUIC 用）
function generateSelfSignedCert(dir) {
  const keyPath  = `${dir}/key.pem`;
  const certPath = `${dir}/cert.pem`;
  if (fs.existsSync(keyPath) && fs.existsSync(certPath)) return { keyPath, certPath };
  fs.mkdirSync(dir, { recursive: true });
  try {
    execSync(
      `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -days 3650 -nodes` +
      ` -keyout "${keyPath}" -out "${certPath}"` +
      ` -subj "/CN=bing.com/O=Microsoft/C=US"`,
      { stdio: 'pipe' }
    );
  } catch {
    // openssl 不可用时用 sing-box 自带证书占位，启动时会报警告但能运行
    fs.writeFileSync(keyPath, '');
    fs.writeFileSync(certPath, '');
  }
  return { keyPath, certPath };
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
// 获取公网 IP
// ──────────────────────────────────────────────

async function getPublicIP() {
  return await httpGet('https://ipinfo.io/ip') ||
         await httpGet('https://ifconfig.co/ip') ||
         '';
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
  const SS_PASS     = deriveSSPassword(UUID);

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

  const ARGO_PORT = (ARGO_DOMAIN && ARGO_AUTH)
    ? parseInt(PRESET_ARGO_PORT || process.env.ARGO_PORT || '8001')
    : await getFreePort();

  // 可选协议端口（有值则启动，无值则跳过）
  const HY2_PORT_RAW     = PRESET_HY2_PORT     || process.env.HY2_PORT     || '';
  const TUIC_PORT_RAW    = PRESET_TUIC_PORT     || process.env.TUIC_PORT    || '';
  const REALITY_PORT_RAW = PRESET_REALITY_PORT  || process.env.REALITY_PORT || '';
  const SS_PORT_RAW      = PRESET_SS_PORT       || process.env.SS_PORT      || '';

  const HY2_PORT     = HY2_PORT_RAW     ? parseInt(HY2_PORT_RAW)     : 0;
  const TUIC_PORT    = TUIC_PORT_RAW    ? parseInt(TUIC_PORT_RAW)    : 0;
  const REALITY_PORT = REALITY_PORT_RAW ? parseInt(REALITY_PORT_RAW) : 0;
  const SS_PORT      = SS_PORT_RAW      ? parseInt(SS_PORT_RAW)      : 0;

  const REALITY_DOMAIN = PRESET_REALITY_DOMAIN || process.env.REALITY_DOMAIN || 'addons.mozilla.org';

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

  // 公网 IP（可选协议订阅需要）
  const PUBLIC_IP = (HY2_PORT || TUIC_PORT || REALITY_PORT || SS_PORT)
    ? await getPublicIP()
    : '';

  // ── sing-box 配置 ──────────────────────────
  const inbounds = [
    // Argo 三协议，固定内部端口
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
  ];

  // 端口冲突检测：同传输类型不能共用同一端口
  // UDP 组：Hysteria2 和 TUIC 均为 UDP，端口相同则冲突
  // TCP 组：Reality 和 Shadowsocks 均为 TCP，端口相同则冲突
  // 跨类型（UDP vs TCP）端口相同完全没问题，可以共用
  const hy2Active     = !!(HY2_PORT  && !(TUIC_PORT    && TUIC_PORT    === HY2_PORT));
  const tuicActive    = !!(TUIC_PORT  && !(HY2_PORT     && HY2_PORT     === TUIC_PORT));
  const realityActive = !!(REALITY_PORT && !(SS_PORT    && SS_PORT      === REALITY_PORT));
  const ssActive      = !!(SS_PORT    && !(REALITY_PORT && REALITY_PORT === SS_PORT));

  if (HY2_PORT && TUIC_PORT && HY2_PORT === TUIC_PORT)
    console.warn(`警告: HY2_PORT 与 TUIC_PORT 相同 (${HY2_PORT})，均为 UDP 会冲突，TUIC 已跳过`);
  if (REALITY_PORT && SS_PORT && REALITY_PORT === SS_PORT)
    console.warn(`警告: REALITY_PORT 与 SS_PORT 相同 (${REALITY_PORT})，均为 TCP 会冲突，Shadowsocks 已跳过`);

  // 自签证书（Hysteria2 / TUIC 需要）
  let certPath = '', keyPath = '';
  if (hy2Active || tuicActive) {
    const certDir = `${HOME}/certs`;
    const cert = generateSelfSignedCert(certDir);
    certPath = cert.certPath;
    keyPath  = cert.keyPath;
  }

  // Hysteria2（可选，UDP）
  if (hy2Active) {
    console.log(`启用 Hysteria2，端口 ${HY2_PORT} (UDP)`);
    inbounds.push({
      type: 'hysteria2',
      tag: 'hy2-in',
      listen: '::',
      listen_port: HY2_PORT,
      users: [{ password: UUID }],
      tls: {
        enabled: true,
        certificate_path: certPath,
        key_path: keyPath
      }
    });
  }

  // TUIC v5（可选，UDP，可与 Hysteria2 端口号不同时共存）
  if (tuicActive) {
    console.log(`启用 TUIC v5，端口 ${TUIC_PORT} (UDP)`);
    inbounds.push({
      type: 'tuic',
      tag: 'tuic-in',
      listen: '::',
      listen_port: TUIC_PORT,
      users: [{ uuid: UUID, password: UUID }],
      congestion_control: 'bbr',
      tls: {
        enabled: true,
        certificate_path: certPath,
        key_path: keyPath
      }
    });
  }

  // VLESS Reality（可选，TCP，可与 Hysteria2/TUIC 共用端口号）
  if (realityActive) {
    console.log(`启用 VLESS Reality，端口 ${REALITY_PORT}`);
    // 生成 Reality 密钥对
    let realityPrivKey = '', realityPubKey = '', realityShortId = '';
    try {
      const keyOut = execSync(`${SB_BIN_PATH || 'sing-box'} generate reality-keypair`, { encoding: 'utf8' });
      const privMatch = keyOut.match(/PrivateKey:\s*(\S+)/);
      const pubMatch  = keyOut.match(/PublicKey:\s*(\S+)/);
      if (privMatch) realityPrivKey = privMatch[1];
      if (pubMatch)  realityPubKey  = pubMatch[1];
    } catch {
      realityPrivKey = crypto.randomBytes(32).toString('base64url');
      realityPubKey  = '';
    }
    realityShortId = crypto.randomBytes(4).toString('hex');

    // 持久化 Reality 密钥（重启后 pubkey 不变，客户端无需重新配置）
    const realityKeyFile = `${HOME}/reality-keys.json`;
    if (fs.existsSync(realityKeyFile)) {
      try {
        const saved = JSON.parse(fs.readFileSync(realityKeyFile, 'utf8'));
        realityPrivKey = saved.privKey || realityPrivKey;
        realityPubKey  = saved.pubKey  || realityPubKey;
        realityShortId = saved.shortId || realityShortId;
      } catch {}
    } else {
      fs.writeFileSync(realityKeyFile, JSON.stringify({
        privKey: realityPrivKey,
        pubKey:  realityPubKey,
        shortId: realityShortId
      }));
    }

    inbounds.push({
      type: 'vless',
      tag: 'reality-in',
      listen: '::',
      listen_port: REALITY_PORT,
      users: [{ uuid: UUID, flow: 'xtls-rprx-vision' }],
      tls: {
        enabled: true,
        server_name: REALITY_DOMAIN,
        reality: {
          enabled: true,
          handshake: { server: REALITY_DOMAIN, server_port: 443 },
          private_key: realityPrivKey,
          short_id: [realityShortId]
        }
      }
    });

    // 暴露 pubkey 供订阅生成
    global.REALITY_PUB_KEY  = realityPubKey;
    global.REALITY_SHORT_ID = realityShortId;
  }

  // Shadowsocks 2022（可选，TCP，可与 Hysteria2/TUIC 共用端口号）
  if (ssActive) {
    console.log(`启用 Shadowsocks 2022，端口 ${SS_PORT} (TCP)`);
    inbounds.push({
      type: 'shadowsocks',
      tag: 'ss-in',
      listen: '::',
      listen_port: SS_PORT,
      method: '2022-blake3-aes-128-gcm',
      password: SS_PASS
    });
  }

  const config = {
    log: { level: 'warn', timestamp: false },
    inbounds,
    outbounds: [{ type: 'direct', tag: 'direct' }]
  };

  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));

  // ── 启动 sing-box ──────────────────────────
  let sbBin = '';
  for (const p of ['sing-box', '/usr/local/bin/sing-box', '/usr/bin/sing-box']) {
    try { execSync(`which ${p} 2>/dev/null || test -x ${p}`); sbBin = p; break; } catch {}
  }
  if (!sbBin) sbBin = await downloadSingBox();

  // Reality 密钥生成依赖 sing-box 二进制，确保路径正确
  if (REALITY_PORT && !global.REALITY_PUB_KEY) {
    try {
      const keyOut = execSync(`"${sbBin}" generate reality-keypair`, { encoding: 'utf8' });
      const privMatch = keyOut.match(/PrivateKey:\s*(\S+)/);
      const pubMatch  = keyOut.match(/PublicKey:\s*(\S+)/);
      const realityKeyFile = `${HOME}/reality-keys.json`;
      if (privMatch && pubMatch && !fs.existsSync(realityKeyFile)) {
        const realityShortId = crypto.randomBytes(4).toString('hex');
        fs.writeFileSync(realityKeyFile, JSON.stringify({
          privKey: privMatch[1],
          pubKey:  pubMatch[1],
          shortId: realityShortId
        }));
        // 重写配置里的 reality inbound
        const saved = JSON.parse(fs.readFileSync(realityKeyFile, 'utf8'));
        const rIdx  = config.inbounds.findIndex(i => i.tag === 'reality-in');
        if (rIdx >= 0) {
          config.inbounds[rIdx].tls.reality.private_key  = saved.privKey;
          config.inbounds[rIdx].tls.reality.short_id     = [saved.shortId];
          global.REALITY_PUB_KEY  = saved.pubKey;
          global.REALITY_SHORT_ID = saved.shortId;
          fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
        }
      }
    } catch {}
  }

  const sbEnv = { ...process.env };
  delete sbEnv.PORT;

  const sb = spawn(sbBin, ['run', '-c', CONFIG_FILE], { stdio: 'inherit', env: sbEnv });
  sb.on('exit', code => process.exit(code));

  // ── Node.js WS 反向代理（Argo 三协议路径分发）──
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

  // ── 启动 cloudflared ───────────────────────
  const cfBin    = await downloadCloudflared();
  const argoHost = await startArgoTunnel(cfBin, ARGO_PORT, ARGO_DOMAIN, ARGO_AUTH);
  const HOST     = argoHost || 'your-domain.com';

  // ── 生成订阅链接 ───────────────────────────
  const links = [];

  // Argo 三协议
  const VMESS_OBJ = {
    v: '2', ps: NAME, add: CF_PREFER_HOST, port: '443',
    id: UUID, aid: '0', scy: 'auto', net: 'ws', type: 'none',
    host: HOST, path: WS_PATH_VMESS, tls: 'tls', sni: HOST
  };
  links.push('vmess://' + Buffer.from(JSON.stringify(VMESS_OBJ)).toString('base64'));

  links.push(
    `vless://${UUID}@${CF_PREFER_HOST}:443` +
    `?encryption=none&security=tls&sni=${HOST}&type=ws&host=${HOST}` +
    `&path=${encodeURIComponent(WS_PATH_VLESS)}#${encodeURIComponent(NAME)}`
  );

  links.push(
    `trojan://${TROJAN_PASS}@${CF_PREFER_HOST}:443` +
    `?security=tls&sni=${HOST}&type=ws&host=${HOST}` +
    `&path=${encodeURIComponent(WS_PATH_TROJAN)}#${encodeURIComponent(NAME)}`
  );

  // Hysteria2（可选，UDP）
  if (HY2_PORT && PUBLIC_IP) {
    links.push(
      `hysteria2://${UUID}@${PUBLIC_IP}:${HY2_PORT}` +
      `?insecure=1#${encodeURIComponent(NAME)}`
    );
  }

  // TUIC v5（可选，UDP，可与 Hysteria2 共用同一端口号）
  if (TUIC_PORT && PUBLIC_IP) {
    links.push(
      `tuic://${UUID}:${UUID}@${PUBLIC_IP}:${TUIC_PORT}` +
      `?congestion_control=bbr&alpn=h3&insecure=1` +
      `#${encodeURIComponent(NAME)}`
    );
  }

  // VLESS Reality（可选，TCP）
  if (REALITY_PORT && PUBLIC_IP && global.REALITY_PUB_KEY) {
    links.push(
      `vless://${UUID}@${PUBLIC_IP}:${REALITY_PORT}` +
      `?encryption=none&security=reality&sni=${REALITY_DOMAIN}` +
      `&fp=chrome&pbk=${global.REALITY_PUB_KEY}&sid=${global.REALITY_SHORT_ID}` +
      `&flow=xtls-rprx-vision&type=tcp` +
      `#${encodeURIComponent(NAME)}`
    );
  }

  // Shadowsocks 2022（可选，TCP，可与 Reality 共用同一端口号）
  if (SS_PORT && PUBLIC_IP) {
    const ssUserInfo = Buffer.from(`2022-blake3-aes-128-gcm:${SS_PASS}`).toString('base64');
    links.push(
      `ss://${ssUserInfo}@${PUBLIC_IP}:${SS_PORT}` +
      `#${encodeURIComponent(NAME)}`
    );
  }

  const SUB_BASE64 = Buffer.from(links.join('\n')).toString('base64');
  global.SUB_CONTENT = SUB_BASE64;

  const SUB_FILE = `${process.cwd()}/sub.txt`;
  fs.writeFileSync(SUB_FILE, SUB_BASE64);

  console.log('================= 订阅内容 =================');
  console.log(SUB_BASE64);
  console.log('============================================');
  console.log(`订阅地址: https://${HOST}${SUB_PATH}`);
  console.log(`节点文件: ${SUB_FILE}`);

  // 输出已启用协议汇总
  console.log('============== 已启用协议 ==============');
  console.log(`✓ VMess  + WS + Argo TLS`);
  console.log(`✓ VLESS  + WS + Argo TLS`);
  console.log(`✓ Trojan + WS + Argo TLS`);
  if (hy2Active)     console.log(`✓ Hysteria2     端口 ${HY2_PORT} (UDP)`);
  if (tuicActive)    console.log(`✓ TUIC v5       端口 ${TUIC_PORT} (UDP)`);
  if (realityActive) console.log(`✓ VLESS Reality 端口 ${REALITY_PORT} (TCP)  PubKey: ${global.REALITY_PUB_KEY || '生成中'}`);
  if (ssActive)      console.log(`✓ Shadowsocks   端口 ${SS_PORT} (TCP)  密码: ${SS_PASS}`);
  console.log('========================================');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
