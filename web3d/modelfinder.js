// Model-finder bot: for each kind of tool, find a realistic free 3D model on Sketchfab (official API),
// let Claude pick the best candidate by looking at the previews, download it, fit it to the tool's size,
// and keep it in a library so it is only ever found once.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const API = 'https://api.sketchfab.com/v3';

// ---------------------------------------------------------------------------
// What to search for
// ---------------------------------------------------------------------------
const TERMS = {
  'locking-pliers': { _: 'locking pliers', 'long-nose': 'long nose locking pliers' },
  pliers: { _: 'pliers', lineman: 'lineman pliers', diagonal: 'diagonal cutter pliers', 'long-nose': 'needle nose pliers',
    'slip-joint': 'slip joint pliers', 'groove-joint': 'tongue and groove pliers', stripper: 'wire stripper', snips: 'tin snips' },
  screwdriver: { _: 'screwdriver' }, pick: { _: 'pick tool' }, wrench: { _: 'combination wrench' },
  'adjustable-wrench': { _: 'adjustable wrench' }, ratchet: { _: 'ratchet wrench' }, socket: { _: 'socket wrench socket' },
  hammer: { _: 'hammer', claw: 'claw hammer', 'ball-peen': 'ball peen hammer' }, 'utility-knife': { _: 'utility knife', folding: 'folding utility knife' },
  'tape-measure': { _: 'tape measure' }, 'pry-bar': { _: 'pry bar' },
  'power-tool': { _: 'cordless drill', impact: 'impact driver', screwdriver: 'cordless screwdriver' },
  'hex-key': { _: 'allen key' }, punch: { _: 'punch tool', chisel: 'cold chisel' }, file: { _: 'metal file' }, flashlight: { _: 'flashlight' },
};
/** Library key: one realistic model per tool type + variant. */
export const libraryKey = model => `${model?.type || 'box'}|${model?.variant || ''}`;
export function searchTerms(model) {
  const t = TERMS[model?.type]; if (!t) return [];
  return [...new Set([t[model.variant], t._].filter(Boolean))];
}

// ---------------------------------------------------------------------------
// 1. Search (no account needed)
// ---------------------------------------------------------------------------
const JUNK = /\b(pack|collection|set|kit|assets?|workbench|bench|toolbelt|belt|scene|room|garage|shop|weapons?|gun|rifle|sword|props)\b/i;
export async function searchCandidates(model, max = 8) {
  const seen = new Set(), out = [];
  for (const q of searchTerms(model)) {
    const url = `${API}/search?type=models&downloadable=true&count=24&sort_by=-likeCount&q=${encodeURIComponent(q)}`;
    const r = await fetch(url); if (!r.ok) continue;
    for (const m of (await r.json()).results || []) {
      const lic = (m.license?.label || '').toLowerCase();
      if (seen.has(m.uid) || JUNK.test(m.name)) continue;
      if (lic.includes('noncommercial') || lic.includes('noderivs') || lic.includes('editorial')) continue;   // must be reusable
      if (m.faceCount > 400000) continue;   // too heavy for a phone
      const img = (m.thumbnails?.images || []).sort((a, b) => Math.abs(a.width - 400) - Math.abs(b.width - 400))[0];
      if (!img) continue;
      seen.add(m.uid);
      out.push({ uid: m.uid, name: m.name, author: m.user?.displayName || m.user?.username || '', license: m.license?.label || '',
        url: m.viewerUrl, thumb: img.url, faces: m.faceCount, likes: m.likeCount });
    }
    if (out.length >= max) break;
  }
  return out.slice(0, max);
}

