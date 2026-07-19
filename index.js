// ========== 预留配置，留空则自动识别 ==========
const PRESET_UUID           = '';
const PRESET_PORT           = '';
const PRESET_ARGO_PORT      = '';
const PRESET_NAME           = '';
const PRESET_SUB            = '';
const PRESET_ARGO_DOMAIN    = '';
const PRESET_ARGO_AUTH      = '';
// ── 填 'true' 禁用 Argo，留空则启用 ──
const PRESET_DISABLE_ARGO   = '';
// ── 可选协议，填写端口则启动对应协议，留空不启动 ──
const PRESET_HY2_PORT       = '';
const PRESET_TUIC_PORT      = '';
const PRESET_REALITY_PORT   = '';
const PRESET_REALITY_DOMAIN = '';
const PRESET_SS_PORT        = '';
const PRESET_S5_PORT        = '';
const PRESET_ANYTLS_PORT    = '';
// ── 填 '0'/'false'/'no' 关闭部署完成后的清理动作，留空即默认开启 ──
const PRESET_CLEANUP_AFTER_DEPLOY = '';
// =============================================

const { execSync, spawn } = require('child_process');
const fs     = require('fs');
const os     = require('os');
const path   = require('path');
const https  = require('https');
const http   = require('http');
const crypto = require('crypto');
const net    = require('net');

const HOME            = process.env.HOME || os.tmpdir();
const WORLD_DIR       = `${HOME}/world`;
const UUID_FILE       = `${WORLD_DIR}/uuid.txt`;
const CONFIG_FILE     = `${WORLD_DIR}/sb-config.json`;
const SB_DIR          = `${WORLD_DIR}/sing-box`;
const SB_BIN_NAME     = os.platform() === 'win32' ? 'sing-box.exe' : 'sing-box';
const SB_BIN_PATH     = `${SB_DIR}/${SB_BIN_NAME}`;
const CLOUDFLARED_BIN = `${WORLD_DIR}/cloudflared${os.platform() === 'win32' ? '.exe' : ''}`;

const WS_PATH_VMESS  = '/fengyue-vm';
const WS_PATH_VLESS  = '/fengyue-vl';
const WS_PATH_TROJAN = '/fengyue-tr';

const V_VMESS_PORT  = 10000;
const V_VLESS_PORT  = 10001;
const V_TROJAN_PORT = 10002;

const CF_PREFER_HOST = 'cdns.doon.eu.org';

// ──────────────────────────────────────────────
// 工具函数
// ──────────────────────────────────────────────

// 注意：这里获取到空闲端口后会先关闭探测用的 socket，再在稍后真正监听，
// 两者之间存在极小的窗口期理论上可能被其他进程抢占（TOCTOU）。
// 对个人/小规模部署场景概率可忽略，如需绝对保证可自行加重试逻辑。
function getFreePort() {
  return new Promise((resolve) => {
    const srv = net.createServer();
    srv.listen(0, '127.0.0.1', () => {
      const port = srv.address().port;
      srv.close(() => resolve(port));
    });
  });
}

function httpGet(url, timeout = 5000, _redirects = 0) {
  return new Promise((resolve) => {
    if (_redirects > 3) { resolve(''); return; }
    const mod = url.startsWith('https') ? https : http;
    const req = mod.get(url, { timeout }, (res) => {
      // 跟随重定向（ipinfo.io 等接口偶尔返回 301/302）
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        httpGet(res.headers.location, timeout, _redirects + 1).then(resolve);
        return;
      }
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data.trim()));
    });
    req.on('error', () => resolve(''));
    req.on('timeout', () => { req.destroy(); resolve(''); });
  });
}

async function download(url, dest) {
  try { execSync(`curl -fsSL "${url}" -o "${dest}"`, { stdio: 'pipe' }); return; } catch {}
  try { execSync(`wget -q "${url}" -O "${dest}"`, { stdio: 'pipe' }); return; } catch {}
  await downloadWithNode(url, dest);
}

function downloadWithNode(url, dest) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith('https') ? https : http;
    const file = fs.createWriteStream(dest);
    const req = mod.get(url, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        file.close();
        fs.unlinkSync(dest);
        return downloadWithNode(res.headers.location, dest).then(resolve, reject);
      }
      if (res.statusCode !== 200) {
        file.close();
        return reject(new Error(`下载失败，HTTP状态码: ${res.statusCode}`));
      }
      res.pipe(file);
      file.on('finish', () => file.close(resolve));
    });
    req.on('error', (err) => { try { fs.unlinkSync(dest); } catch {} reject(err); });
  });
}

// 多源下载，依次尝试直连和镜像，任一成功即返回
async function downloadWithFallback(urls, dest) {
  for (const url of urls) {
    try {
      await download(url, dest);
      return;
    } catch {
      console.warn(`下载失败，尝试下一个源...`);
      try { fs.unlinkSync(dest); } catch {}
    }
  }
  throw new Error('所有下载源均失败');
}

