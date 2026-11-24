// Builds a 3D storage model (three.js) from the JSON spec the AI returns for a photo.
// Units: inches. Origin: floor, centered. +z is toward the viewer (front).
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

// ---------------------------------------------------------------------------
// Textures (generated, so the model works offline)
// ---------------------------------------------------------------------------
function canvasTex(size, draw) {
  const c = document.createElement('canvas'); c.width = c.height = size;
  draw(c.getContext('2d'), size);
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 4;
  return t;
}
const NOISE = canvasTex(256, (g, s) => {
  const d = g.createImageData(s, s);
  for (let i = 0; i < d.data.length; i += 4) { const v = 120 + Math.random() * 70; d.data[i] = d.data[i + 1] = d.data[i + 2] = v; d.data[i + 3] = 255; }
  g.putImageData(d, 0, 0);
});
NOISE.repeat.set(3, 3);
const WOOD = canvasTex(256, (g, s) => {
  g.fillStyle = '#fff'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 90; i++) {
    const y = Math.random() * s, v = 170 + Math.random() * 70;
    g.strokeStyle = `rgba(${v * 0.9},${v * 0.75},${v * 0.55},${0.25 + Math.random() * 0.4})`;
    g.lineWidth = 1 + Math.random() * 3;
    g.beginPath(); g.moveTo(0, y);
    for (let x = 0; x <= s; x += 16) g.lineTo(x, y + Math.sin(x / 40 + i) * 3);
    g.stroke();
  }
});
const DIAMOND = canvasTex(64, (g, s) => {
  g.fillStyle = '#808080'; g.fillRect(0, 0, s, s);
  const tread = (cx, cy, rot) => {
    g.save(); g.translate(cx, cy); g.rotate(rot);
    const gr = g.createLinearGradient(-12, 0, 12, 0); gr.addColorStop(0, '#606060'); gr.addColorStop(0.5, '#ffffff'); gr.addColorStop(1, '#606060');
    g.fillStyle = gr; g.beginPath(); g.ellipse(0, 0, 13, 3.2, 0, 0, Math.PI * 2); g.fill(); g.restore();
  };
  tread(16, 16, Math.PI / 4); tread(48, 48, Math.PI / 4); tread(48, 16, -Math.PI / 4); tread(16, 48, -Math.PI / 4);
});
const PEG = canvasTex(64, (g, s) => {
  g.fillStyle = '#fff'; g.fillRect(0, 0, s, s);
  g.fillStyle = '#141414'; g.beginPath(); g.arc(s / 2, s / 2, 6, 0, Math.PI * 2); g.fill();
});

// wire shelf deck: white lines on black, used as an alpha map (2" x 4" grid per tile)
const GRID = canvasTex(64, (g, s) => {
  g.fillStyle = '#000'; g.fillRect(0, 0, s, s);
  g.fillStyle = '#fff'; g.fillRect(0, 0, s, 6); g.fillRect(0, 0, 6, s);
});
// punched steel upright: keyhole slots
const PUNCH = canvasTex(64, (g, s) => {
  g.fillStyle = '#fff'; g.fillRect(0, 0, s, s);
  g.fillStyle = '#1a1a1a';
  g.beginPath(); g.arc(s / 2, s * 0.35, 9, 0, Math.PI * 2); g.fill();
  g.fillRect(s / 2 - 4, s * 0.35, 8, s * 0.35);
});

function rep(tex, r) {
  if (!r) return tex;
  const t = tex.clone(); t.repeat.set(Math.max(0.2, r[0]), Math.max(0.2, r[1])); t.needsUpdate = true; return t;
}

