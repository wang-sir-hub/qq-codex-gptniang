import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomInt} from 'node:crypto';

const root = path.dirname(fileURLToPath(import.meta.url));
const localDir = path.join(root, '.local');
const ownerFile = path.join(localDir, 'owner.json');
if (fs.existsSync(ownerFile)) throw new Error('Owner already paired. Review the local owner file before re-pairing.');
const creds = JSON.parse(fs.readFileSync(path.join(localDir, 'credentials.json'), 'utf8'));
const code = String(randomInt(100000, 1000000));
async function request(url, options) {
  const res = await fetch(url, {...options, signal: AbortSignal.timeout(20000)});
  const data = await res.json();
  if (!res.ok) throw new Error(`QQ HTTP ${res.status}; code=${data.code ?? data.errcode ?? 'unknown'}`);
  return data;
}
const auth = await request('https://bots.qq.com/app/getAppAccessToken', {
  method:'POST', headers:{'Content-Type':'application/json'},
  body:JSON.stringify({appId:creds.appId, clientSecret:creds.appSecret})
});
if (!auth.access_token) throw new Error('No QQ access token returned.');
const gateway = await request('https://api.sgroup.qq.com/gateway/bot', {
  headers:{Authorization:`QQBot ${auth.access_token}`}
});
if (!gateway.url?.startsWith('wss://')) throw new Error('Invalid gateway URL.');
let sequence = null, heartbeat, paired = false;
const ws = new WebSocket(gateway.url);
const timeout = setTimeout(()=>{console.log('Pairing expired. Run again for a new code.');ws.close();}, 600000);
ws.addEventListener('message', event=>{
  try {
    const message = JSON.parse(String(event.data));
    if (message.s != null) sequence = message.s;
    if (message.op === 10) {
      ws.send(JSON.stringify({op:2,d:{token:`QQBot ${auth.access_token}`,intents:1<<25,shard:[0,1]}}));
      heartbeat = setInterval(()=>{
        if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({op:1,d:sequence}));
      }, message.d.heartbeat_interval || 41250);
    }
    if (message.t === 'READY') console.log(`READY: privately send this code to your bot: ${code}`);
    if (!paired && message.t === 'C2C_MESSAGE_CREATE' && String(message.d?.content || '').trim() === code) {
      const ownerOpenId = message.d?.author?.user_openid;
      if (typeof ownerOpenId !== 'string' || !/^[A-Za-z0-9_-]+$/.test(ownerOpenId)) return;
      paired = true;
      fs.writeFileSync(ownerFile, JSON.stringify({ownerOpenId, pairedAt:new Date().toISOString()},null,2));
      console.log('OWNER_PAIRED: review the local owner file before starting the bridge.');
      ws.close();
    }
    if (message.op === 9 || message.op === 7) { console.log('Gateway session changed. Run pairing again.'); ws.close(); }
  } catch { console.error('Invalid gateway message.'); ws.close(); process.exitCode = 1; }
});
ws.addEventListener('error', ()=>{console.error('QQ WebSocket error.');ws.close();process.exitCode=1;});
ws.addEventListener('close', ()=>{clearTimeout(timeout);clearInterval(heartbeat);if(!paired)process.exitCode=1;});