// ---------------------------------------------------------------------------
// 2. Let Claude look at the previews and pick
// ---------------------------------------------------------------------------
async function toB64(src, max = 512) {
  const img = new Image(); img.crossOrigin = 'anonymous'; img.src = src; await img.decode();
  const k = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
  const c = document.createElement('canvas'); c.width = Math.round(img.naturalWidth * k); c.height = Math.round(img.naturalHeight * k);
  c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
  return c.toDataURL('image/jpeg', 0.85).split(',')[1];
}
export async function pickCandidate({ tool, candidates, photo, anthropicKey, promptText }) {
  if (!candidates.length) return { pick: 0, why: 'No downloadable models found.' };
  if (!anthropicKey) return { pick: 1, score: 0.3, why: 'No API key: took the most-liked candidate.' };
  const content = [];
  if (photo) { content.push({ type: 'text', text: "Owner's photo of the tool:" }); content.push({ type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: await toB64(photo) } }); }
  for (const [i, c] of candidates.entries()) {
    try { content.push({ type: 'text', text: `Candidate ${i + 1}: "${c.name}"` }); content.push({ type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: await toB64(c.thumb, 400) } }); }
    catch { content.push({ type: 'text', text: `(Candidate ${i + 1} preview failed to load)` }); }
  }
  content.push({ type: 'text', text: promptText.replace('{{TOOL}}', `${tool.name} (${tool.model?.type}${tool.model?.variant ? ', ' + tool.model.variant : ''})`)
    .replace('{{PHOTO_NOTE}}', photo ? 'First comes the owner\'s photo of their tool.' : 'There is no photo of the owner\'s tool.').replace('{{N}}', candidates.length) });
  const res = await fetch('https://api.anthropic.com/v1/messages', { method: 'POST',
    headers: { 'x-api-key': anthropicKey, 'anthropic-version': '2023-06-01', 'content-type': 'application/json', 'anthropic-dangerous-direct-browser-access': 'true' },
    body: JSON.stringify({ model: 'claude-sonnet-5-5', max_tokens: 300, messages: [{ role: 'user', content }] }) });
  if (!res.ok) throw new Error(`AI request failed (${res.status})`);
  const out = ((await res.json()).content.find(x => x.type === 'text') || {}).text || '';
  return JSON.parse(out.slice(out.indexOf('{'), out.lastIndexOf('}') + 1));
}

// ---------------------------------------------------------------------------
// 3. Download (needs the owner's free Sketchfab API token)
// ---------------------------------------------------------------------------
export async function downloadModel(uid, sketchfabToken) {
  if (!sketchfabToken) throw new Error('Downloading needs a Sketchfab API token (free account → Settings → Password & API).');
  const r = await fetch(`${API}/models/${uid}/download`, { headers: { Authorization: `Token ${sketchfabToken}` } });
  if (!r.ok) throw new Error(`Sketchfab download refused (${r.status})`);
  const links = await r.json();
  if (links.glb?.url) return { kind: 'glb', data: await (await fetch(links.glb.url)).arrayBuffer() };
  if (links.gltf?.url) return { kind: 'zip', data: await (await fetch(links.gltf.url)).arrayBuffer() };
  throw new Error('No glTF download offered for this model.');
}