// ---------------------------------------------------------------------------
// Materials
// ---------------------------------------------------------------------------
const cache = new Map();
export function mat(color, finish = 'textured', r) {
  const key = `${color}|${finish}|${r ? r.map(v => v.toFixed(1)).join('x') : ''}`;
  if (cache.has(key)) return cache.get(key);
  const c = new THREE.Color(color);
  let m;
  switch (finish) {
    case 'gloss': m = new THREE.MeshPhysicalMaterial({ color: c, roughness: 0.25, metalness: 0.05, clearcoat: 1, clearcoatRoughness: 0.06 }); break;
    case 'satin': m = new THREE.MeshStandardMaterial({ color: c, roughness: 0.45, metalness: 0.05 }); break;
    case 'wood': m = new THREE.MeshStandardMaterial({ color: c, roughness: 0.78, map: rep(WOOD, r) }); break;
    case 'aluminum': m = new THREE.MeshStandardMaterial({ color: c, roughness: 0.3, metalness: 0.9 }); break;
    case 'diamond': m = new THREE.MeshStandardMaterial({ color: c, roughness: 0.28, metalness: 0.95, bumpMap: rep(DIAMOND, r || [8, 8]), bumpScale: 3 }); break;
    case 'plastic': m = new THREE.MeshStandardMaterial({ color: c, roughness: 0.55, metalness: 0 }); break;
    case 'pegboard': m = new THREE.MeshStandardMaterial({ color: c, roughness: 0.55, metalness: 0.1, map: rep(PEG, r) }); break;
    case 'punched': m = new THREE.MeshStandardMaterial({ color: c, roughness: 0.45, metalness: 0.1, map: rep(PUNCH, r) }); break;
    case 'wire': m = new THREE.MeshStandardMaterial({ color: c, roughness: 0.4, metalness: 0.5, alphaMap: rep(GRID, r), alphaTest: 0.5, side: THREE.DoubleSide }); break;
    default: m = new THREE.MeshStandardMaterial({ color: c, roughness: 0.45, metalness: 0.05, bumpMap: NOISE, bumpScale: 0.35 });
  }
  cache.set(key, m);
  return m;
}
const FIX = {
  chrome: new THREE.MeshStandardMaterial({ color: 0xe6e6e6, metalness: 1, roughness: 0.16 }),
  aluminum: new THREE.MeshStandardMaterial({ color: 0xc9ccd0, metalness: 0.85, roughness: 0.32 }),
  black: new THREE.MeshStandardMaterial({ color: 0x18191b, roughness: 0.5, metalness: 0.2 }),
  rubber: new THREE.MeshStandardMaterial({ color: 0x111111, roughness: 0.9 }),
  steel: new THREE.MeshStandardMaterial({ color: 0xb7b9bc, metalness: 0.9, roughness: 0.35 }),
  tray: new THREE.MeshStandardMaterial({ color: 0x3a3c40, roughness: 0.7, metalness: 0.3 }),
};
function pullMat(p) {
  if (!p || p === 'chrome') return FIX.chrome;
  if (p === 'aluminum' || p === 'silver') return FIX.aluminum;
  if (p === 'black') return mat('#151517', 'satin');
  return mat(p, 'satin');
}
function darker(hex, k) { return '#' + new THREE.Color(hex).multiplyScalar(k).getHexString(); }

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------
function box(w, h, d, m, x, y, z, r, parent) {
  const rr = Math.min(r ?? 0.08, w / 2 - 0.001, h / 2 - 0.001, d / 2 - 0.001);
  const geo = rr > 0.01 ? new RoundedBoxGeometry(w, h, d, 2, rr) : new THREE.BoxGeometry(w, h, d);
  const mesh = new THREE.Mesh(geo, m);
  mesh.position.set(x, y, z); mesh.castShadow = mesh.receiveShadow = true;
  parent.add(mesh); return mesh;
}
function cyl(r, len, m, parent, seg = 24) {
  const mesh = new THREE.Mesh(new THREE.CylinderGeometry(r, r, len, seg), m);
  mesh.castShadow = mesh.receiveShadow = true; parent.add(mesh); return mesh;
}
// Side-profile prism: pts are [z, y] pairs, extruded across x from -w/2 to w/2.
function prism(pts, w, m, parent) {
  const s = new THREE.Shape(); s.moveTo(pts[0][0], pts[0][1]); for (const p of pts.slice(1)) s.lineTo(p[0], p[1]);
  const geo = new THREE.ExtrudeGeometry(s, { depth: w, bevelEnabled: false });
  geo.rotateY(-Math.PI / 2); geo.translate(w / 2, 0, 0);
  const mesh = new THREE.Mesh(geo, m); mesh.castShadow = mesh.receiveShadow = true; parent.add(mesh); return mesh;
}
function layout(node, x0, y0, x1, y1, out) {
  if (node && node.split && node.parts?.length) {
    const tot = node.parts.reduce((s, p) => s + (p.size || 1), 0);
    let a = node.split === 'rows' ? y0 : x0;
    const span = node.split === 'rows' ? y1 - y0 : x1 - x0;
    for (const p of node.parts) {
      const len = span * (p.size || 1) / tot;
      if (node.split === 'rows') layout(p, x0, a, x1, a + len, out); else layout(p, a, y0, a + len, y1, out);
      a += len;
    }
  } else out.push({ ...(node || { kind: 'panel' }), x0, y0, x1, y1 });
}

// ---------------------------------------------------------------------------
// Build context: everything tappable is registered here
// ---------------------------------------------------------------------------
let SEL = [], LIDS = [];
function register(obj, name, section, mode, extra = {}) {
  obj.userData = { name: `${section} · ${name}`, section, mode, open: 0, target: 0, ...extra };
  SEL.push(obj);
}

// ---------------------------------------------------------------------------
// Drawers, doors and panels
// ---------------------------------------------------------------------------
function addDrawerPull(style, g, cw, ch, PM) {
  switch (style) {
    case 'none': return;
    case 'recessed':
      box(cw * 0.97, 0.45, 0.8, PM, 0, ch / 2 - 0.25, 0.5, 0.15, g);
      box(cw * 0.95, 0.3, 0.3, FIX.black, 0, ch / 2 - 0.62, 0.3, 0.05, g);
      return;
    case 'bar': {
      const len = Math.min(Math.max(cw * 0.35, 3.5), 12), y = ch > 10 ? ch * 0.3 : 0;
      const bar = cyl(0.22, len, PM, g); bar.rotation.z = Math.PI / 2; bar.position.set(0, y, 1.05);
      for (const s of [-1, 1]) { const st = cyl(0.18, 0.9, PM, g); st.rotation.x = Math.PI / 2; st.position.set(s * (len / 2 - 0.5), y, 0.65); }
      return;
    }
    case 'file': {
      const ly = ch * 0.2, lw = 3.4, lh = 2.1;
      box(lw, 0.22, 0.2, PM, 0, ly + lh / 2, 0.35, 0.05, g); box(lw, 0.22, 0.2, PM, 0, ly - lh / 2, 0.35, 0.05, g);
      box(0.22, lh, 0.2, PM, -lw / 2, ly, 0.35, 0.05, g); box(0.22, lh, 0.2, PM, lw / 2, ly, 0.35, 0.05, g);
      box(4.6, 0.38, 0.35, PM, 0, -ch * 0.05, 1.0, 0.1, g);
      for (const s of [-1, 1]) box(0.45, 0.9, 1.0, PM, s * 2.2, -ch * 0.05 + 0.2, 0.6, 0.1, g);
      return;
    }
    case 'knob': { const k = new THREE.Mesh(new THREE.SphereGeometry(0.6, 20, 14), PM); k.position.set(0, 0, 0.8); g.add(k); return; }
    case 'label': // small parts drawer: label card + lip pull along the bottom
      box(cw * 0.6, Math.min(ch * 0.35, 1.6), 0.1, mat('#f4f4f0', 'satin'), 0, ch * 0.12, 0.3, 0, g);
      box(cw * 0.75, Math.min(0.45, ch * 0.15), 0.9, PM, 0, -ch / 2 + 0.4, 0.5, 0.1, g);
      return;
    default: // 'toolbox': chrome bar along the top edge with a black strip under it
      box(cw * 0.9, 0.34, 0.6, PM, 0, ch / 2 - 0.3, 0.45, 0.14, g);
      box(cw * 0.9 - 0.1, Math.min(0.4, ch * 0.16), 0.45, FIX.black, 0, ch / 2 - 0.66, 0.35, 0.06, g);
  }
}
function addDoorPull(style, g, cw, ch, PM, free) {
  const fx = free * (cw / 2 - 1.6);
  switch (style) {
    case 'none': return;
    case 'rod': {
      const rod = cyl(0.3, ch * 0.88, PM, g); rod.position.set(fx, 0, 1.0);
      box(0.5, 3.5, 0.9, PM, fx, 0, 1.2, 0.15, g);
      return;
    }
    case 'knob': { const k = new THREE.Mesh(new THREE.SphereGeometry(0.6, 20, 14), PM); k.position.set(fx, ch / 2 - 4, 0.8); g.add(k); return; }
    default: { // 'bar'
      const len = Math.min(Math.max(ch * 0.22, 4), 10), y = ch / 2 - len / 2 - 2.5;
      const bar = cyl(0.22, len, PM, g); bar.position.set(fx, y, 1.05);
      for (const s of [-1, 1]) { const st = cyl(0.18, 0.9, PM, g); st.rotation.x = Math.PI / 2; st.position.set(fx, y + s * (len / 2 - 0.5), 0.65); }
    }
  }
}

