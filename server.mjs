#!/usr/bin/env node
/*
  HQR Metadata Mover - local server (macOS, Linux and Windows). House of Quintanilla-Reese LLC - MIT License
  Same API as server.ps1, written for Node.js 18 or newer with no dependencies.
  Wraps the Salesforce CLI (sf) and serves the UI at http://127.0.0.1:<port>/ (this computer only).
    node server.mjs [--port 8770] [--no-browser] [--data-dir <folder>] [--idle-minutes 10]
  It opens in its own Chrome or Edge app window when one is installed, and stops by itself once no
  window has been open for --idle-minutes.
*/
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const AppName = 'HQR Metadata Mover';
const Version = '1.0.0';
const IS_WIN = process.platform === 'win32';
const IS_MAC = process.platform === 'darwin';
const Root = path.dirname(fileURLToPath(import.meta.url));

// ---------- arguments ----------
const argv = process.argv.slice(2);
function argVal(name, dflt) {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : dflt;
}
let Port = parseInt(argVal('--port', '8770'), 10) || 8770;
const NoBrowser = argv.includes('--no-browser');
const IdleMinutes = parseInt(argVal('--idle-minutes', '10'), 10) || 10;
let DataDir = argVal('--data-dir', '');
if (!DataDir) {
  DataDir = fs.existsSync(path.join(Root, 'packages')) ? Root : path.join(os.homedir(), 'Documents', AppName);
}
const PkgRoot = path.join(DataDir, 'packages');
const WorkDir = path.join(DataDir, '.sf-workspace');
const LogFile = path.join(DataDir, 'server.log');
const RunFile = path.join(DataDir, 'running.json');
// Random per-run token: the page gets it embedded, so other websites can't call this API.
const Token = crypto.randomBytes(16).toString('hex');
const Sessions = new Map();
const StartedAt = Date.now();
let SfPath = null;
let SfVersion = '';

process.env.SF_AUTOUPDATE_DISABLE = 'true';
process.env.SF_USE_PROGRESS_BAR = 'false';
process.env.FORCE_COLOR = '0';

// ---------- logging ----------
function log(msg) {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  const line = `[${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}] ${msg}`;
  console.log(line);
  try { fs.appendFileSync(LogFile, line + '\n'); } catch {}
}

// ---------- small helpers ----------
const exists = (p) => fs.existsSync(p);
const mkdirp = (p) => fs.mkdirSync(p, { recursive: true });
const rmrf = (p) => fs.rmSync(p, { recursive: true, force: true });
const readText = (p) => fs.readFileSync(p, 'utf8');
const writeText = (p, t) => fs.writeFileSync(p, t, 'utf8');
function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out); else out.push(p);
  }
  return out;
}
function listDirs(dir) {
  try { return fs.readdirSync(dir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name); } catch { return []; }
}
function xmlEscape(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}
function stamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

// Extracts a zip: unzip where it exists (macOS, Linux), otherwise tar (Windows 10+ and macOS can read zips).
function unzip(zip, dest) {
  mkdirp(dest);
  const tries = IS_WIN
    ? [['tar', ['-xf', zip, '-C', dest]], ['unzip', ['-o', '-q', zip, '-d', dest]]]
    : [['unzip', ['-o', '-q', zip, '-d', dest]], ['tar', ['-xf', zip, '-C', dest]]];
  for (const [cmd, args] of tries) {
    const r = spawnSync(cmd, args, { stdio: 'ignore' });
    if (!r.error && r.status === 0) return;
  }
  throw new Error('Could not unzip ' + zip + '. On macOS this needs the built-in unzip or tar command.');
}

// ---------- Salesforce CLI ----------
function findSf() {
  const names = IS_WIN ? ['sf.cmd', 'sf.exe'] : ['sf'];
  const dirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  if (IS_WIN) {
    dirs.push(path.join(process.env.ProgramFiles || 'C:\\Program Files', 'sf', 'bin'),
      path.join(process.env.LOCALAPPDATA || '', 'sf', 'bin'), path.join(process.env.APPDATA || '', 'npm'));
  } else {
    dirs.push('/opt/homebrew/bin', '/usr/local/bin', '/usr/local/sf/bin', path.join(os.homedir(), '.local', 'bin'), path.join(os.homedir(), 'sf', 'bin'));
  }
  for (const d of dirs) {
    for (const n of names) {
      const p = path.join(d, n);
      try { if (fs.statSync(p).isFile()) return p; } catch {}
    }
  }
  return null;
}