// ---------------------------------------------------------------------------
// 4. Fit: lay the model flat along its longest axis and scale it to the tool's real length
// ---------------------------------------------------------------------------
async function parse(entry) {
  const loader = new GLTFLoader();
  if (entry.kind === 'glb') return (await loader.parseAsync(entry.data, '')).scene;
  const { default: JSZip } = await import('https://cdn.jsdelivr.net/npm/jszip@3.10.1/+esm');
  const zip = await JSZip.loadAsync(entry.data), urls = {};
  for (const [name, f] of Object.entries(zip.files)) if (!f.dir) urls[name] = URL.createObjectURL(await f.async('blob'));
  const main = Object.keys(urls).find(n => n.endsWith('.gltf'));
  const mgr = new THREE.LoadingManager(); mgr.setURLModifier(u => { const k = Object.keys(urls).find(n => u.endsWith(n.split('/').pop())); return k ? urls[k] : u; });
  return (await new GLTFLoader(mgr).loadAsync(urls[main])).scene;
}
function principalAxes(obj) {
  // covariance of (a sample of) the world-space vertices, then a Jacobi eigen-solve
  obj.updateWorldMatrix(true, true);
  const pts = [], v = new THREE.Vector3();
  obj.traverse(o => {
    if (!o.isMesh) return; const p = o.geometry.attributes.position, step = Math.max(1, Math.floor(p.count / 4000));
    for (let i = 0; i < p.count; i += step) pts.push(v.fromBufferAttribute(p, i).applyMatrix4(o.matrixWorld).clone());
  });
  const c = pts.reduce((a, p) => a.add(p), new THREE.Vector3()).divideScalar(pts.length);
  const A = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
  for (const p of pts) { const d = [p.x - c.x, p.y - c.y, p.z - c.z]; for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) A[i][j] += d[i] * d[j]; }
  const V = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];
  for (let sweep = 0; sweep < 30; sweep++) for (const [p, q] of [[0, 1], [0, 2], [1, 2]]) {
    if (Math.abs(A[p][q]) < 1e-12) continue;
    const th = (A[q][q] - A[p][p]) / (2 * A[p][q]), t = Math.sign(th || 1) / (Math.abs(th) + Math.sqrt(th * th + 1)), cs = 1 / Math.sqrt(t * t + 1), sn = t * cs;
    for (let k = 0; k < 3; k++) { const a = A[k][p], b = A[k][q]; A[k][p] = cs * a - sn * b; A[k][q] = sn * a + cs * b; }
    for (let k = 0; k < 3; k++) { const a = A[p][k], b = A[q][k]; A[p][k] = cs * a - sn * b; A[q][k] = sn * a + cs * b; }
    for (let k = 0; k < 3; k++) { const a = V[k][p], b = V[k][q]; V[k][p] = cs * a - sn * b; V[k][q] = sn * a + cs * b; }
  }
  const ev = [0, 1, 2].map(i => ({ val: A[i][i], vec: new THREE.Vector3(V[0][i], V[1][i], V[2][i]).normalize() })).sort((a, b) => b.val - a.val);
  return { center: c, axes: ev.map(e => e.vec) };
}
/** Returns a group: the model lying along x (longest), y (middle), z (thinnest), centered, `lengthIn` long. */
export async function fitModel(entry, lengthIn) {
  const scene = await parse(entry);
  scene.traverse(o => { if (o.isMesh) { o.castShadow = true; } });
  const { center, axes } = principalAxes(scene);
  const z = axes[2].clone(); if (new THREE.Vector3().crossVectors(axes[0], axes[1]).dot(z) < 0) z.negate();
  const basis = new THREE.Matrix4().makeBasis(axes[0], axes[1], z);              // model axes → world
  const toFlat = basis.clone().invert().multiply(new THREE.Matrix4().makeTranslation(-center.x, -center.y, -center.z));
  const inner = new THREE.Group(); inner.add(scene); inner.applyMatrix4(toFlat);
  const outer = new THREE.Group(); outer.add(inner);
  const size = new THREE.Box3().setFromObject(outer).getSize(new THREE.Vector3());
  outer.scale.setScalar((+lengthIn || 8) / Math.max(size.x, 1e-6));
  const c2 = new THREE.Box3().setFromObject(outer).getCenter(new THREE.Vector3()); inner.position.sub(c2.divideScalar(outer.scale.x));
  return outer;
}

// ---------------------------------------------------------------------------
// 5. Library (this browser for now; shared cloud storage in the app)
// ---------------------------------------------------------------------------
const DB = 'toolModels', STORE = 'models';
function db() { return new Promise((ok, no) => { const r = indexedDB.open(DB, 1); r.onupgradeneeded = () => r.result.createObjectStore(STORE); r.onsuccess = () => ok(r.result); r.onerror = () => no(r.error); }); }
async function idb(mode, fn) { const d = await db(); return new Promise((ok, no) => { const t = d.transaction(STORE, mode), q = fn(t.objectStore(STORE)); q.onsuccess = () => ok(q.result); q.onerror = () => no(q.error); }); }
export const library = {
  get: key => idb('readonly', s => s.get(key)).catch(() => null),
  put: (key, rec) => idb('readwrite', s => s.put(rec, key)),
  all: () => idb('readonly', s => s.getAll()).catch(() => []),
  remove: key => idb('readwrite', s => s.delete(key)),
};

/** The whole bot for one kind of tool. Calls onStatus(text) as it goes. Returns the library record or null. */
export async function findAndStore(tool, { anthropicKey, sketchfabToken, photo, promptText, onStatus = () => {} }) {
  const key = libraryKey(tool.model);
  const have = await library.get(key); if (have) return have;
  onStatus(`Searching for a ${searchTerms(tool.model)[0] || tool.model?.type} model…`);
  const candidates = await searchCandidates(tool.model);
  if (!candidates.length) { onStatus('No free model found for this tool type.'); return null; }
  onStatus(`Comparing ${candidates.length} models…`);
  const pick = await pickCandidate({ tool, candidates, photo, anthropicKey, promptText });
  const c = candidates[(pick.pick || 0) - 1];
  if (!c) { onStatus(`None looked right (${pick.why || 'no match'}).`); return null; }
  onStatus(`Downloading "${c.name}"…`);
  const entry = await downloadModel(c.uid, sketchfabToken);
  const rec = { key, kind: entry.kind, data: entry.data, credit: { name: c.name, author: c.author, license: c.license, url: c.url }, why: pick.why, score: pick.score };
  await library.put(key, rec);
  onStatus(`Got "${c.name}" by ${c.author} (${c.license}).`);
  return rec;
}