/** One cell of a drawer face. ctx: parent, x, y, zFront, cw, ch, depth, P, sec, counter */
function makeLeaf(L, ctx) {
  const { cw, ch, sec } = ctx; const kind = L.kind || 'drawer';
  const PM = pullMat(L.pullColor || sec.pullColor);
  if (kind === 'panel') { box(cw, ch, 0.5, ctx.P, ctx.x, ctx.y, ctx.zFront - 0.25, 0.1, ctx.parent); return; }
  if (kind === 'door') {
    const s = (L.hinge || 'left') === 'left' ? -1 : 1;
    const pivot = new THREE.Group(); pivot.position.set(ctx.x + s * cw / 2, ctx.y, ctx.zFront - 0.3); ctx.parent.add(pivot);
    const door = new THREE.Group(); door.position.x = -s * cw / 2; pivot.add(door);
    const style = L.panel || sec.doorStyle || 'flat';
    const dm = style === 'pegboard' ? mat(sec.color, 'pegboard', [cw, ch]) : ctx.P;
    box(cw, ch, 0.6, dm, 0, 0, 0, 0.1, door);
    if (style === 'shaker') {
      const r = Math.min(2.6, cw * 0.15);
      for (const sy of [-1, 1]) box(cw, r, 0.3, ctx.P, 0, sy * (ch / 2 - r / 2), 0.4, 0.05, door);
      for (const sx of [-1, 1]) box(r, ch - 2 * r, 0.3, ctx.P, sx * (cw / 2 - r / 2), 0, 0.4, 0.05, door);
    }
    addDoorPull(L.pull || sec.doorPull || 'bar', door, cw, ch, PM, -s);
    ctx.counter.door++;
    const base = (L.open || 0) * Math.PI / 180;
    const name = L.name || (s < 0 ? (ctx.counter.door === 1 ? 'Left door' : `Door ${ctx.counter.door}`) : (ctx.counter.door <= 2 ? 'Right door' : `Door ${ctx.counter.door}`));
    register(pivot, name, ctx.label, 'swing', { sign: s, base, max: Math.max(base, 1.85) });
    pivot.rotation.y = s * base;
    return;
  }
  // drawer
  const dg = new THREE.Group(); dg.position.set(ctx.x, ctx.y, ctx.zFront - 0.25); ctx.parent.add(dg);
  box(cw, ch, 0.5, ctx.P, 0, 0, 0, 0.1, dg);
  const td = Math.max(2, ctx.depth - 1.6);
  box(cw - 0.4, 0.15, td, FIX.tray, 0, -ch / 2 + 0.3, -td / 2 - 0.25, 0, dg);
  for (const s of [-1, 1]) box(0.12, Math.max(0.3, ch - 0.6), td, FIX.tray, s * (cw / 2 - 0.3), 0, -td / 2 - 0.25, 0, dg);
  box(cw - 0.4, Math.max(0.3, ch - 0.6), 0.12, FIX.tray, 0, 0, -td - 0.25, 0, dg);
  addDrawerPull(L.pull || sec.pull || 'toolbox', dg, cw, ch, PM);
  ctx.counter.drawer++;
  register(dg, L.name || `Drawer ${ctx.counter.drawer}`, ctx.label, 'slide', { travel: td * 0.7, z0: dg.position.z });
}