// 从主 UUID 派生独立的协议密钥，避免所有协议共用同一凭据
// （某一协议的订阅链接泄露不会连带暴露其它协议）
function deriveSecret(uuid, label) {
  return crypto.createHash('sha256').update(`${uuid}:${label}`).digest();
}

function deriveSSPassword(uuid) {
  // ss-2022 aes-128-gcm 需要 16 字节密钥
  return deriveSecret(uuid, 'ss-2022').subarray(0, 16).toString('base64');
}

function deriveTrojanPassword(uuid) {
  return deriveSecret(uuid, 'trojan').toString('hex');
}

function deriveAnyTLSPassword(uuid) {
  return deriveSecret(uuid, 'anytls').toString('hex');
}

function deriveS5Credentials(uuid) {
  const buf = deriveSecret(uuid, 's5');
  return {
    username: buf.subarray(0, 8).toString('hex'),
    password: buf.subarray(8, 16).toString('hex')
  };
}

function secureFilePermissions(filePath) {
  if (os.platform() === 'win32') return;
  try { fs.chmodSync(filePath, 0o600); } catch (e) {
    console.warn(`设置文件权限失败 ${filePath}: ${e.message}`);
  }
}

// ──────────────────────────────────────────────
// 自签证书
// ──────────────────────────────────────────────

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
    secureFilePermissions(keyPath);
    return { keyPath, certPath };
  } catch {
    console.log('openssl 不可用，使用内置兜底证书（仅供个人测试）');
  }

  const FALLBACK_KEY = `-----BEGIN EC PARAMETERS-----
BggqhkjOPQMBBw==
-----END EC PARAMETERS-----
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIM4792SEtPqIt1ywqTd/0bYidBqpYV/++siNnfBYsdUYoAoGCCqGSM49
AwEHoUQDQgAE1kHafPj07rJG+HboH2ekAI4r+e6TL38GWASANnngZreoQDF16ARa
/TsyLyFoPkhLxSbehH/NBEjHtSZGaDhMqQ==
-----END EC PRIVATE KEY-----`;
  const FALLBACK_CERT = `-----BEGIN CERTIFICATE-----
MIIBejCCASGgAwIBAgIUfWeQL3556PNJLp/veCFxGNj9crkwCgYIKoZIzj0EAwIw
EzERMA8GA1UEAwwIYmluZy5jb20wHhcNMjUwOTE4MTgyMDIyWhcNMzUwOTE2MTgy
MDIyWjATMREwDwYDVQQDDAhiaW5nLmNvbTBZMBMGByqGSM49AgEGCCqGSM49AwEH
A0IABNZB2nz49O6yRvh26B9npACOK/nuky9/BlgEgDZ54Ga3qEAxdegEWv07Mi8h
aD5IS8Um3oR/zQRIx7UmRmg4TKmjUzBRMB0GA1UdDgQWBBTV1cFID7UISE7PLTBR
BfGbgkrMNzAfBgNVHSMEGDAWgBTV1cFID7UISE7PLTBRBfGbgkrMNzAPBgNVHRMB
Af8EBTADAQH/MAoGCCqGSM49BAMCA0cAMEQCIAIDAJvg0vd/ytrQVvEcSm6XTlB+
eQ6OFb9LbLYL9f+sAiAffoMbi4y/0YUSlTtz7as9S8/lciBF5VCUoVIKS+vX2g==
-----END CERTIFICATE-----`;

  fs.writeFileSync(keyPath, FALLBACK_KEY);
  fs.writeFileSync(certPath, FALLBACK_CERT);
  secureFilePermissions(keyPath);
  return { keyPath, certPath };
}

// ──────────────────────────────────────────────
// 平台识别
// ──────────────────────────────────────────────

function detectArch() {
  const archMap = { x64: 'amd64', arm64: 'arm64', arm: 'armv7', ia32: '386' };
  return archMap[os.arch()] || 'amd64';
}

function detectOS() {
  const p = os.platform();
  if (p === 'darwin') return 'darwin';
  if (p === 'win32')  return 'windows';
  return 'linux';
}

// ──────────────────────────────────────────────
// 下载 sing-box（多源 fallback）
// ──────────────────────────────────────────────

async function downloadSingBox() {
  if (fs.existsSync(SB_BIN_PATH)) {
    if (os.platform() !== 'win32') execSync(`chmod +x "${SB_BIN_PATH}"`);
    return SB_BIN_PATH;
  }

  const arch     = detectArch();
  const platform = detectOS();
  console.log(`正在获取 sing-box 最新版本 (${platform}-${arch})...`);

  // AnyTLS 需要 >= 1.12.0，设为兜底最低版本
  let version = 'v1.12.0';
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
  const ext     = platform === 'windows' ? 'zip' : 'tar.gz';
  const tarName = `sing-box-${verNum}-${platform}-${arch}.${ext}`;
  const ghBase  = `https://github.com/SagerNet/sing-box/releases/download/${version}/${tarName}`;

  fs.mkdirSync(SB_DIR, { recursive: true });
  const tarPath = `${WORLD_DIR}/sb.${ext}`;
  console.log('正在下载 sing-box...');

  await downloadWithFallback([
    ghBase,
    `https://ghproxy.net/${ghBase}`,
    `https://gh.idayer.com/${ghBase}`,
    `https://mirror.ghproxy.com/${ghBase}`,
  ], tarPath);

  if (ext === 'zip') {
    execSync(`powershell -Command "Expand-Archive -Path '${tarPath}' -DestinationPath '${SB_DIR}' -Force"`);
  } else {
    execSync(`tar -xzf "${tarPath}" -C "${SB_DIR}" --strip-components=1`);
  }

  if (platform !== 'windows') execSync(`chmod +x "${SB_BIN_PATH}"`);
  fs.unlinkSync(tarPath);
  console.log('sing-box 下载完成');
  return SB_BIN_PATH;
}

