'use strict';
const vscode = require('vscode');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const net = require('node:net');
const crypto = require('node:crypto');
const VERSION = '3.5.91', SCHEMA = 1, MAX_FRAME = 1024 * 1024;
const fingerprints = {
  'out/main.js':'90fda6a0e5b4851a8a060afe1ebef3dbe69403934ab8f5669c98539b95acdf8d',
  'modules/ai-agent/libai_agent.dylib':'2e93b706d711574a717a985bc84c329aa903d9a75b4bcde83e01ce84d2450f6f',
  'out/vs/workbench/workbench.desktop.main.js':'a7a826e8191a386eb7c73bc3f6926924ef981f377721486c4480f0917b24276d',
  'node_modules/@byted-icube/ai-modules-chat/dist/index.mjs':'1198074030bb24e4b79f349c06ffc67b20feda642a9e35836c7194ed4c0fe7ac'
};
let widget, server, socketPath, lease, watching = false, stopping = false;
const clients = new Set(), pending = new Map();
let retainedThreadIDs = [];
async function fingerprint(file) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}
function send(client, value) {
  if (client.destroyed) return;
  const bytes = JSON.stringify(value) + '\n';
  if (Buffer.byteLength(bytes) > MAX_FRAME || client.writableLength > 2 * MAX_FRAME) { client.destroy(); return; }
  client.write(bytes);
}
function forward(q, timeout = 8000) {
  if (!widget || stopping) return Promise.reject(Error('Companion unavailable'));
  return new Promise((resolve, reject) => {
    const requestId = crypto.randomUUID();
    const timer = setTimeout(() => { pending.delete(requestId); reject(Error('Renderer did not respond')); }, timeout);
    pending.set(requestId, {resolve, reject, timer});
    widget.postMessage({...q, requestId}).then(sent => {
      if (!sent) { clearTimeout(timer); pending.delete(requestId); reject(Error('Renderer not attached')); }
    }, error => { clearTimeout(timer); pending.delete(requestId); reject(error); });
  });
}
function unavailable() {
  for (const client of clients) send(client, {type:'unavailable', error:'Trae companion is not ready. Reopen the Trae window if this persists.'});
}
async function begin(moduleURL) {
  if (watching || !clients.size || stopping) return;
  watching = true;
  try { await widget.postMessage({op:'start', moduleURL, retainedThreadIDs}); }
  catch { watching = false; unavailable(); }
}
exports.activate = async function(context) {
  // An extension runs only in the local host. Remote execution is out of scope.
  if (vscode.env.remoteName) return;
  const appRoot = vscode.env.appRoot;
  const product = JSON.parse(await fs.promises.readFile(path.join(appRoot, 'product.json'), 'utf8'));
  if (product.appVersion !== VERSION) return;
  for (const [file, expected] of Object.entries(fingerprints)) {
    if (await fingerprint(path.join(appRoot, file)) !== expected) return;
  }
  if (!vscode.icube?.defineComponent || !vscode.icube?.addIcubeComponentInTitleCenter) return;
  const directory = path.join(os.homedir(), 'Library/Application Support/Notchline/agents/trae');
  await fs.promises.mkdir(directory, {recursive:true, mode:0o700});
  const stat = await fs.promises.lstat(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077)) return;
  socketPath = path.join(directory, `${process.pid}.sock`);
  // Never unlink another process's endpoint. A stale PID collision requires manual cleanup.
  if (fs.existsSync(socketPath)) return;
  await vscode.icube.defineComponent(vscode.Uri.joinPath(context.extensionUri, 'bridge-v1.js'));
  widget = vscode.icube.addIcubeComponentInTitleCenter({tag:'notchline-trae-reader-v1'}, {position:'right'});
  const moduleURL = path.join(appRoot, 'node_modules/@byted-icube/ai-modules-chat/dist/index.mjs');
  context.subscriptions.push(widget, widget.onDidReceiveMessage(message => {
    const waiter = pending.get(message?.requestId);
    if (waiter) { pending.delete(message.requestId); clearTimeout(waiter.timer); message.ok ? waiter.resolve(message) : waiter.reject(Error('Renderer refused the operation')); return; }
    if (message?.type === 'snapshot') {
      for (const client of clients) send(client, message);
    } else if (message?.type === 'unavailable') { watching = false; unavailable(); }
  }));
  server = net.createServer(client => {
    let bytes = Buffer.alloc(0), subscribed = false;
    client.setTimeout(10000, () => { if (!subscribed) client.destroy(); });
    client.on('error', () => {});
    client.on('data', chunk => {
      bytes = Buffer.concat([bytes, chunk]);
      if (bytes.length > 16384) { client.destroy(); return; }
      const newline = bytes.indexOf(10); if (newline < 0) return;
      if (newline !== bytes.length - 1) { client.destroy(); return; }
      let q; try { q = JSON.parse(bytes.subarray(0, newline).toString('utf8')); } catch { client.destroy(); return; }
      bytes = Buffer.alloc(0);
      if (q.op === 'watch' && !subscribed && q.schema === SCHEMA) {
        // One Notchline observer per extension host prevents baseline resets racing.
        if (clients.size) { client.destroy(); return; }
        if (!Array.isArray(q.retainedThreadIDs ?? []) || (q.retainedThreadIDs?.length ?? 0) > 512 ||
            !(q.retainedThreadIDs ?? []).every(id => /^[a-f0-9]{24}$/.test(id))) { client.destroy(); return; }
        retainedThreadIDs = q.retainedThreadIDs ?? [];
        subscribed = true; client.setTimeout(0); clients.add(client);
        send(client, {type:'hello', schema:SCHEMA, version:VERSION, bridgeVersion:'1.2.1', pid:process.pid});
        void begin(moduleURL);
      } else if (q.op === 'read' && !subscribed && watching) {
        forward({op:'read'}, 800).then(message => {
          send(client, {ok:true, schema:SCHEMA, version:VERSION, reading:message.reading ?? null}); client.end();
        }, () => { send(client, {ok:false}); client.end(); });
      } else if (q.op === 'navigate' && !subscribed && /^[a-f0-9]{24}$/.test(q.threadID ?? '')) {
        forward({op:'navigate', threadID:q.threadID}).then(() => {
          send(client, {ok:true}); client.end();
        }, () => { send(client, {ok:false}); client.end(); });
      } else { client.destroy(); }
    });
    client.on('close', () => {
      if (!clients.delete(client)) return;
      watching = false;
      void forward({op:'stop'}).catch(() => {});
    });
  });
  server.on('error', unavailable);
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(socketPath, resolve); });
  await fs.promises.chmod(socketPath, 0o600);
  lease = setInterval(async () => {
    if (!clients.size) return;
    if (!watching) { void begin(moduleURL); return; }
    try { await forward({op:'lease'}); for (const c of clients) send(c, {type:'heartbeat', schema:SCHEMA, version:VERSION}); }
    catch { watching = false; unavailable(); }
  }, 10000);
  context.subscriptions.push({dispose:() => { void exports.deactivate(); }});
};
exports.deactivate = async function() {
  if (stopping) return;
  try { await forward({op:'stop'}); } catch {}
  stopping = true; clearInterval(lease);
  for (const c of clients) c.destroy(); clients.clear();
  for (const p of pending.values()) { clearTimeout(p.timer); p.reject(Error('Companion stopped')); } pending.clear();
  server?.close(); widget?.dispose();
  if (socketPath) { try { await fs.promises.unlink(socketPath); } catch {} }
};