// ---------------------------------------------------------------------------
// Cabinet / chest / pedestal
// ---------------------------------------------------------------------------
function buildBox(sec, spec) {
  const g = new THREE.Group(); g.name = sec.label;
  const color = sec.color || spec.color || '#b3222b', finish = sec.finish || spec.finish || 'textured';
  const { width: w, height: h, depth: d } = sec; const t = 0.35;
  const f = { top: 1.5, bottom: 1.5, sides: 1.2, ...(sec.face || {}) };
  const P = mat(color, finish), IN = mat(darker(color, 0.45), 'satin');
  const sideMat = sec.pegboard ? mat(color, 'pegboard', [d, h]) : P;
  const slanted = sec.sideProfile && sec.sideProfile.frontHeight;
  const fh = slanted ? sec.sideProfile.frontHeight : h;           // height of the front (drawer) face
  const sl = slanted ? (sec.sideProfile.slantDepth || d * 0.4) : 0;

  // shell
  for (const s of [-1, 1]) {
    if (slanted) {
      const side = prism([[-d / 2, 0], [d / 2, 0], [d / 2, fh], [d / 2 - sl, h], [-d / 2, h]], t, sideMat, g);
      side.position.x = s * (w / 2 - t / 2);
    } else box(t, h, d, sideMat, s * (w / 2 - t / 2), h / 2, 0, 0.15, g);
  }
  box(w, t, d, P, 0, t / 2, 0, 0.05, g);
  box(w, h, t, sec.pegboard ? mat(color, 'pegboard', [w, h]) : P, 0, h / 2, -d / 2 + t / 2, 0.05, g);
  const open = sec.openTop || slanted;
  if (!open && !sec.lid) box(w, t, d, P, 0, h - t / 2, 0, 0.15, g);
  if (open) box(w - 2 * t, t, d - 2 * t, IN, 0, slanted ? fh + 0.2 : h - (sec.tillDepth || 3), 0, 0, g);
  // inside darkness behind doors
  box(w - 2 * t - 0.1, fh - 2 * t, 0.1, IN, 0, fh / 2, -d / 2 + t + 0.1, 0, g);

  // front frame
  const zF = d / 2 - t / 2;
  box(w, f.top, t, P, 0, fh - f.top / 2, zF, 0.12, g);
  if (f.bottom > 0) box(w, f.bottom, t, P, 0, f.bottom / 2, zF, 0.12, g);
  const sh = fh - f.top - f.bottom;
  for (const s of [-1, 1]) box(f.sides, sh, t, P, s * (w / 2 - f.sides / 2), f.bottom + sh / 2, zF, 0.1, g);

  // interior shelves (seen through open doors)
  (sec.interiorShelves || []).slice().sort((a, b) => b - a).forEach((fy, i) => {
    const sg = new THREE.Group(); sg.position.set(0, f.bottom + fy * sh, 0); g.add(sg);
    box(w - 2 * t - 0.2, 0.5, d - 2 * t - 0.8, IN, 0, 0, -0.4, 0.05, sg);
    register(sg, `Shelf ${i + 1}`, sec.label, 'glow');
  });

  // drawers / doors / panels
  const faceW = w - 2 * f.sides, fx0 = -w / 2 + f.sides, fyTop = fh - f.top;
  const leaves = []; layout(sec.face?.layout || { kind: 'panel' }, 0, 0, faceW, sh, leaves);
  leaves.sort((a, b) => (a.y0 - b.y0) || (a.x0 - b.x0));
  const counter = { drawer: 0, door: 0 };
  for (const L of leaves) {
    const gap = L.kind === 'door' ? 0.2 : 0.16;
    makeLeaf(L, {
      parent: g, x: fx0 + (L.x0 + L.x1) / 2, y: fyTop - (L.y0 + L.y1) / 2, zFront: d / 2,
      cw: L.x1 - L.x0 - gap, ch: L.y1 - L.y0 - gap, depth: d, P, sec: { ...sec, color }, label: sec.label, counter,
    });
  }

  // hardware
  if (sec.lock) {
    const lk = cyl(0.32, 0.3, FIX.chrome, g); lk.rotation.x = Math.PI / 2; lk.position.set(0, fh - f.top / 2, d / 2 + 0.1);
    box(0.08, 0.4, 0.05, FIX.black, 0, fh - f.top / 2, d / 2 + 0.26, 0, g);
  }
  if (sec.badge) box(3.4, 0.9, 0.12, FIX.steel, w / 2 - f.sides - 3, fh - Math.max(f.top, 1.2) / 2, d / 2 + 0.05, 0.05, g);
  if (sec.topLip && !open) {
    const lm = sec.topMat ? mat(sec.topMat, 'plastic') : P;
    if (sec.topMat) box(w - 0.6, 0.2, d - 0.6, lm, 0, h + 0.1, 0, 0, g);
    box(w, 0.7, 0.25, P, 0, h + 0.35, d / 2 - 0.12, 0.1, g);
    box(w, 0.7, 0.25, P, 0, h + 0.35, -d / 2 + 0.12, 0.1, g);
    for (const s of [-1, 1]) box(0.25, 0.7, d, P, s * (w / 2 - 0.12), h + 0.35, 0, 0.1, g);
  }
  for (const r of sec.sideRails || []) {
    const s = r.side === 'right' ? 1 : -1;
    box(0.9, 1.3, d * 0.96, FIX.black, s * (w / 2 + 0.45), r.y * h, 0, 0.12, g);
  }
  if (sec.pushHandle) {
    const s = sec.pushHandle.side === 'left' ? -1 : 1, off = sec.pushHandle.offset || 2.3;
    const hm = sec.pushHandle.color ? mat(sec.pushHandle.color, 'satin') : P;
    const hy = h - (sec.pushHandle.drop || 1.3);
    const tube = cyl(0.55, d * 0.92, hm, g); tube.rotation.x = Math.PI / 2; tube.position.set(s * (w / 2 + off), hy, 0);
    if (sec.pushHandle.grip) { const gr = cyl(0.72, d * 0.6, FIX.rubber, g); gr.rotation.x = Math.PI / 2; gr.position.set(s * (w / 2 + off), hy, 0); }
    for (const z of [-1, 1]) box(off, 1.0, 1.0, hm, s * (w / 2 + off / 2), hy, z * (d * 0.46 - 0.6), 0.1, g);
  }
  if (sec.frontBumper) box(w * 0.62, 1.0, 0.9, FIX.black, 0, 0.9, d / 2 + 0.45, 0.12, g);
  if (sec.sideHandles) {
    for (const s of [-1, 1]) {
      if (sec.sideHandles === 'recessed') {
        box(0.2, 3.2, 5.5, FIX.black, s * (w / 2 + 0.05), fh * 0.55, 0, 0.3, g);
        box(0.25, 0.6, 4.5, FIX.black, s * (w / 2 + 0.2), fh * 0.55 - 0.9, 0, 0.2, g);
        continue;
      }
      box(0.25, 3.8, 3.2, FIX.chrome, s * (w / 2 + 0.12), h - 5, 0, 0.08, g);
      const hg = new THREE.Group(); hg.position.set(s * (w / 2 + 0.55), h - 5.4, 0); hg.rotation.y = Math.PI / 2; g.add(hg);
      const u = new THREE.Mesh(new THREE.TorusGeometry(1.35, 0.2, 12, 28, Math.PI), FIX.chrome); u.rotation.z = Math.PI; u.castShadow = true; hg.add(u);
      const grip = cyl(0.33, 1.7, FIX.black, hg); grip.rotation.z = Math.PI / 2; grip.position.y = -1.35;
    }
  }
  if (sec.lid) {
    const pivot = new THREE.Group(); pivot.position.set(0, h, -d / 2); g.add(pivot);
    if (slanted) {
      const topLen = d - sl, drop = h - fh, slLen = Math.hypot(sl, drop);
      box(w, 0.35, topLen, P, 0, 0.17, topLen / 2, 0.12, pivot);
      const sp = box(w, 0.35, slLen, P, 0, -drop / 2, topLen + sl / 2, 0.12, pivot);
      sp.rotation.x = Math.atan2(drop, sl);
    } else {
      const L = sec.lid.height || 2.5;
      box(w, 0.3, d, P, 0, L - 0.15, d / 2, 0.12, pivot);
      box(w, L, 0.3, P, 0, L / 2, d - 0.15, 0.1, pivot);
      for (const s of [-1, 1]) box(0.3, L, d, P, s * (w / 2 - 0.15), L / 2, d / 2, 0.1, pivot);
      box(0.9, 0.7, 0.15, FIX.chrome, 0, L * 0.45, d + 0.05, 0.05, pivot);
    }
    const hinge = cyl(0.22, w - 1, FIX.chrome, g); hinge.rotation.z = Math.PI / 2; hinge.position.set(0, h, -d / 2);
    const ang = (sec.lid.angle || 0) * Math.PI / 180;
    pivot.rotation.x = -ang;
    LIDS.push({ pivot, open: ang, target: ang, max: ang || 1.6 });
  }
  return g;
}