// ──────────────────────────────────────────────
// 下载 cloudflared（多源 fallback）
// ──────────────────────────────────────────────

async function downloadCloudflared() {
  if (fs.existsSync(CLOUDFLARED_BIN)) {
    if (os.platform() !== 'win32') execSync(`chmod +x "${CLOUDFLARED_BIN}"`);
    return CLOUDFLARED_BIN;
  }

  const platform = os.platform();
  const arch     = os.arch();
  const archMap  = {
    linux:  { x64: 'linux-amd64',      arm64: 'linux-arm64',   arm: 'linux-arm' },
    darwin: { x64: 'darwin-amd64',     arm64: 'darwin-arm64' },
    win32:  { x64: 'windows-amd64.exe', ia32: 'windows-386.exe' },
  };
  const suffix   = (archMap[platform] && archMap[platform][arch]) || 'linux-amd64';
  const ghBase   = `https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-${suffix}`;

  console.log(`正在下载 cloudflared (${suffix})...`);
  await downloadWithFallback([
    ghBase,
    `https://ghproxy.net/${ghBase}`,
    `https://gh.idayer.com/${ghBase}`,
    `https://mirror.ghproxy.com/${ghBase}`,
  ], CLOUDFLARED_BIN);

  if (platform !== 'win32') execSync(`chmod +x "${CLOUDFLARED_BIN}"`);
  console.log('cloudflared 下载完成');
  return CLOUDFLARED_BIN;
}

// ──────────────────────────────────────────────
// Argo 隧道
// ──────────────────────────────────────────────

const TUNNEL_CONNECTED_PATTERN = /registered tunnel connection/i;
const TUNNEL_ERROR_PATTERN = /(failed to |unable to |unauthorized|context canceled|connection refused)/i;