function quoteArg(a) {
  if (a === '') return '""';
  if (/[\s"&|<>^()%!,;=]/.test(a)) return '"' + a.replace(/"/g, '\\"') + '"';
  return a;
}

function invokeSf(sfArgs, timeoutSec = 1800) {
  if (!SfPath) return Promise.reject(new Error('Salesforce CLI (sf) was not found. Install it, then restart Metadata Mover.'));
  log('sf ' + sfArgs.map(quoteArg).join(' '));
  return new Promise((resolve, reject) => {
    let child;
    const opts = { cwd: WorkDir, windowsHide: true };
    if (IS_WIN) {
      // cmd /s /c "..." keeps the quoting of a .cmd path with spaces intact.
      child = spawn(process.env.ComSpec || 'cmd.exe',
        ['/d', '/s', '/c', '"' + '"' + SfPath + '" ' + sfArgs.map(quoteArg).join(' ') + '"'],
        { ...opts, windowsVerbatimArguments: true });
    } else {
      child = spawn(SfPath, sfArgs, opts);
    }
    let out = '', err = '', done = false;
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      try { child.kill(); } catch {}
      reject(new Error(`sf did not finish within ${timeoutSec} seconds.`));
    }, timeoutSec * 1000);
    child.stdout.setEncoding('utf8').on('data', (d) => { out += d; });
    child.stderr.setEncoding('utf8').on('data', (d) => { err += d; });
    child.on('error', (e) => { if (done) return; done = true; clearTimeout(timer); reject(e); });
    child.on('close', (code) => { if (done) return; done = true; clearTimeout(timer); resolve({ exitCode: code, out, err }); });
  });
}

function parseSfJson(text) {
  const i = text.indexOf('{');
  if (i < 0) throw new Error('Unexpected output from sf: ' + text);
  const s = text.slice(i);
  try { return JSON.parse(s); } catch {}
  return JSON.parse(s.slice(0, s.lastIndexOf('}') + 1));
}

async function httpRequest(method, url, headers, body, contentType) {
  const h = { Accept: '*/*', ...(headers || {}) };
  if (body) h['Content-Type'] = contentType;
  const res = await fetch(url, { method, headers: h, body: body || undefined, signal: AbortSignal.timeout(300000) });
  return { status: res.status, body: await res.text() };
}

async function getOrgSession(org, refresh = false) {
  if (!refresh && Sessions.has(org)) return Sessions.get(org);
  const r = await invokeSf(['org', 'display', '--target-org', org, '--json'], 120);
  const j = parseSfJson(r.out);
  if (!j.result || !j.result.instanceUrl) {
    throw new Error(`Could not open a session for ${org}: ${j.message}. Try reconnecting the org.`);
  }
  // Newer CLI versions redact the token in 'org display'; 'org auth show-access-token' returns it (and refreshes it first).
  let token = String(j.result.accessToken || '');
  const t = await invokeSf(['org', 'auth', 'show-access-token', '--target-org', org, '--json'], 120);
  try { const tj = parseSfJson(t.out); if (tj.result && tj.result.accessToken) token = String(tj.result.accessToken); } catch {}
  if (!token || !token.includes('!')) {
    throw new Error(`Could not get an access token for ${org}. Disconnect the org and connect it again, or update the Salesforce CLI (sf update).`);
  }
  const s = { Token: token, Url: String(j.result.instanceUrl).replace(/\/+$/, ''), Username: j.result.username };
  Sessions.set(org, s);
  return s;
}

// Calls the org's REST or SOAP API, refreshing the session once if it has expired.
async function invokeOrgApi(org, method, apiPath, body, contentType, soap = false) {
  let r = null;
  for (let i = 0; i < 2; i++) {
    const s = await getOrgSession(org, i > 0);
    let b, h;
    if (soap) {
      b = String(body).split('{{SESSION}}').join(xmlEscape(s.Token));
      h = { SOAPAction: '""' };
    } else {
      b = body;
      h = { Authorization: 'Bearer ' + s.Token };
    }
    r = await httpRequest(method, s.Url + apiPath, h, b, contentType);
    if (r.status === 401 || /INVALID_SESSION_ID/.test(r.body)) continue;
    return r;
  }
  return r;
}

// REST GET that returns parsed JSON, or throws Salesforce's own error message.
async function getOrgJson(org, apiPath) {
  const r = await invokeOrgApi(org, 'GET', apiPath);
  let j = null;
  try { j = JSON.parse(r.body); } catch {}
  if (r.status >= 400 || j === null) {
    let msg = r.body;
    if (j) msg = [].concat(j).map((e) => `${e.errorCode}: ${e.message}`).join('; ');
    throw new Error(`Salesforce returned HTTP ${r.status} for ${org}. ${msg}`);
  }
  return j;
}