// ---------------------------------------------------------------------------
// Diamond-plate truck box
// ---------------------------------------------------------------------------
function buildTruckbox(sec, spec) {
  const g = new THREE.Group(); g.name = sec.label;
  const { width: w, height: h, depth: d } = sec;
  const M = mat(sec.color || '#d9dadc', 'diamond', [0.4, 0.4]);
  const fhh = h * 0.55, sl = d * 0.3;
  prism([[-d / 2, 0], [d / 2, 0], [d / 2, fhh], [d / 2 - sl, h], [-d / 2, h]], w, M, g);
  // lid seam and lock buttons
  box(w + 0.05, 0.15, 0.15, FIX.black, 0, fhh, d / 2 + 0.02, 0, g);
  for (const s of [-1, 1]) {
    const b = cyl(0.55, 0.5, FIX.chrome, g); b.rotation.x = Math.PI / 2; b.position.set(s * (w / 2 - 6), fhh - 1.5, d / 2 + 0.2);
  }
  register(g, 'Truck box', sec.label, 'glow');
  return g;
}

// ---------------------------------------------------------------------------
// Welded cart / bench frame
// ---------------------------------------------------------------------------
function buildFrame(sec, spec) {
  const g = new THREE.Group(); g.name = sec.label;
  const { width: w, height: h, depth: d } = sec; const tb = sec.tube || 2;
  const M = mat(sec.color || spec.color || '#2d3035', sec.finish || 'satin');
  const S = mat(sec.shelfColor || '#8d9096', 'aluminum');
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) box(tb, h, tb, M, sx * (w / 2 - tb / 2), h / 2, sz * (d / 2 - tb / 2), 0.1, g);
  const level = (y) => {
    for (const sz of [-1, 1]) box(w, tb, tb, M, 0, y, sz * (d / 2 - tb / 2), 0.1, g);
    for (const sx of [-1, 1]) box(tb, tb, d, M, sx * (w / 2 - tb / 2), y, 0, 0.1, g);
  };
  level(h - tb / 2);
  if (sec.top) box(w, 0.3, d, S, 0, h + 0.15, 0, 0.05, g);
  (sec.shelves || []).forEach((fy, i, arr) => {
    const y = Math.max(tb / 2, fy * h);
    level(y);
    const sg = new THREE.Group(); sg.position.set(0, y + tb / 2 + 0.1, 0); g.add(sg);
    box(w - tb * 2, 0.2, d - tb * 2, S, 0, 0, 0, 0, sg);
    register(sg, arr.length === 1 ? 'Lower shelf' : `Shelf ${arr.length - i}`, sec.label, 'glow');
  });
  return g;
}