function startArgoTunnel(cfBin, argoPort, argoDomain, argoAuth) {
  return new Promise((resolve) => {
    if (argoDomain && argoAuth) {
      console.log('启动固定 Argo 隧道...');
      const cf = spawn(cfBin, [
        'tunnel', '--edge-ip-version', 'auto', '--no-autoupdate',
        'run', '--token', argoAuth
      ], { stdio: 'pipe' });

      let settled = false;
      let buf = ''; // 滚动缓冲区，避免日志行被拆分到两个 data 事件里导致匹配失败
      const onData = (data) => {
        if (settled) return;
        buf = (buf + data.toString()).slice(-4000);
        if (TUNNEL_CONNECTED_PATTERN.test(buf)) {
          settled = true;
          console.log('固定 Argo 隧道连接成功');
          resolve(argoDomain);
        } else if (TUNNEL_ERROR_PATTERN.test(buf)) {
          settled = true;
          console.warn('固定 Argo 隧道连接失败（token 可能无效或网络异常）');
          resolve('');
        }
      };
      cf.stdout.on('data', onData);
      cf.stderr.on('data', onData);
      cf.on('error', (err) => {
        if (!settled) { settled = true; console.error('cloudflared error:', err); resolve(''); }
      });
      cf.on('exit', (code) => {
        if (!settled) {
          settled = true;
          console.warn(`固定 Argo 隧道进程提前退出（code=${code}）`);
          resolve('');
        }
      });
      setTimeout(() => {
        if (!settled) {
          settled = true;
          console.warn('10 秒内未确认固定隧道状态，继续使用配置的 ARGO_DOMAIN');
          resolve(argoDomain);
        }
      }, 10000);
    } else {
      console.log('启动临时 Argo 隧道...');
      let argoHost = '';
      let buf = ''; // 滚动缓冲区，避免域名字符串被拆分到两个 data 事件里
      const cf = spawn(cfBin, [
        'tunnel', '--edge-ip-version', 'auto', '--no-autoupdate',
        '--url', `http://127.0.0.1:${argoPort}`
      ], { stdio: 'pipe' });

      cf.stderr.on('data', (data) => {
        buf = (buf + data.toString()).slice(-4000);
        const match = buf.match(/https:\/\/([a-z0-9-]+\.trycloudflare\.com)/);
        if (match && !argoHost) {
          argoHost = match[1];
          console.log(`临时隧道域名: ${argoHost}`);
          resolve(argoHost);
        }
      });
      cf.stdout.on('data', () => {});
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
  // 并发竞速：谁先返回有效 IP 就用谁，避免串行等待两个超时
  return new Promise((resolve) => {
    let resolved = false;
    const done = (val) => {
      if (!resolved && val) { resolved = true; resolve(val); }
    };
    Promise.all([
      httpGet('https://ipinfo.io/ip').then(done),
      httpGet('https://ifconfig.co/ip').then(done),
    ]).then(() => { if (!resolved) resolve(''); });
  });
}

// ──────────────────────────────────────────────
// 部署后清理
// ──────────────────────────────────────────────

// 仅清理 sing-box 下载产生的临时归档和无用文档文件，
// 不涉及 install.sh/sb_manager.sh 等安装脚本自身
function cleanupDeployArtifacts() {
  const removed = [];
  for (const name of ['sb.tar.gz', 'sb.zip']) {
    const p = `${WORLD_DIR}/${name}`;
    if (fs.existsSync(p)) { try { fs.unlinkSync(p); removed.push(name); } catch {} }
  }
  const unusedNames = ['LICENSE', 'LICENSE.txt', 'README.md', 'README', 'CHANGELOG.md', 'CHANGELOG'];
  if (fs.existsSync(SB_DIR)) {
    for (const name of unusedNames) {
      const p = path.join(SB_DIR, name);
      if (fs.existsSync(p) && p !== SB_BIN_PATH) {
        try { fs.unlinkSync(p); removed.push(name); } catch {}
      }
    }
  }
  if (removed.length) {
    console.log(`cleanup: removed ${removed.join(', ')}`);
  }
}

// ──────────────────────────────────────────────
// 主流程
// ──────────────────────────────────────────────

async function main() {
  fs.mkdirSync(WORLD_DIR, { recursive: true });

  const DISABLE_ARGO = PRESET_DISABLE_ARGO === 'true' || process.env.DISABLE_ARGO === 'true';

  // UUID
  let UUID = PRESET_UUID || process.env.UUID || '';
  if (UUID) {
    try { fs.writeFileSync(UUID_FILE, UUID); } catch {}
  } else if (fs.existsSync(UUID_FILE)) {
    try { UUID = fs.readFileSync(UUID_FILE, 'utf8').trim(); } catch {}
  }
  if (!UUID) {
    UUID = crypto.randomUUID();
    try { fs.writeFileSync(UUID_FILE, UUID); } catch {}
  }
  secureFilePermissions(UUID_FILE);

  const TROJAN_PASS = deriveTrojanPassword(UUID);
  const SS_PASS     = deriveSSPassword(UUID);
  const ANYTLS_PASS = deriveAnyTLSPassword(UUID);
  const S5_CREDS    = deriveS5Credentials(UUID);

  const INBOUND_PORT = PRESET_PORT
    ? parseInt(PRESET_PORT)
    : process.env.PORT
      ? parseInt(process.env.PORT)
      : await getFreePort();

  // 未显式指定 SUB 时，生成随机路径并持久化，避免默认的 /sub 被扫描器猜中
  const SUB_TOKEN_FILE = `${WORLD_DIR}/sub_token.txt`;
  let SUB_RAW = PRESET_SUB || process.env.SUB || '';
  if (!SUB_RAW) {
    if (fs.existsSync(SUB_TOKEN_FILE)) {
      try { SUB_RAW = fs.readFileSync(SUB_TOKEN_FILE, 'utf8').trim(); } catch {}
    }
    if (!SUB_RAW) {
      SUB_RAW = crypto.randomBytes(6).toString('hex');
      try { fs.writeFileSync(SUB_TOKEN_FILE, SUB_RAW); secureFilePermissions(SUB_TOKEN_FILE); } catch {}
    }
  }
  const SUB_PATH = '/' + SUB_RAW.replace(/^\//, '');

  const ARGO_DOMAIN = PRESET_ARGO_DOMAIN || process.env.ARGO_DOMAIN || '';
  const ARGO_AUTH   = PRESET_ARGO_AUTH   || process.env.ARGO_AUTH   || '';

  const ARGO_PORT = (ARGO_DOMAIN && ARGO_AUTH)
    ? parseInt(PRESET_ARGO_PORT || process.env.ARGO_PORT || '8001')
    : await getFreePort();

  const HY2_PORT     = parseInt(PRESET_HY2_PORT     || process.env.HY2_PORT     || '0') || 0;
  const TUIC_PORT    = parseInt(PRESET_TUIC_PORT     || process.env.TUIC_PORT    || '0') || 0;
  const REALITY_PORT = parseInt(PRESET_REALITY_PORT  || process.env.REALITY_PORT || '0') || 0;
  const SS_PORT      = parseInt(PRESET_SS_PORT       || process.env.SS_PORT      || '0') || 0;
  const S5_PORT      = parseInt(PRESET_S5_PORT       || process.env.S5_PORT      || '0') || 0;
  const ANYTLS_PORT  = parseInt(PRESET_ANYTLS_PORT   || process.env.ANYTLS_PORT  || '0') || 0;

  const REALITY_DOMAIN = PRESET_REALITY_DOMAIN || process.env.REALITY_DOMAIN || 'www.iij.ad.jp';

  // 并发获取 COUNTRY 和 ASN_ORG，节省串行等待的超时时间
  const [COUNTRY, ASN_ORG_RAW] = await Promise.all([
    httpGet('https://ipinfo.io/country').then(v => v || httpGet('https://ifconfig.co/country-iso')),
    httpGet('https://ipinfo.io/org').then(v => v || httpGet('https://ifconfig.co/org')),
  ]);

  let NAME = PRESET_NAME || process.env.NAME || '';
  if (!NAME) {
    let ASN_ORG = ASN_ORG_RAW;
    ASN_ORG = ASN_ORG
      .replace(/^AS\d+\s+/, '')
      .replace(/,?\s*Inc\.?$/, '').replace(/,?\s*LLC\.?/g, '')
      .replace(/,?\s*Ltd\.?/g, '').replace(/,?\s*Corp\.?/g, '')
      .trim().substring(0, 20);
    NAME = COUNTRY && ASN_ORG ? `${COUNTRY}-${ASN_ORG}` :
           COUNTRY ? `${COUNTRY}-sb` : 'sb';
  }

  const PUBLIC_IP = (HY2_PORT || TUIC_PORT || REALITY_PORT || SS_PORT || S5_PORT || ANYTLS_PORT)
    ? await getPublicIP()
    : '';

  // ── sing-box inbounds ──────────────────────
  const inbounds = DISABLE_ARGO ? [] : [
    {
      type: 'vmess', tag: 'vmess-in',
      listen: '127.0.0.1', listen_port: V_VMESS_PORT,
      users: [{ uuid: UUID, alterId: 0 }],
      transport: { type: 'ws', path: WS_PATH_VMESS }
    },
    {
      type: 'vless', tag: 'vless-in',
      listen: '127.0.0.1', listen_port: V_VLESS_PORT,
      users: [{ uuid: UUID, flow: '' }],
      transport: { type: 'ws', path: WS_PATH_VLESS }
    },
    {
      type: 'trojan', tag: 'trojan-in',
      listen: '127.0.0.1', listen_port: V_TROJAN_PORT,
      users: [{ password: TROJAN_PASS }],
      transport: { type: 'ws', path: WS_PATH_TROJAN }
    }
  ];

  // ── 找到 sing-box 二进制 ───────────────────
  let sbBin = '';
  if (fs.existsSync(SB_BIN_PATH)) {
    if (os.platform() !== 'win32') execSync(`chmod +x "${SB_BIN_PATH}"`);
    sbBin = SB_BIN_PATH;
  } else {
    const candidates = os.platform() === 'win32'
      ? ['C:\\sing-box\\sing-box.exe']
      : ['/usr/local/bin/sing-box', '/usr/bin/sing-box'];
    for (const p of candidates) {
      if (fs.existsSync(p)) { sbBin = p; break; }
    }
  }
  if (!sbBin) sbBin = await downloadSingBox();

  // ── 端口唯一性检测 ──────────────────────────
  const usedPorts = new Set();
  usedPorts.add(`tcp:${INBOUND_PORT}`);
  if (!DISABLE_ARGO) {
    usedPorts.add(`tcp:${ARGO_PORT}`);
    usedPorts.add(`tcp:${V_VMESS_PORT}`);
    usedPorts.add(`tcp:${V_VLESS_PORT}`);
    usedPorts.add(`tcp:${V_TROJAN_PORT}`);
  }
  function portOk(p, proto) {
    if (!p || isNaN(p)) return false;
    const n = parseInt(p);
    if (n < 1 || n > 65535) return false;
    const key = `${proto}:${n}`;
    if (usedPorts.has(key)) return false;
    usedPorts.add(key);
    return true;
  }
  const hy2Active     = portOk(HY2_PORT,     'udp');
  const tuicActive    = portOk(TUIC_PORT,    'udp');
  let   realityActive = portOk(REALITY_PORT, 'tcp');
  const ssActive      = portOk(SS_PORT,      'tcp');
  const s5Active      = portOk(S5_PORT,      'tcp');
  const anytlsActive  = portOk(ANYTLS_PORT,  'tcp');

  // 冲突提示：内部保留端口列表，帮助定位是与哪个端口冲突
  const reservedPortHint = !DISABLE_ARGO
    ? `（内部保留端口: ${INBOUND_PORT}/HTTP订阅, ${ARGO_PORT}/Argo转发, ${V_VMESS_PORT}/${V_VLESS_PORT}/${V_TROJAN_PORT}/三协议内部）`
    : `（内部保留端口: ${INBOUND_PORT}/HTTP订阅）`;
  if (HY2_PORT     && !hy2Active)     console.warn(`警告: HY2_PORT(${HY2_PORT}) 端口冲突或无效，Hysteria2 已跳过 ${reservedPortHint}`);
  if (TUIC_PORT    && !tuicActive)    console.warn(`警告: TUIC_PORT(${TUIC_PORT}) 端口冲突或无效，TUIC 已跳过 ${reservedPortHint}`);
  if (REALITY_PORT && !realityActive) console.warn(`警告: REALITY_PORT(${REALITY_PORT}) 端口冲突或无效，Reality 已跳过 ${reservedPortHint}`);
  if (SS_PORT      && !ssActive)      console.warn(`警告: SS_PORT(${SS_PORT}) 端口冲突或无效，Shadowsocks 已跳过 ${reservedPortHint}`);
  if (S5_PORT      && !s5Active)      console.warn(`警告: S5_PORT(${S5_PORT}) 端口冲突或无效，Socks5 已跳过 ${reservedPortHint}`);
  if (ANYTLS_PORT  && !anytlsActive)  console.warn(`警告: ANYTLS_PORT(${ANYTLS_PORT}) 端口冲突或无效，AnyTLS 已跳过 ${reservedPortHint}`);

  // 自签证书（HY2 / TUIC / AnyTLS 需要）
  let certPath = '', keyPath = '', certReady = false;
  if (hy2Active || tuicActive || anytlsActive) {
    try {
      const cert = generateSelfSignedCert(`${WORLD_DIR}/certs`);
      certPath  = cert.certPath;
      keyPath   = cert.keyPath;
      certReady = true;
    } catch (e) {
      console.error(`证书生成失败，HY2/TUIC/AnyTLS 将被跳过: ${e.message}`);
    }
  }
  const hy2Final    = hy2Active    && certReady;
  const tuicFinal   = tuicActive   && certReady;
  const anytlsFinal = anytlsActive && certReady;

  if (hy2Active    && !certReady) console.warn('因证书不可用，Hysteria2 已跳过');
  if (tuicActive   && !certReady) console.warn('因证书不可用，TUIC 已跳过');
  if (anytlsActive && !certReady) console.warn('因证书不可用，AnyTLS 已跳过');

  if (hy2Final) {
    console.log(`启用 Hysteria2，端口 ${HY2_PORT}`);
    inbounds.push({
      type: 'hysteria2', tag: 'hy2-in',
      listen: '::', listen_port: HY2_PORT,
      users: [{ password: UUID }],
      masquerade: 'https://bing.com',
      tls: { enabled: true, alpn: ['h3'], certificate_path: certPath, key_path: keyPath }
    });
  }

  if (tuicFinal) {
    console.log(`启用 TUIC v5，端口 ${TUIC_PORT}`);
    inbounds.push({
      type: 'tuic', tag: 'tuic-in',
      listen: '::', listen_port: TUIC_PORT,
      users: [{ uuid: UUID, password: UUID }],
      congestion_control: 'bbr',
      tls: { enabled: true, alpn: ['h3'], certificate_path: certPath, key_path: keyPath }
    });
  }

  if (realityActive) {
    console.log(`启用 VLESS Reality，端口 ${REALITY_PORT}`);

    const realityKeyFile = `${WORLD_DIR}/reality-keys.json`;
    let realityPrivKey = '', realityPubKey = '';

    if (fs.existsSync(realityKeyFile)) {
      try {
        const saved = JSON.parse(fs.readFileSync(realityKeyFile, 'utf8'));
        if (saved.privKey && saved.pubKey) {
          realityPrivKey = saved.privKey;
          realityPubKey  = saved.pubKey;
          secureFilePermissions(realityKeyFile);
          console.log('已从文件读取 Reality 密钥对');
        } else {
          throw new Error('字段不完整');
        }
      } catch (e) {
        console.warn(`reality-keys.json 读取失败（${e.message}），重新生成...`);
        try { fs.unlinkSync(realityKeyFile); } catch {}
      }
    }

    if (!realityPrivKey || !realityPubKey) {
      try {
        const keyOut    = execSync(`"${sbBin}" generate reality-keypair`, { encoding: 'utf8' });
        const privMatch = keyOut.match(/PrivateKey:\s*(\S+)/);
        const pubMatch  = keyOut.match(/PublicKey:\s*(\S+)/);
        if (privMatch && pubMatch) {
          realityPrivKey = privMatch[1];
          realityPubKey  = pubMatch[1];
          fs.writeFileSync(realityKeyFile, JSON.stringify({
            privKey: realityPrivKey,
            pubKey:  realityPubKey
          }));
          secureFilePermissions(realityKeyFile);
          console.log('Reality 密钥对生成并保存成功');
        } else {
          throw new Error('密钥输出格式异常');
        }
      } catch (e) {
        console.error('Reality 密钥生成失败:', e.message);
      }
    }

    if (!realityPrivKey || !realityPubKey) {
      console.warn('Reality 密钥不可用，VLESS Reality 已跳过');
      realityActive = false;
    } else {
      global.REALITY_PUB_KEY = realityPubKey;
      inbounds.push({
        type: 'vless', tag: 'reality-in',
        listen: '::', listen_port: REALITY_PORT,
        users: [{ uuid: UUID, flow: 'xtls-rprx-vision' }],
        tls: {
          enabled: true,
          server_name: REALITY_DOMAIN,
          reality: {
            enabled: true,
            handshake: { server: REALITY_DOMAIN, server_port: 443 },
            private_key: realityPrivKey,
            short_id: ['']
          }
        }
      });
    }
  }

  if (ssActive) {
    console.log(`启用 Shadowsocks 2022，端口 ${SS_PORT}`);
    inbounds.push({
      type: 'shadowsocks', tag: 'ss-in',
      listen: '::', listen_port: SS_PORT, network: 'tcp',
      method: '2022-blake3-aes-128-gcm', password: SS_PASS
    });
  }

  if (s5Active) {
    console.log(`启用 Socks5，端口 ${S5_PORT}`);
    inbounds.push({
      type: 'socks', tag: 's5-in',
      listen: '::', listen_port: S5_PORT,
      network: 'tcp',  // socks5 只走 TCP，避免默认同时绑 UDP 与其他协议冲突
      users: [{ username: S5_CREDS.username, password: S5_CREDS.password }]
    });
  }

  if (anytlsFinal) {
    console.log(`启用 AnyTLS，端口 ${ANYTLS_PORT}`);
    inbounds.push({
      type: 'anytls', tag: 'anytls-in',
      listen: '::', listen_port: ANYTLS_PORT,
      users: [{ password: ANYTLS_PASS }],
      tls: { enabled: true, certificate_path: certPath, key_path: keyPath }
    });
  }

  fs.writeFileSync(CONFIG_FILE, JSON.stringify({
    log: { level: 'warn', timestamp: false },
    inbounds,
    outbounds: [{ type: 'direct', tag: 'direct' }]
  }, null, 2));

  // ── sing-box 配置校验 ──────────────────────
  const SB_LOG_FILE = `${WORLD_DIR}/sb-run.log`;
  let sbStartFailed = false;
  try {
    execSync(`"${sbBin}" check -c "${CONFIG_FILE}"`, { encoding: 'utf8', stdio: 'pipe' });
    console.log('sing-box 配置校验通过');
  } catch (e) {
    const detail = (e.stdout || '') + (e.stderr || '') + e.message;
    console.error('sing-box 配置校验失败:\n' + detail.trim());
    console.error('常见原因：sing-box 版本过旧不支持某协议（AnyTLS 需要 >= 1.12.0）');
    try { fs.writeFileSync(SB_LOG_FILE, `[CONFIG CHECK FAILED]\n${detail}\n`); } catch {}
    sbStartFailed = true;
  }

  // ── 启动 sing-box（detached 后台，stdio: ignore 避免文件描述符继承问题）──
  try {
    if (os.platform() !== 'win32') {
      execSync(`pkill -f "${SB_BIN_PATH}" 2>/dev/null || true`);
    }
    await new Promise(r => setTimeout(r, 800));
  } catch {}

  if (!sbStartFailed) {
    const sbEnv = { ...process.env };
    delete sbEnv.PORT;

    const sb = spawn(sbBin, ['run', '-c', CONFIG_FILE], {
      stdio: 'ignore',          // 必须 ignore，detached 模式下不能继承父进程文件描述符
      detached: os.platform() !== 'win32',
      env: sbEnv
    });
    sb.unref();
    console.log(`sing-box 已在后台启动，PID: ${sb.pid}`);
  } else {
    console.warn('sing-box 未启动（配置校验失败），HTTP 订阅服务仍会继续运行');
  }

  await new Promise(r => setTimeout(r, 1500));

  // ── Argo WS 反向代理 ───────────────────────
  if (!DISABLE_ARGO) {
    const argoServer = http.createServer((req, res) => {
      res.writeHead(400); res.end('Bad Request');
    });

    argoServer.on('upgrade', (req, socket, head) => {
      const reqPath = req.url.split('?')[0];
      const targetPort =
        reqPath === WS_PATH_VMESS  ? V_VMESS_PORT  :
        reqPath === WS_PATH_VLESS  ? V_VLESS_PORT  :
        reqPath === WS_PATH_TROJAN ? V_TROJAN_PORT : null;

      if (!targetPort) { socket.destroy(); return; }

      const proxy = net.connect(targetPort, '127.0.0.1', () => {
        const headerLines = Object.entries(req.headers).flatMap(([k, v]) =>
          Array.isArray(v) ? v.map(vv => `${k}: ${vv}`) : [`${k}: ${v}`]
        );
        proxy.write(
          `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n` +
          headerLines.join('\r\n') +
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
  }

  // ── HTTP 服务（伪装页 + 订阅）──────────────
  const INDEX_HTML = fs.existsSync('./index.html')
    ? fs.readFileSync('./index.html', 'utf8')
    : '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Welcome</title></head>' +
      '<body><h1>Hello World</h1></body></html>';

  http.createServer((req, res) => {
    if (req.url.split('?')[0] === SUB_PATH) {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(global.SUB_CONTENT || '');
    } else {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(INDEX_HTML);
    }
  }).listen(INBOUND_PORT, '0.0.0.0', () => {
    console.log(`HTTP 服务启动，端口 ${INBOUND_PORT}`);
  });

  // ── cloudflared ────────────────────────────
  let HOST = 'your-domain.com';
  if (!DISABLE_ARGO) {
    const cfBin    = await downloadCloudflared();
    const argoHost = await startArgoTunnel(cfBin, ARGO_PORT, ARGO_DOMAIN, ARGO_AUTH);
    HOST = argoHost || 'your-domain.com';
  } else {
    console.log('Argo 隧道已禁用');
  }

  // ── 生成订阅链接 ───────────────────────────
  const links = [];

  if (!DISABLE_ARGO) {
    links.push('vmess://' + Buffer.from(JSON.stringify({
      v: '2', ps: NAME, add: CF_PREFER_HOST, port: '443',
      id: UUID, aid: '0', scy: 'auto', net: 'ws', type: 'none',
      host: HOST, path: WS_PATH_VMESS, tls: 'tls', sni: HOST
    })).toString('base64'));

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
  }

  if (hy2Final && PUBLIC_IP) {
    links.push(
      `hysteria2://${UUID}@${PUBLIC_IP}:${HY2_PORT}` +
      `?sni=www.bing.com&insecure=1&alpn=h3&obfs=none` +
      `#${encodeURIComponent(NAME)}`
    );
  }

  if (tuicFinal && PUBLIC_IP) {
    links.push(
      `tuic://${UUID}:${UUID}@${PUBLIC_IP}:${TUIC_PORT}` +
      `?sni=www.bing.com&congestion_control=bbr&udp_relay_mode=native&alpn=h3&allow_insecure=1` +
      `#${encodeURIComponent(NAME)}`
    );
  }

  if (realityActive && PUBLIC_IP && global.REALITY_PUB_KEY) {
    links.push(
      `vless://${UUID}@${PUBLIC_IP}:${REALITY_PORT}` +
      `?encryption=none&flow=xtls-rprx-vision&security=reality` +
      `&sni=${REALITY_DOMAIN}&fp=firefox&pbk=${global.REALITY_PUB_KEY}` +
      `&type=tcp&headerType=none` +
      `#${encodeURIComponent(NAME)}`
    );
  }

  if (ssActive && PUBLIC_IP) {
    const ssUserInfo = Buffer.from(`2022-blake3-aes-128-gcm:${SS_PASS}`).toString('base64');
    links.push(
      `ss://${ssUserInfo}@${PUBLIC_IP}:${SS_PORT}` +
      `#${encodeURIComponent(NAME)}`
    );
  }

  if (s5Active && PUBLIC_IP) {
    const s5UserInfo = Buffer.from(`${S5_CREDS.username}:${S5_CREDS.password}`).toString('base64');
    links.push(
      // 注意：必须是 socks5://，管理面板(sb)按此前缀识别协议
      `socks5://${s5UserInfo}@${PUBLIC_IP}:${S5_PORT}` +
      `#${encodeURIComponent(NAME)}`
    );
  }

  if (anytlsFinal && PUBLIC_IP) {
    links.push(
      `anytls://${ANYTLS_PASS}@${PUBLIC_IP}:${ANYTLS_PORT}` +
      `?security=tls&sni=www.bing.com&fp=chrome&insecure=1&allowInsecure=1` +
      `#${encodeURIComponent(NAME)}`
    );
  }

  const SUB_BASE64 = Buffer.from(links.join('\n')).toString('base64');
  global.SUB_CONTENT = SUB_BASE64;
  try { fs.writeFileSync(`${WORLD_DIR}/sub.txt`, SUB_BASE64); } catch {}

  console.log('================= 订阅内容 =================');
  console.log(SUB_BASE64);
  console.log('============================================');
  console.log(`订阅地址: https://${HOST}${SUB_PATH}`);

  console.log('============== 已启用协议 ==============');
  if (!DISABLE_ARGO) {
    console.log(`✓ VMess  + WS + Argo TLS`);
    console.log(`✓ VLESS  + WS + Argo TLS`);
    console.log(`✓ Trojan + WS + Argo TLS`);
  }
  if (hy2Final)      console.log(`✓ Hysteria2     端口 ${HY2_PORT} (UDP)`);
  if (tuicFinal)     console.log(`✓ TUIC v5       端口 ${TUIC_PORT} (UDP)`);
  if (realityActive) console.log(`✓ VLESS Reality 端口 ${REALITY_PORT}  PubKey: ${global.REALITY_PUB_KEY}`);
  if (ssActive)      console.log(`✓ Shadowsocks   端口 ${SS_PORT} (TCP)  密码: ${SS_PASS}`);
  if (s5Active)      console.log(`✓ Socks5        端口 ${S5_PORT} (TCP)  账号: ${S5_CREDS.username}`);
  if (anytlsFinal)   console.log(`✓ AnyTLS        端口 ${ANYTLS_PORT} (TCP)`);
  if (DISABLE_ARGO)  console.log(`✗ Argo 隧道已禁用`);
  console.log(`运行环境: ${detectOS()}-${detectArch()}`);
  console.log('========================================');

  const cleanupEnv = (PRESET_CLEANUP_AFTER_DEPLOY || process.env.CLEANUP_AFTER_DEPLOY || '').toLowerCase().trim();
  if (!['0', 'false', 'no'].includes(cleanupEnv)) {
    cleanupDeployArtifacts();
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