// ---------- input validation ----------
function assertMatch(value, pattern, what) {
  const s = String(value === undefined || value === null ? '' : value);
  if (!pattern.test(s)) throw new Error('Invalid ' + what);
  return s;
}
const assertOrg = (v) => assertMatch(v, /^[\w.@+\-]{1,150}$/, 'org');
const assertPkgName = (v) => assertMatch(v, /^[\w\-]{1,80}$/, 'package name');
const assertJobId = (v) => assertMatch(v, /^0Af[A-Za-z0-9]{12,15}$/, 'deployment id');
const assertVersion = (v) => assertMatch(v, /^\d{2,3}\.0$/, 'API version');
const assertBackupId = (v) => assertMatch(v, /^[\w\-]{1,160}$/, 'backup id');

function getPackageZip(name) {
  const dir = path.join(PkgRoot, name, 'retrieved');
  if (!exists(dir)) return null;
  return walk(dir).find((f) => f.toLowerCase().endsWith('.zip')) || null;
}

// Returns what to deploy for a package: its zip, or a fixed-up copy when it has a CustomSite whose site admin or
// guest record owner is a username that doesn't exist in the target (sandbox usernames differ per org). Those are
// mapped to the same user in the target where one exists, otherwise to the target's connected user.
async function getDeploySource(name, org) {
  const zip = getPackageZip(name);
  if (!zip) return null;
  const out = { Path: zip, Fixes: [] };
  const dir = path.join(PkgRoot, name, 'deploy');
  rmrf(dir);
  const tmp = dir + '-tmp';
  rmrf(tmp);
  unzip(zip, tmp);
  const sites = walk(tmp).filter((f) => f.endsWith('.site') && path.basename(path.dirname(f)) === 'sites');
  const rx = /<(siteAdmin|siteGuestRecordDefaultOwner)>([^<]+)<\/\1>/g;
  const users = [...new Set(sites.flatMap((f) => [...readText(f).matchAll(rx)].map((m) => m[2])))].sort();
  if (!users.length) { rmrf(tmp); return out; }

  let ver = '60.0';
  try { const m = JSON.parse(readText(path.join(PkgRoot, name, 'meta.json'))); if (m.apiVersion) ver = m.apiVersion; } catch {}
  const me = (await getOrgSession(org)).Username;
  const oq = encodeURIComponent('SELECT IsSandbox FROM Organization');
  const isSandbox = !!(await getOrgJson(org, `/services/data/v${ver}/query?q=${oq}`)).records[0].IsSandbox;
  let tgtSuffix = '';
  if (isSandbox) { const m = /\.([^.@]+)$/.exec(me); if (m) tgtSuffix = m[1]; }

  // The same person in the target, best first: the username itself, then with the target's sandbox suffix
  // (sandbox usernames are the production username + .<sandbox name>), or without a suffix in production.
  const cands = {};
  for (const u of users) {
    let base = u;
    const m = /^(.+@.+\..+)\.[^.@]+$/.exec(u);
    if (m) base = m[1];
    const c = [u];
    if (tgtSuffix) c.push(`${base}.${tgtSuffix}`, `${u}.${tgtSuffix}`); else c.push(base);
    cands[u] = [...new Set(c)];
  }
  const all = [...new Set(Object.values(cands).flat())].sort();
  const inList = all.map((x) => "'" + x.replace(/'/g, "\\'") + "'").join(',');
  const q = encodeURIComponent(`SELECT Username FROM User WHERE IsActive = true AND Username IN (${inList})`);
  const found = (await getOrgJson(org, `/services/data/v${ver}/query?q=${q}`)).records.map((r) => r.Username.toLowerCase());
  const map = {};
  for (const u of users) {
    const hit = cands[u].find((c) => found.includes(c.toLowerCase()));
    if (!hit) map[u] = { To: me, Fallback: true };
    else if (hit !== u) map[u] = { To: hit, Fallback: false };
  }
  if (!Object.keys(map).length) { rmrf(tmp); return out; }

  for (const f of sites) {
    const text = readText(f);
    const base = path.basename(f, '.site');
    const next = text.replace(rx, (all2, field, u) => {
      if (!map[u]) return all2;
      const to = map[u].To;
      out.Fixes.push(`CustomSite ${base} ${field}: ${u} -> ${to}` +
        (map[u].Fallback ? " (no matching user in the target, so your connected user is used; change it in the site's Administration > Preferences if needed)" : ''));
      return `<${field}>${to}</${field}>`;
    });
    if (next !== text) writeText(f, next);
  }
  const pk = walk(tmp).filter((f) => path.basename(f) === 'package.xml').sort((a, b) => a.length - b.length)[0];
  fs.renameSync(path.dirname(pk), dir);
  rmrf(tmp);
  out.Path = dir;
  return out;
}

// Builds the rollback folder from a backup: the target's previous versions, with package.xml limited to what existed,
// plus destructiveChangesPost.xml for components the deploy added. sf zips the folder itself when deploying it.
function newRollbackDir(backupDir, packageXml, destructiveXml) {
  const rb = path.join(backupDir, 'rollback');
  const tmp = path.join(backupDir, 'rollback-tmp');
  rmrf(rb); rmrf(tmp);
  const retrieved = path.join(backupDir, 'retrieved');
  const src = exists(retrieved) ? walk(retrieved).find((f) => f.toLowerCase().endsWith('.zip')) : null;
  if (src) {
    unzip(src, tmp);
    const pk = walk(tmp).filter((f) => path.basename(f) === 'package.xml').sort((a, b) => a.length - b.length)[0];
    if (pk) fs.renameSync(path.dirname(pk), rb); else fs.renameSync(tmp, rb);
    rmrf(tmp);
  } else {
    mkdirp(rb);
  }
  writeText(path.join(rb, 'package.xml'), packageXml);
  if (destructiveXml) writeText(path.join(rb, 'destructiveChangesPost.xml'), destructiveXml);
  return rb;
}

function addDeployLog(name, line) {
  fs.appendFileSync(path.join(PkgRoot, name, 'deploys.jsonl'), String(line).replace(/[\r\n]/g, ' ') + '\n', 'utf8');
}

// ---------- opening windows and links ----------
function detached(cmd, args) {
  try {
    const c = spawn(cmd, args, { detached: true, stdio: 'ignore', windowsHide: true });
    c.on('error', () => {});
    c.unref();
    return true;
  } catch { return false; }
}
function openDefault(target) {
  if (IS_MAC) return detached('open', [target]);
  if (IS_WIN) return detached('rundll32', ['url.dll,FileProtocolHandler', target]);
  return detached('xdg-open', [target]);
}
function openFolder(dir) {
  if (IS_MAC) return detached('open', [dir]);
  if (IS_WIN) return detached('explorer.exe', [dir]);
  return detached('xdg-open', [dir]);
}
// Chrome or Edge can show a page as its own app window (no tabs, no address bar).
function findAppBrowser() {
  if (IS_MAC) {
    for (const app of ['Google Chrome', 'Microsoft Edge', 'Brave Browser', 'Chromium']) {
      if (exists(`/Applications/${app}.app`) || exists(path.join(os.homedir(), 'Applications', `${app}.app`))) return { mac: app };
    }
    return null;
  }
  const cands = IS_WIN
    ? [path.join(process.env.ProgramFiles || '', 'Google/Chrome/Application/chrome.exe'),
       path.join(process.env['ProgramFiles(x86)'] || '', 'Google/Chrome/Application/chrome.exe'),
       path.join(process.env.LOCALAPPDATA || '', 'Google/Chrome/Application/chrome.exe'),
       path.join(process.env['ProgramFiles(x86)'] || '', 'Microsoft/Edge/Application/msedge.exe'),
       path.join(process.env.ProgramFiles || '', 'Microsoft/Edge/Application/msedge.exe')]
    : ['/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/microsoft-edge'];
  const p = cands.find((c) => c && exists(c));
  return p ? { exe: p } : null;
}
function openAppWindow(url) {
  if (NoBrowser) return;
  const b = findAppBrowser();
  if (!b) { openDefault(url); return; }
  // A private browser profile just for this window keeps it out of the person's tabs and sign-ins.
  let profileDir = path.join(Root, 'browser-profile');
  try { mkdirp(profileDir); } catch { profileDir = path.join(os.tmpdir(), AppName.replace(/ /g, '-') + '-profile'); mkdirp(profileDir); }
  const flags = [`--app=${url}`, '--window-size=1400,940', `--user-data-dir=${profileDir}`,
    '--no-first-run', '--no-default-browser-check', '--disable-sync'];
  if (b.mac) detached('open', ['-na', b.mac, '--args', ...flags]);
  else detached(b.exe, flags);
}

// ---------- responses ----------
function sendResponse(res, code, type, text) {
  const bytes = Buffer.from(text, 'utf8');
  res.writeHead(code, { 'Content-Type': `${type}; charset=utf-8`, 'Cache-Control': 'no-store', 'Content-Length': bytes.length });
  res.end(bytes);
}
const sendJson = (res, obj, code = 200) => sendResponse(res, code, 'application/json', JSON.stringify(obj));

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

// ---------- routes ----------
let running = true;
let lastSeen = Date.now();

async function handleRequest(req, res) {
  const url = new URL(req.url, 'http://localhost');
  const p = url.pathname;
  const host = String(req.headers.host || '');
  if (host !== `localhost:${Port}` && host !== `127.0.0.1:${Port}`) { sendResponse(res, 403, 'text/plain', 'Forbidden'); return; }
  if (p === '/' || p === '/index.html') {
    sendResponse(res, 200, 'text/html', readText(path.join(Root, 'index.html')).split('{{TOKEN}}').join(Token));
    return;
  }
  if (!p.startsWith('/api/')) { sendResponse(res, 404, 'text/plain', 'Not found'); return; }
  if (req.headers['x-token'] !== Token) { sendJson(res, { error: 'Forbidden' }, 403); return; }

  let b = {};
  const text = await readBody(req);
  if (text) b = JSON.parse(text);

  switch (p) {
    case '/api/health': {
      const stale = fs.statSync(fileURLToPath(import.meta.url)).mtimeMs > StartedAt;
      sendJson(res, { sf: !!SfPath, sfPath: SfPath, sfVersion: SfVersion, packagesDir: PkgRoot, dataDir: DataDir, version: Version, stale });
      return;
    }
    case '/api/orgs': {
      const r = await invokeSf(['org', 'list', '--json'], 120);
      sendJson(res, { raw: r.out, err: r.err });
      return;
    }
    case '/api/login': {
      const alias = assertMatch(b.alias, /^[\w.\-]{1,60}$/, 'alias');
      const instanceUrl = assertMatch(b.instanceUrl, /^https:\/\/[\w.\-]+(:\d+)?\/?$/, 'login URL');
      const r = await invokeSf(['org', 'login', 'web', '--alias', alias, '--instance-url', instanceUrl, '--json'], 600);
      sendJson(res, { raw: r.out, err: r.err });
      return;
    }
    case '/api/alias': {
      // Renames a connected org's alias in the Salesforce CLI (an empty alias just removes the old one).
      const org = assertOrg(b.org);
      let alias = String(b.alias || '');
      if (alias) alias = assertMatch(alias, /^[\w.\-]{1,60}$/, 'alias');
      let old = String(b.old || '');
      if (old) old = assertMatch(old, /^[\w.\-]{1,60}$/, 'alias');
      let r = null;
      if (alias) r = await invokeSf(['alias', 'set', `${alias}=${org}`, '--json'], 120);
      if (old && old !== alias) { const u = await invokeSf(['alias', 'unset', old, '--json'], 120); if (!r) r = u; }
      sendJson(res, { raw: r ? r.out : '', err: r ? r.err : '' });
      return;
    }
    case '/api/logout': {
      const org = assertOrg(b.org);
      const r = await invokeSf(['org', 'logout', '--target-org', org, '--no-prompt', '--json'], 120);
      Sessions.delete(org);
      sendJson(res, { raw: r.out, err: r.err });
      return;
    }
    case '/api/orginfo': {
      const org = assertOrg(b.org);
      const s = await getOrgSession(org, true);
      const versions = await getOrgJson(org, '/services/data/');
      const ver = Math.max(...versions.map((v) => parseFloat(v.version))).toFixed(1);
      const q = encodeURIComponent('SELECT Name, IsSandbox, OrganizationType FROM Organization');
      const o = (await getOrgJson(org, `/services/data/v${ver}/query?q=${q}`)).records[0];
      const uq = encodeURIComponent("SELECT Name FROM User WHERE Username = '" + String(s.Username).replace(/'/g, "\\'") + "'");
      const u = (await getOrgJson(org, `/services/data/v${ver}/query?q=${uq}`)).records;
      sendJson(res, {
        org, apiVersion: ver, instanceUrl: s.Url, username: s.Username,
        name: o.Name, isSandbox: !!o.IsSandbox, orgType: o.OrganizationType,
        userFullName: u.length ? u[0].Name : ''
      });
      return;
    }
    case '/api/listmetadata': {
      const org = assertOrg(b.org);
      const ver = assertVersion(b.apiVersion);
      const qs = (b.queries || []).map((q) => {
        const t = assertMatch(q.type, /^[A-Za-z]{2,80}$/, 'metadata type');
        const folder = q.folder ? '<met:folder>' + xmlEscape(String(q.folder)) + '</met:folder>' : '';
        return `<met:queries>${folder}<met:type>${t}</met:type></met:queries>`;
      });
      const envelope = '<?xml version="1.0" encoding="UTF-8"?>' +
        '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:met="http://soap.sforce.com/2006/04/metadata">' +
        '<soapenv:Header><met:SessionHeader><met:sessionId>{{SESSION}}</met:sessionId></met:SessionHeader></soapenv:Header>' +
        '<soapenv:Body><met:listMetadata>' + qs.join('') + `<met:asOfVersion>${ver}</met:asOfVersion></met:listMetadata></soapenv:Body></soapenv:Envelope>`;
      const r = await invokeOrgApi(org, 'POST', `/services/Soap/m/${ver}`, envelope, 'text/xml; charset=utf-8', true);
      sendResponse(res, 200, 'text/xml', r.body);
      return;
    }
    case '/api/retrieve': {
      const org = assertOrg(b.org);
      const name = assertPkgName(b.name);
      const dir = path.join(PkgRoot, name);
      for (const sub of ['retrieved', 'contents']) rmrf(path.join(dir, sub));
      mkdirp(dir);
      const manifest = path.join(dir, 'package.xml');
      writeText(manifest, String(b.packageXml));
      const meta = {
        name, sourceOrg: org, sourceLabel: String(b.sourceLabel || ''), apiVersion: String(b.apiVersion || ''),
        components: Number(b.count) || 0, note: String(b.note || ''), created: new Date().toISOString()
      };
      writeText(path.join(dir, 'meta.json'), JSON.stringify(meta));
      const r = await invokeSf(['project', 'retrieve', 'start', '--manifest', manifest, '--target-metadata-dir', path.join(dir, 'retrieved'),
        '--zip-file-name', 'unpackaged.zip', '--target-org', org, '--wait', '60', '--json'], 3900);
      const zip = getPackageZip(name);
      if (zip) {
        try { unzip(zip, path.join(dir, 'contents')); } catch (e) { log('Could not unzip for browsing: ' + e.message); }
      }
      sendJson(res, { ok: !!zip, zip, dir, raw: r.out, err: r.err });
      return;
    }
    case '/api/deploy': {
      const org = assertOrg(b.target);
      const name = assertPkgName(b.pkg);
      const mode = assertMatch(b.mode, /^(validate|deploy|quick|rollback)$/, 'mode');
      const level = assertMatch(b.testLevel, /^(NoTestRun|RunSpecifiedTests|RunLocalTests|RunAllTestsInOrg)$/, 'test level');
      let testArgs = ['--test-level', level];
      if (level === 'RunSpecifiedTests') {
        const tests = (b.tests || []).filter(Boolean);
        if (!tests.length) throw new Error('List at least one test class for RunSpecifiedTests.');
        for (const t of tests) testArgs = testArgs.concat(['--tests', assertMatch(t, /^[\w.]{1,255}$/, 'test name')]);
      }
      let backupId = '';
      if (b.backupId) backupId = assertBackupId(b.backupId);
      let fixes = [];
      let a;
      if (mode === 'quick') {
        a = ['project', 'deploy', 'quick', '--job-id', assertJobId(b.jobId)];
      } else if (mode === 'rollback') {
        const rb = path.join(PkgRoot, name, 'backups', backupId, 'rollback');
        if (!backupId || !exists(path.join(rb, 'package.xml'))) throw new Error('That rollback point has no rollback package.');
        a = ['project', 'deploy', 'start', '--metadata-dir', rb, ...testArgs];
      } else {
        const src = await getDeploySource(name, org);
        if (!src) throw new Error(`Package '${name}' has no retrieved zip. Build it first.`);
        fixes = src.Fixes;
        for (const f of fixes) log(f);
        if (mode === 'deploy') a = ['project', 'deploy', 'start', '--metadata-dir', src.Path, ...testArgs];
        else if (level === 'NoTestRun') a = ['project', 'deploy', 'start', '--dry-run', '--metadata-dir', src.Path, ...testArgs];
        else a = ['project', 'deploy', 'validate', '--metadata-dir', src.Path, ...testArgs];
      }
      const r = await invokeSf([...a, '--target-org', org, '--async', '--json'], 600);
      let id = '';
      try { id = parseSfJson(r.out).result.id; } catch {}
      addDeployLog(name, JSON.stringify({ time: new Date().toISOString(), event: 'start', mode, target: org, testLevel: level, jobId: id, backupId }));
      sendJson(res, { raw: r.out, err: r.err, fixes });
      return;
    }
    case '/api/backup': {
      // Retrieves the package's components from the target as they are now, before a deploy changes them.
      const org = assertOrg(b.target);
      const name = assertPkgName(b.pkg);
      const manifest = path.join(PkgRoot, name, 'package.xml');
      if (!exists(manifest)) throw new Error(`Package '${name}' has no package.xml.`);
      const id = org.replace(/[^\w\-]/g, '_') + '-' + stamp();
      const bdir = path.join(PkgRoot, name, 'backups', id);
      mkdirp(bdir);
      const r = await invokeSf(['project', 'retrieve', 'start', '--manifest', manifest, '--target-metadata-dir', path.join(bdir, 'retrieved'),
        '--zip-file-name', 'backup.zip', '--target-org', org, '--wait', '60', '--json'], 3900);
      sendJson(res, { id, raw: r.out, err: r.err });
      return;
    }
    case '/api/rollback/prepare': {
      const name = assertPkgName(b.pkg);
      const id = assertBackupId(b.id);
      const bdir = path.join(PkgRoot, name, 'backups', id);
      if (!exists(bdir)) throw new Error(`Backup ${id} not found.`);
      JSON.parse(String(b.meta));
      const rb = newRollbackDir(bdir, String(b.packageXml), String(b.destructiveXml || ''));
      writeText(path.join(bdir, 'backup.json'), String(b.meta));
      sendJson(res, { ok: true, dir: rb });
      return;
    }
    case '/api/report': {
      const org = assertOrg(b.target);
      const id = assertJobId(b.jobId);
      const r = await invokeSf(['project', 'deploy', 'report', '--job-id', id, '--target-org', org, '--json'], 300);
      sendJson(res, { raw: r.out, err: r.err });
      return;
    }
    case '/api/cancel': {
      const org = assertOrg(b.target);
      const id = assertJobId(b.jobId);
      const r = await invokeSf(['project', 'deploy', 'cancel', '--job-id', id, '--target-org', org, '--async', '--json'], 300);
      sendJson(res, { raw: r.out, err: r.err });
      return;
    }
    case '/api/logdeploy': {
      const name = assertPkgName(b.pkg);
      if (exists(path.join(PkgRoot, name))) addDeployLog(name, String(b.line));
      sendJson(res, { ok: true });
      return;
    }
    case '/api/packages': {
      const read = (d, f) => { const f2 = path.join(d, f); return exists(f2) ? readText(f2) : ''; };
      const dirs = listDirs(PkgRoot)
        .map((n) => ({ n, t: fs.statSync(path.join(PkgRoot, n)).birthtimeMs }))
        .sort((x, y) => y.t - x.t);
      const list = dirs.map(({ n }) => {
        const d = path.join(PkgRoot, n);
        const backups = listDirs(path.join(d, 'backups'))
          .filter((bn) => exists(path.join(d, 'backups', bn, 'backup.json')) && exists(path.join(d, 'backups', bn, 'rollback', 'package.xml')))
          .map((bn) => readText(path.join(d, 'backups', bn, 'backup.json')));
        return {
          name: n, meta: read(d, 'meta.json'), packageXml: read(d, 'package.xml'), deploys: read(d, 'deploys.jsonl'),
          hasZip: !!getPackageZip(n), backups, archived: exists(path.join(d, 'archived.flag'))
        };
      });
      sendJson(res, { packages: list });
      return;
    }
    case '/api/templates': {
      const f = path.join(DataDir, 'templates.json');
      if (b && b.json !== undefined && b.json !== null) {
        const t = String(b.json);
        JSON.parse(t); // refuse to save anything that isn't valid JSON
        if (exists(f)) fs.copyFileSync(f, f + '.bak');
        writeText(f, t);
      }
      sendJson(res, { raw: exists(f) ? readText(f) : '[]' });
      return;
    }
    case '/api/package/archive': {
      const name = assertPkgName(b.pkg);
      const dir = path.join(PkgRoot, name);
      if (!exists(dir)) throw new Error(`Package '${name}' not found.`);
      const flag = path.join(dir, 'archived.flag');
      if (b.archived) writeText(flag, new Date().toISOString()); else rmrf(flag);
      sendJson(res, { ok: true });
      return;
    }
    case '/api/package/delete': {
      const name = assertPkgName(b.pkg);
      const dir = path.join(PkgRoot, name);
      if (!exists(dir)) throw new Error(`Package '${name}' not found.`);
      rmrf(dir);
      log('Deleted package ' + name);
      sendJson(res, { ok: true });
      return;
    }
    case '/api/open': {
      let dir = DataDir;
      if (b.pkg) dir = path.join(PkgRoot, assertPkgName(b.pkg));
      if (!exists(dir)) dir = PkgRoot;
      openFolder(dir);
      sendJson(res, { ok: true });
      return;
    }
    case '/api/ping':
      sendJson(res, { ok: true });
      return;
    case '/api/openurl': {
      // Links open in the person's normal browser, where they're signed in to Salesforce, not in the app window.
      const u = assertMatch(b.url, /^(https?:\/\/|mailto:)[^\s"]{1,4000}$/, 'link');
      openDefault(u);
      sendJson(res, { ok: true });
      return;
    }
    case '/api/shutdown':
      sendJson(res, { ok: true });
      running = false;
      return;
    default:
      sendJson(res, { error: `Unknown endpoint ${p}` }, 404);
  }
}

// ---------- start ----------
async function main() {
  mkdirp(PkgRoot);
  mkdirp(path.join(WorkDir, 'force-app'));
  if (exists(LogFile)) { try { fs.renameSync(LogFile, path.join(DataDir, 'server-previous.log')); } catch {} }
  const projFile = path.join(WorkDir, 'sfdx-project.json');
  if (!exists(projFile)) writeText(projFile, '{"packageDirectories":[{"path":"force-app","default":true}],"sourceApiVersion":"60.0"}');

  // Already running (e.g. the shortcut was clicked again)? Open that copy instead of starting a second one.
  if (exists(RunFile)) {
    try {
      const run = JSON.parse(readText(RunFile));
      const r = await fetch(`http://127.0.0.1:${run.port}/`, { signal: AbortSignal.timeout(3000) });
      if (r.status === 200 && (await r.text()).includes(AppName)) { openAppWindow(`http://127.0.0.1:${run.port}/`); process.exit(0); }
    } catch {}
  }

  SfPath = findSf();
  if (SfPath) {
    try { SfVersion = (await invokeSf(['--version'], 120)).out.trim(); } catch {}
    log('Salesforce CLI: ' + SfVersion);
  } else {
    log('Salesforce CLI (sf) not found. Install it from https://developer.salesforce.com/tools/salesforcecli');
  }

  const server = http.createServer((req, res) => {
    handleRequest(req, res).catch((e) => {
      log('Error: ' + e.message);
      try { sendJson(res, { error: e.message }, 500); } catch {}
    }).finally(() => { lastSeen = Date.now(); });
  });

  let listening = false;
  for (let p = Port; p < Port + 10 && !listening; p++) {
    listening = await new Promise((resolve) => {
      const onErr = () => resolve(false);
      server.once('error', onErr);
      server.listen(p, '127.0.0.1', () => { server.off('error', onErr); Port = p; resolve(true); });
    });
  }
  if (!listening) { log(`Could not open a local port between ${Port} and ${Port + 9}.`); process.exit(1); }

  const url = `http://127.0.0.1:${Port}/`;
  writeText(RunFile, JSON.stringify({ pid: process.pid, port: Port }));
  log(`${AppName} ${Version} is running at ${url}  (Ctrl+C or the Stop Server button to quit)`);
  log('Packages are saved in ' + PkgRoot);
  openAppWindow(url);

  // The page checks in every minute. When nothing has called for this long (its window was closed), the server
  // stops on its own instead of lingering in the background. Deployments already started carry on in Salesforce.
  const idleLimit = IdleMinutes * 60 * 1000;
  let tick = Date.now();
  const finish = () => { try { rmrf(RunFile); } catch {} log('Stopped.'); process.exit(0); };
  process.on('SIGINT', finish);
  process.on('SIGTERM', finish);
  setInterval(() => {
    const now = Date.now();
    // A long gap between ticks means the computer was asleep: give the window time to check in again after waking.
    if (now - tick > 60000) lastSeen = now;
    tick = now;
    if (!running) { server.close(); finish(); }
    if (now - lastSeen > idleLimit) { log(`No window open for ${IdleMinutes} min; stopping.`); finish(); }
  }, 500);
}

main().catch((e) => { log('Fatal: ' + e.message); process.exit(1); });