// ---------------------------------------------------------------------------
// Shelving and tote racks
// ---------------------------------------------------------------------------
function buildShelving(sec, spec) {
  const g = new THREE.Group(); g.name = sec.label;
  const { width: w, height: h, depth: d } = sec;
  const cols = sec.columns || 1, wood = sec.material === 'wood';
  const pc = sec.color || spec.color;
  const post = wood ? mat(pc || '#d9b27c', 'wood', [1, 4]) : mat(pc || '#2d3035', 'punched', [1, h / 2.5]);
  const beam = wood ? post : mat(pc || '#2d3035', 'satin');
  const deck = sec.deck || (wood ? 'board' : 'steel');
  const board = wood ? mat(sec.shelfColor || sec.color || '#d9b27c', 'wood', [2, 1])
    : deck === 'wire' ? mat(sec.shelfColor || '#2a2b2e', 'wire', [w / 2, d / 4])
    : deck === 'board' ? mat(sec.shelfColor || '#d8ccb4', 'satin')
    : mat(sec.shelfColor || sec.color || '#2d3035', 'satin');
  const pw = wood ? 1.5 : 1.4, pd = wood ? 3.5 : 1.4;
  const bayW = (w - pw) / cols;
  for (let c = 0; c <= cols; c++) {
    const x = -w / 2 + pw / 2 + c * bayW;
    for (const sz of [-1, 1]) box(pw, h, pd, post, x, h / 2, sz * (d / 2 - pd / 2), 0.05, g);
  }
  // top frame (built wood racks)
  if (wood) for (const sz of [-1, 1]) box(w, 3.5, pw, post, 0, h - 1.75, sz * (d / 2 - pw / 2), 0.05, g);
  if (sec.base) box(w, 3.5, d, post, 0, 1.75, 0, 0.05, g);
  let levels = (sec.shelves || [0, 0.5, 1]).map(f => Math.max(sec.base ? 3.5 : 0.8, f * h)).sort((a, b) => a - b);
  // the base itself is a level when things sit on it
  if (sec.base && levels[0] > 6) levels = [3.5, ...levels];
  const maxBinShelf = Math.max(-1, ...(sec.bins || []).map(b => b.shelf ?? 0));
  if (maxBinShelf >= levels.length && !(sec.base && levels[0] <= 6)) levels = [sec.base ? 3.5 : 0.8, ...levels];
  const style = sec.style || 'boards';
  const binsHere = new Set((sec.bins || []).map(b => `${b.column}|${b.shelf}`));
  levels.forEach((y, li) => {
    if (style === 'ledge') {
      for (let c = 0; c <= cols; c++) {
        const x = -w / 2 + pw / 2 + c * bayW;
        for (const s of [-1, 1]) if ((c > 0 || s > 0) && (c < cols || s < 0)) box(1.5, 3.5, d - 1, post, x + s * (pw / 2 + 0.75), y - 1.75, 0, 0.05, g);
      }
      return;
    }
    const sg = new THREE.Group(); sg.position.set(0, y, 0); g.add(sg);
    box(w - 0.4, deck === 'wire' ? 0.2 : 0.75, d - 0.4, board, 0, 0, 0, deck === 'wire' ? 0 : 0.08, sg);
    if (!wood) for (const sz of [-1, 1]) box(w, 1.8, 1.0, beam, 0, -0.5, sz * (d / 2 - 0.5), 0.1, sg);
    if (![...binsHere].some(k => k.endsWith('|' + li))) register(sg, `Shelf ${levels.length - li}`, sec.label, 'glow');
  });
  // bins / totes
  let n = 0;
  for (const b of sec.bins || []) {
    const colsFor = b.column === 'all' || b.column == null ? [...Array(cols).keys()] : [b.column];
    for (const c of colsFor) {
      const li = b.shelf ?? 0;
      if (li < 0 || li >= levels.length) continue;   // bad index from the AI: skip rather than break the model
      const y0 = levels[li] + (style === 'ledge' ? 0 : 0.4);
      const next = levels[li + 1] ?? h - 3.5;
      const bh = b.height || Math.max(4, Math.min(16, next - y0 - 1.2));
      const count = b.count || 1, bw = (bayW - pw) / count - 0.8;
      const body = mat(b.color || '#1c1d20', 'plastic'), lid = mat(b.lidColor || b.color || '#1c1d20', 'plastic');
      for (let i = 0; i < count; i++) {
        const x = -w / 2 + pw + c * bayW + (i + 0.5) * (bayW - pw) / count;
        const tg = new THREE.Group(); tg.position.set(x, y0, 0); g.add(tg);
        box(bw * 0.94, bh - 1, d - 3, body, 0, (bh - 1) / 2, 0, 0.6, tg);
        box(bw, 1.2, d - 2.4, lid, 0, bh - 0.6, 0, 0.3, tg);
        if (b.label !== false) box(Math.min(5, bw * 0.4), 2.2, 0.1, mat('#f2f2ee', 'satin'), 0, bh * 0.5, (d - 3) / 2 + 0.05, 0, tg);
        n++;
        register(tg, b.name || `Bay ${c + 1}, level ${li + 1}${count > 1 ? '-' + (i + 1) : ''}`, sec.label, 'slide', { travel: d * 0.55, z0: 0 });
      }
    }
  }
  return g;
}

// ---------------------------------------------------------------------------
// Louvered panel rack with hanging bins
// ---------------------------------------------------------------------------
function buildLouvered(sec, spec) {
  const g = new THREE.Group(); g.name = sec.label;
  const { width: w, height: h, depth: d } = sec;
  const M = mat(sec.color || spec.color || '#202124', 'satin'), PNL = mat(sec.panelColor || '#2a2b2e', 'satin');
  for (const s of [-1, 1]) box(1.5, h, d, M, s * (w / 2 - 0.75), h / 2, 0, 0.1, g);
  box(w, 1.5, d, M, 0, 0.75, 0, 0.1, g);
  box(w, 1.5, 1.5, M, 0, h - 0.75, 0, 0.1, g);
  const ph = h - 6, py = 3 + ph / 2;
  box(w - 3, ph, 0.3, PNL, 0, py, 0, 0, g);
  for (let y = 4; y < h - 3; y += 3) box(w - 3, 0.35, 0.9, PNL, 0, y, 0.45, 0.1, g);
  (sec.rows || []).forEach((r, ri) => {
    const n = r.count || 6, bw = (w - 4) / n - 0.4, bh = r.height || 4, bd = r.depth || 7;
    const bm = mat(r.color || '#e8501c', 'plastic');
    for (let i = 0; i < n; i++) {
      const bg = new THREE.Group(); bg.position.set(-w / 2 + 2 + (i + 0.5) * (w - 4) / n, 3 + r.y * ph, 0.6); g.add(bg);
      box(bw, bh, bd, bm, 0, bh / 2, bd / 2, 0.3, bg);
      box(bw, bh * 0.35, 0.3, bm, 0, bh * 0.8, bd + 0.1, 0.1, bg);
      register(bg, `Row ${ri + 1} bin ${i + 1}`, sec.label, 'slide', { travel: 3, z0: 0.6 });
    }
  });
  return g;
}

// ---------------------------------------------------------------------------
// Equipment / machines: a plain block with a name on the front
// ---------------------------------------------------------------------------
function buildBlock(sec, spec) {
  const g = new THREE.Group(); g.name = sec.label;
  const { width: w, height: h, depth: d } = sec;
  box(w, h, d, mat(sec.color || '#9a9da2', sec.finish || 'satin'), 0, h / 2, 0, Math.min(1, w / 8), g);
  if (sec.label) {
    const c = document.createElement('canvas'); c.width = 512; c.height = 128;
    const x = c.getContext('2d'); x.font = 'bold 64px system-ui, sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle';
    const dark = new THREE.Color(sec.color || '#9a9da2').getHSL({}).l > 0.5;
    x.fillStyle = dark ? '#222' : '#f4f4f4'; x.fillText(sec.label, 256, 64);
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
    const lw = Math.min(w * 0.9, 24), plane = new THREE.Mesh(new THREE.PlaneGeometry(lw, lw / 4), new THREE.MeshBasicMaterial({ map: t, transparent: true }));
    plane.position.set(0, Math.min(h * 0.75, h - lw / 8 - 1), d / 2 + 0.05); g.add(plane);
  }
  return g;
}

// ---------------------------------------------------------------------------
// Desk: top + drawer pedestals + optional center drawer
// ---------------------------------------------------------------------------
function buildDesk(sec, spec) {
  const g = new THREE.Group(); g.name = sec.label;
  const { width: w, height: h, depth: d } = sec;
  const top = { thickness: 1.25, color: '#4a3a2c', finish: 'wood', overhang: 1, ...(sec.top || {}) };
  const color = sec.color || spec.color || '#202124', finish = sec.finish || spec.finish || 'satin';
  const bodyH = h - top.thickness;
  box(w + 2 * top.overhang, top.thickness, d + top.overhang, mat(top.color, top.finish, [3, 1]), 0, h - top.thickness / 2, top.overhang / 2, 0.25, g);
  let leftEdge = -w / 2, rightEdge = w / 2;
  for (const p of sec.pedestals || []) {
    const ps = { type: 'cabinet', label: `${sec.label} ${p.side}`, width: p.width, height: bodyH, depth: d - 1, color, finish,
      pull: p.pull || sec.pull || 'bar', pullColor: p.pullColor || sec.pullColor, face: { top: 0.6, bottom: p.kick ?? 2.5, sides: 0.6, layout: p.layout } };
    const pg = buildBox(ps, spec);
    const x = p.side === 'left' ? -w / 2 + p.width / 2 : w / 2 - p.width / 2;
    pg.position.set(x, 0, -0.5); g.add(pg);
    if (p.side === 'left') leftEdge = -w / 2 + p.width; else rightEdge = w / 2 - p.width;
  }
  if (sec.centerDrawer) {
    const ch = sec.centerDrawer.height || 3, cw = rightEdge - leftEdge - 1;
    box(cw + 1, 0.4, d - 2, mat(color, finish), (leftEdge + rightEdge) / 2, bodyH - ch - 0.3, -0.5, 0, g);
    makeLeaf({ kind: 'drawer', name: sec.centerDrawer.name || 'Center drawer', pull: sec.centerDrawer.pull || 'none' }, {
      parent: g, x: (leftEdge + rightEdge) / 2, y: bodyH - ch / 2 - 0.1, zFront: d / 2, cw, ch: ch - 0.2, depth: d - 1,
      P: mat(color, finish), sec: { ...sec, color }, label: sec.label, counter: { drawer: 0, door: 0 },
    });
  }
  if (sec.legs === 'posts') {
    const lm = mat(sec.legColor || '#a9adb2', 'aluminum');
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) box(1.5, bodyH, 1.5, lm, sx * (w / 2 + 0.2), bodyH / 2, sz * (d / 2 - 0.75), 0.1, g);
  }
  if (sec.modesty !== false) box(rightEdge - leftEdge, bodyH * 0.45, 0.4, mat(color, finish), (leftEdge + rightEdge) / 2, bodyH * 0.6, -d / 2 + 1, 0.05, g);
  return g;
}

// ---------------------------------------------------------------------------
// Casters and toe kicks
// ---------------------------------------------------------------------------
function buildCasters(sec, parent) {
  const D = sec.casters.diameter || 4, Hc = D + 1.2;
  const w = sec.width, d = sec.depth;
  const wheelM = sec.casters.color ? mat(sec.casters.color, 'plastic') : FIX.rubber;
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    const c = new THREE.Group(); c.position.set(sx * (w / 2 - 2.6), 0, sz * (d / 2 - 2.6)); parent.add(c);
    box(3, 0.3, 3, FIX.steel, 0, Hc - 0.15, 0, 0.05, c);
    box(1.0, 0.5, 1.0, FIX.steel, 0, Hc - 0.5, 0, 0.05, c);
    for (const s of [-1, 1]) box(0.18, D * 0.72, 1.6, FIX.steel, s * 0.95, Hc - 0.6 - D * 0.33, 0, 0.05, c);
    const wheel = cyl(D / 2, 1.4, wheelM, c, 32); wheel.rotation.z = Math.PI / 2; wheel.position.y = D / 2;
    const hub = cyl(D * 0.2, 1.5, FIX.steel, c); hub.rotation.z = Math.PI / 2; hub.position.y = D / 2;
  }
  return Hc;
}

// ---------------------------------------------------------------------------
// Whole model
// ---------------------------------------------------------------------------
const BUILDERS = { cabinet: buildBox, chest: buildBox, truckbox: buildTruckbox, frame: buildFrame, shelving: buildShelving, desk: buildDesk, louvered: buildLouvered, block: buildBlock };

export function buildModel(spec) {
  SEL = []; LIDS = [];
  const model = new THREE.Group(); model.name = spec.name || 'storage';
  const units = spec.units || [{ sections: spec.sections || [] }];
  const built = [];
  for (const u of units) {
    const ug = new THREE.Group(); model.add(ug);
    let y = 0, prev = null, uw = 0, ud = 0;
    for (const sec of u.sections) {
      sec.label = sec.label || sec.type;
      const g = (BUILDERS[sec.type] || buildBox)(sec, spec);
      let z = 0;
      if (prev && sec.setBack != null) z = prev.z + prev.sec.depth / 2 - sec.setBack - sec.depth / 2;
      let base = y;
      if (sec.casters) { const cg = new THREE.Group(); cg.position.set(sec.offsetX || 0, y, z); ug.add(cg); base += buildCasters(sec, cg); }
      else if (sec.toeKick) {
        box(sec.width - 1, sec.toeKick, sec.depth - 4, mat('#1d1d1f', 'satin'), sec.offsetX || 0, y + sec.toeKick / 2, z - 1.5, 0, ug);
        base += sec.toeKick;
      } else if (sec.feet) base += sec.feet;
      g.position.set(sec.offsetX || 0, base, z); ug.add(g);
      y = base + sec.height;
      prev = { sec, z };
      uw = Math.max(uw, sec.width);
      ud = Math.max(ud, sec.depth);
    }
    built.push({ ug, u, uw, ud, top: y });
  }
  // place units left to right, backs against the same wall
  const maxD = Math.max(...built.map(b => b.ud));
  let cursor = 0;
  for (const b of built) {
    cursor += b.u.gap || 0;
    b.ug.position.set(cursor + b.uw / 2, 0, (b.ud - maxD) / 2 + (b.u.z || 0));
    cursor += b.uw;
  }
  for (const b of built) b.ug.position.x -= cursor / 2;
  if (spec.countertop) {
    const c = { thickness: 1.25, overhang: 1, color: '#4b3a2b', finish: 'wood', ...spec.countertop };
    const top = Math.max(...built.map(b => b.top));
    const ct = box(cursor + 2 * c.overhang, c.thickness, maxD + c.overhang, mat(c.color, c.finish, [3, 1]), 0, top + c.thickness / 2, c.overhang / 2, 0.4, model);
    register(ct, 'Countertop', 'Top', 'glow');
  }
  // give every tappable part its own materials so it can glow on its own
  for (const s of SEL) {
    s.userData.mats = [];
    s.traverse(o => { if (o.isMesh && o.material.emissive) { o.material = o.material.clone(); s.userData.mats.push(o.material); } });
  }
  return { model, selectable: SEL, lids: LIDS };
}

/** Overall size of a model in inches: [width, depth, height]. */
export function modelSize(spec) {
  const { model } = buildModel(structuredClone(spec));
  const s = new THREE.Box3().setFromObject(model).getSize(new THREE.Vector3());
  model.traverse(o => o.geometry?.dispose());
  return [s.x, s.z, s.y].map(v => Math.round(v));
}

// ---------------------------------------------------------------------------
// Shop scene: a room with every piece of furniture placed on the floor plan
// ---------------------------------------------------------------------------
export function buildScene(scene, specs) {
  const root = new THREE.Group(); root.name = scene.room?.name || 'Shop';
  const r = { width: 360, depth: 300, height: 144, floorColor: '#b9b7b1', wallColor: '#eceeef', ...(scene.room || {}) };
  const floorMat = new THREE.MeshStandardMaterial({ color: r.floorColor, roughness: 0.85, bumpMap: NOISE, bumpScale: 0.3 });
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(r.width, r.depth), floorMat);
  floor.rotation.x = -Math.PI / 2; floor.position.set(r.width / 2, 0, r.depth / 2); floor.receiveShadow = true; root.add(floor);
  const wallMat = new THREE.MeshStandardMaterial({ color: r.wallColor, roughness: 0.9 });
  const wall = (w, x, z, ry) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, r.height), wallMat);
    m.position.set(x, r.height / 2, z); m.rotation.y = ry; m.receiveShadow = true; root.add(m);
  };
  wall(r.width, r.width / 2, 0, 0);                  // back wall, faces the room
  wall(r.depth, 0, r.depth / 2, Math.PI / 2);         // left wall
  wall(r.depth, r.width, r.depth / 2, -Math.PI / 2);  // right wall
  const placed = [];
  const place = (p, spec, id) => {
    if (!spec) return;
    const st = buildModel(structuredClone(spec));
    const g = new THREE.Group(); g.add(st.model);
    g.position.set(p.x, 0, p.z); g.rotation.y = (p.rotation || 0) * Math.PI / 180;
    root.add(g);
    placed.push({ id, src: p, name: spec.name || id, where: p.where || '', group: g, selectable: st.selectable, lids: st.lids, extra: id.startsWith('extra') });
  };
  const over = scene.specOverrides || {};
  for (const p of scene.items || []) place(p, over[p.item] || specs[p.item], p.item);
  (scene.extras || []).forEach((e, i) => place(e, e.spec, `extra-${i + 1}`));
  separate(placed, r);
  return { root, placed, room: r };
}

/** Pushes apart any pieces whose footprints overlap and keeps every piece inside the walls. */
function separate(placed, r, gap = 1) {
  const box = p => new THREE.Box3().setFromObject(p.group);
  for (let it = 0; it < 40; it++) {
    let moved = false;
    for (let i = 0; i < placed.length; i++) for (let j = i + 1; j < placed.length; j++) {
      const a = box(placed[i]), b = box(placed[j]);
      const ox = Math.min(a.max.x, b.max.x) - Math.max(a.min.x, b.min.x) + gap;
      const oz = Math.min(a.max.z, b.max.z) - Math.max(a.min.z, b.min.z) + gap;
      if (ox <= gap + 0.5 || oz <= gap + 0.5) continue;
      const ca = a.getCenter(new THREE.Vector3()), cb = b.getCenter(new THREE.Vector3());
      if (ox < oz) { const s = Math.sign(ca.x - cb.x) || 1; placed[i].group.position.x += s * ox / 2; placed[j].group.position.x -= s * ox / 2; }
      else { const s = Math.sign(ca.z - cb.z) || 1; placed[i].group.position.z += s * oz / 2; placed[j].group.position.z -= s * oz / 2; }
      placed[i].nudged = placed[j].nudged = true; moved = true;
    }
    for (const p of placed) {
      const b = box(p);
      if (b.min.x < 0) p.group.position.x -= b.min.x; else if (b.max.x > r.width) p.group.position.x -= b.max.x - r.width;
      if (b.min.z < 0) p.group.position.z -= b.min.z; else if (b.max.z > r.depth) p.group.position.z -= b.max.z - r.depth;
    }
    if (!moved) break;
  }
}

/** Per-frame animation: drawers slide, doors swing, lids rotate, the selected part glows. */
export function animate(state, selected, t) {
  for (const s of state.selectable) {
    const u = s.userData; u.open += (u.target - u.open) * 0.12;
    if (u.mode === 'slide') s.position.z = u.z0 + u.open * u.travel;
    if (u.mode === 'swing') s.rotation.y = u.sign * (u.base + u.open * (u.max - u.base));
    const k = s === selected ? 0.25 + 0.2 * Math.sin(t * 5) : 0;
    for (const m of u.mats) m.emissive.setRGB(0.95 * k, 0.55 * k, 0.05 * k);
  }
  for (const l of state.lids) { l.open += (l.target - l.open) * 0.1; l.pivot.rotation.x = -l.open; }
}
