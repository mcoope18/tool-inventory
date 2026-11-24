// Tools: photo â†’ cut-out â†’ traced outline â†’ extruded 3D piece with the photo on its faces,
// plus the carousel that shows a drawer's tools hovering over it.
import * as THREE from 'three';
import { buildTool } from 'toolmodels';

// ---------------------------------------------------------------------------
// 1. Cut the tool out of its photo
// ---------------------------------------------------------------------------
/**
 * Returns { canvas (cropped RGBA, background transparent), mask (cropped, 1 = tool), w, h, color }.
 * Uses the image's own transparency when it has some (phone "lift subject", ML Kit cutouts);
 * otherwise removes a plain background by flood-filling from the photo's edges.
 */
export function cutout(img, maxSide = 512) {
  const iw = img.naturalWidth || img.width, ih = img.naturalHeight || img.height;
  const k = Math.min(1, maxSide / Math.max(iw, ih));
  const w = Math.max(8, Math.round(iw * k)), h = Math.max(8, Math.round(ih * k));
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const g = c.getContext('2d', { willReadFrequently: true }); g.drawImage(img, 0, 0, w, h);
  const px = g.getImageData(0, 0, w, h).data, N = w * h;
  let fg = new Uint8Array(N);

  let clear = 0; for (let i = 0; i < N; i++) if (px[i * 4 + 3] < 128) clear++;
  if (clear > N * 0.02) {
    for (let i = 0; i < N; i++) fg[i] = px[i * 4 + 3] >= 128 ? 1 : 0;
  } else {
    const border = [];
    for (let x = 0; x < w; x++) border.push(x, (h - 1) * w + x);
    for (let y = 1; y < h - 1; y++) border.push(y * w, y * w + w - 1);
    let r = 0, gg = 0, b = 0;
    for (const i of border) { r += px[i * 4]; gg += px[i * 4 + 1]; b += px[i * 4 + 2]; }
    r /= border.length; gg /= border.length; b /= border.length;
    const dist = i => Math.hypot(px[i * 4] - r, px[i * 4 + 1] - gg, px[i * 4 + 2] - b);
    let spread = 0; for (const i of border) spread += dist(i); spread /= border.length;
    const tol = Math.max(28, Math.min(75, spread * 2.5 + 22));
    const bg = new Uint8Array(N), q = new Int32Array(N); let qh = 0, qt = 0;
    for (const i of border) if (!bg[i] && dist(i) < tol) { bg[i] = 1; q[qt++] = i; }
    while (qh < qt) {
      const i = q[qh++], x = i % w, y = (i / w) | 0;
      for (const j of [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1])
        if (j >= 0 && !bg[j] && dist(j) < tol) { bg[j] = 1; q[qt++] = j; }
    }
    for (let i = 0; i < N; i++) fg[i] = bg[i] ? 0 : 1;
    // holes: enclosed patches of background colour (a wrench's ring end, a hammer's eye)
    const seen = new Uint8Array(N);
    for (let s = 0; s < N; s++) {
      if (!fg[s] || seen[s] || dist(s) >= tol * 0.7) continue;
      const comp = [s]; seen[s] = 1;
      for (let t = 0; t < comp.length; t++) {
        const i = comp[t], x = i % w, y = (i / w) | 0;
        for (const j of [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1])
          if (j >= 0 && fg[j] && !seen[j] && dist(j) < tol * 0.7) { seen[j] = 1; comp.push(j); }
      }
      if (comp.length > N * 0.002) for (const i of comp) fg[i] = 0;
    }
  }
  fg = largestBlob(fg, w, h);
  let x0 = w, y0 = h, x1 = -1, y1 = -1, area = 0;
  for (let i = 0; i < N; i++) if (fg[i]) { const x = i % w, y = (i / w) | 0; x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); area++; }
  if (area < 50) throw new Error('Could not find the tool in that photo. Try a plain background or a cut-out PNG.');
  const bw = x1 - x0 + 1, bh = y1 - y0 + 1;
  const out = document.createElement('canvas'); out.width = bw; out.height = bh;
  const og = out.getContext('2d'), od = og.createImageData(bw, bh);
  const mask = new Uint8Array(bw * bh);
  let cr = 0, cg = 0, cb = 0;
  for (let y = 0; y < bh; y++) for (let x = 0; x < bw; x++) {
    const si = (y + y0) * w + (x + x0), di = y * bw + x;
    od.data[di * 4] = px[si * 4]; od.data[di * 4 + 1] = px[si * 4 + 1]; od.data[di * 4 + 2] = px[si * 4 + 2];
    od.data[di * 4 + 3] = fg[si] ? 255 : 0; mask[di] = fg[si];
    if (fg[si]) { cr += px[si * 4]; cg += px[si * 4 + 1]; cb += px[si * 4 + 2]; }
  }
  og.putImageData(od, 0, 0);
  const color = '#' + new THREE.Color(cr / area / 255, cg / area / 255, cb / area / 255).getHexString();
  return { canvas: out, mask, w: bw, h: bh, color };
}

function largestBlob(m, w, h) {
  const N = w * h, lab = new Int32Array(N); let best = 0, bestN = 0, id = 0;
  for (let s = 0; s < N; s++) {
    if (!m[s] || lab[s]) continue;
    id++; const comp = [s]; lab[s] = id;
    for (let t = 0; t < comp.length; t++) {
      const i = comp[t], x = i % w, y = (i / w) | 0;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const nx = x + dx, ny = y + dy; if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        const j = ny * w + nx; if (m[j] && !lab[j]) { lab[j] = id; comp.push(j); }
      }
    }
    if (comp.length > bestN) { bestN = comp.length; best = id; }
  }
  const out = new Uint8Array(N); for (let i = 0; i < N; i++) out[i] = lab[i] === best ? 1 : 0; return out;
}

// ---------------------------------------------------------------------------
// 1b. Many tools in one photo (an open drawer, or tools laid out on the floor)
// ---------------------------------------------------------------------------
/** Draws the photo onto a working canvas (long side â‰¤ maxSide). */
export function photoCanvas(img, maxSide = 1600) {
  const iw = img.naturalWidth || img.width, ih = img.naturalHeight || img.height, k = Math.min(1, maxSide / Math.max(iw, ih));
  const c = document.createElement('canvas'); c.width = Math.round(iw * k); c.height = Math.round(ih * k);
  c.getContext('2d').drawImage(img, 0, 0, c.width, c.height); return c;
}

/** The surface the tools lie on (drawer mat, floor): the most common colour in the photo. */
export function photoBackground(src) {
  const px = src.getContext('2d', { willReadFrequently: true }).getImageData(0, 0, src.width, src.height).data;
  const bins = new Map(), q = 20;
  for (let i = 0; i < px.length; i += 4 * 3) {
    const k = ((px[i] / q) | 0) * 10000 + ((px[i + 1] / q) | 0) * 100 + ((px[i + 2] / q) | 0);
    const b = bins.get(k) || [0, 0, 0, 0]; b[0]++; b[1] += px[i]; b[2] += px[i + 1]; b[3] += px[i + 2]; bins.set(k, b);
  }
  let best = null; for (const b of bins.values()) if (!best || b[0] > best[0]) best = b;
  return [best[1] / best[0], best[2] / best[0], best[3] / best[0]];
}

/**
 * Cuts one detected tool out of a many-tool photo. det = { ends: [[x,y],[x,y]] (0..1), width (fraction of photo width) }.
 * The tool is turned so it lies along x, trimmed against the background around it, and returned in the same
 * shape as cutout(): { canvas, mask, w, h, color }.
 */
export function cutDetection(src, det, surface) {
  const W = src.width, H = src.height;
  const a = [det.ends[0][0] * W, det.ends[0][1] * H], b = [det.ends[1][0] * W, det.ends[1][1] * H];
  const len0 = Math.max(10, Math.hypot(b[0] - a[0], b[1] - a[1])), wid0 = Math.max(6, (det.width || 0.04) * W);
  const s = Math.min(1, 640 / (len0 + wid0));
  const len = len0 * s, wid = wid0 * s, pad = Math.round(wid * 0.6 + 4);
  const cw = Math.ceil(len + 2 * pad), ch = Math.ceil(wid * 1.9 + 2 * pad), mid = ch / 2;
  const c = document.createElement('canvas'); c.width = cw; c.height = ch;
  const g = c.getContext('2d', { willReadFrequently: true });
  g.translate(pad, mid); g.rotate(-Math.atan2(b[1] - a[1], b[0] - a[0])); g.scale(s, s); g.translate(-a[0], -a[1]);
  g.drawImage(src, 0, 0);
  const px = g.getImageData(0, 0, cw, ch).data;
  // background colour: median of the band outside the tool's strip
  const rs = [], gs = [], bs = [];
  for (let y = 0; y < ch; y += 2) for (let x = 0; x < cw; x += 2) {
    if (Math.abs(y - mid) < wid * 0.85) continue;
    const i = (y * cw + x) * 4; if (px[i + 3] < 200) continue;
    rs.push(px[i]); gs.push(px[i + 1]); bs.push(px[i + 2]);
  }
  const med = v => { v.sort((p, q) => p - q); return v.length ? v[v.length >> 1] : 60; };
  const bg = surface || [med(rs), med(gs), med(bs)];
  const half = wid * 0.55, x0 = Math.max(0, Math.floor(pad - len * 0.06)), x1 = Math.min(cw - 1, Math.ceil(pad + len * 1.06));
  const mask = new Uint8Array(cw * ch);
  // per column: span between the outermost pixels that differ from the background (keeps dark handles joined)
  let prev = [mid - half * 0.35, mid + half * 0.35], found = 0, capsule = 0;
  for (let x = x0; x <= x1; x++) {
    let lo = -1, hi = -1;
    for (let y = Math.max(0, Math.floor(mid - half)); y <= Math.min(ch - 1, Math.ceil(mid + half)); y++) {
      const i = (y * cw + x) * 4; capsule++;
      if (px[i + 3] > 200 && Math.hypot(px[i] - bg[0], px[i + 1] - bg[1], px[i + 2] - bg[2]) > 42) { if (lo < 0) lo = y; hi = y; found++; }
    }
    if (lo >= 0 && hi - lo >= 1) prev = [lo, hi];
    else if (x < pad || x > pad + len) continue;   // past the tips: nothing there
    for (let y = Math.floor(prev[0]); y <= Math.ceil(prev[1]); y++) mask[y * cw + x] = 1;
  }
  if (found < capsule * 0.12) {   // too little contrast (black tool on a black mat): use the strip itself
    mask.fill(0);
    for (let x = pad; x <= pad + len; x++) for (let y = Math.floor(mid - half * 0.8); y <= Math.ceil(mid + half * 0.8); y++) mask[y * cw + x] = 1;
  }
  // crop to the mask
  let bx0 = cw, by0 = ch, bx1 = -1, by1 = -1;
  for (let y = 0; y < ch; y++) for (let x = 0; x < cw; x++) if (mask[y * cw + x]) { bx0 = Math.min(bx0, x); bx1 = Math.max(bx1, x); by0 = Math.min(by0, y); by1 = Math.max(by1, y); }
  const w = bx1 - bx0 + 1, h = by1 - by0 + 1;
  const out = document.createElement('canvas'); out.width = w; out.height = h;
  const og = out.getContext('2d'), od = og.createImageData(w, h), m2 = new Uint8Array(w * h);
  let cr = 0, cg = 0, cb = 0, n = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const si = (y + by0) * cw + (x + bx0), di = y * w + x;
    od.data[di * 4] = px[si * 4]; od.data[di * 4 + 1] = px[si * 4 + 1]; od.data[di * 4 + 2] = px[si * 4 + 2];
    od.data[di * 4 + 3] = mask[si] ? 255 : 0; m2[di] = mask[si];
    if (mask[si]) { cr += px[si * 4]; cg += px[si * 4 + 1]; cb += px[si * 4 + 2]; n++; }
  }
  og.putImageData(od, 0, 0);
  return { canvas: out, mask: m2, w, h, color: '#' + new THREE.Color(cr / n / 255, cg / n / 255, cb / n / 255).getHexString() };
}

/** The photo with every detection drawn on it, numbered â€” for the review screen. */
export function drawDetections(src, dets, highlight = -1) {
  const c = document.createElement('canvas'); c.width = src.width; c.height = src.height;
  const g = c.getContext('2d'); g.drawImage(src, 0, 0);
  const W = src.width, H = src.height;
  dets.forEach((d, i) => {
    const [a, b] = d.ends.map(([x, y]) => [x * W, y * H]), wid = (d.width || 0.04) * W;
    const ang = Math.atan2(b[1] - a[1], b[0] - a[0]), len = Math.hypot(b[0] - a[0], b[1] - a[1]);
    g.save(); g.translate(a[0], a[1]); g.rotate(ang);
    g.lineWidth = i === highlight ? 6 : 3;
    g.strokeStyle = d.skip ? 'rgba(160,160,160,.7)' : i === highlight ? '#ffd54f' : d.visible === 'partial' ? '#ff8a65' : '#f2a516';
    g.strokeRect(0, -wid / 2, len, wid);
    g.restore();
    const lx = (a[0] + b[0]) / 2, ly = (a[1] + b[1]) / 2;
    g.fillStyle = 'rgba(0,0,0,.75)'; g.beginPath(); g.arc(lx, ly, 17, 0, Math.PI * 2); g.fill();
    g.fillStyle = '#fff'; g.font = 'bold 18px system-ui'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText(i + 1, lx, ly + 1);
  });
  return c;
}

// ---------------------------------------------------------------------------
// 2. Trace the outline (Moore-neighbour contour), then simplify it
// ---------------------------------------------------------------------------
const DX = [1, 1, 0, -1, -1, -1, 0, 1], DY = [0, 1, 1, 1, 0, -1, -1, -1];
export function traceOutline(mask, w, h) {
  const W = w + 2, H = h + 2, m = new Uint8Array(W * H);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) m[(y + 1) * W + x + 1] = mask[y * w + x];
  let s = -1; for (let i = 0; i < m.length; i++) if (m[i]) { s = i; break; }
  if (s < 0) return [];
  const sx = s % W, sy = (s / W) | 0; let x = sx, y = sy, back = 4;
  const pts = [[x, y]];
  for (let guard = W * H * 4; guard > 0; guard--) {
    let moved = false;
    for (let k = 1; k <= 8; k++) {
      const d = (back + k) % 8, nx = x + DX[d], ny = y + DY[d];
      if (m[ny * W + nx]) {
        const pd = (back + k - 1) % 8, bx = x + DX[pd], by = y + DY[pd];
        x = nx; y = ny;
        let nb = -1; for (let i = 0; i < 8; i++) if (DX[i] === bx - x && DY[i] === by - y) nb = i;
        back = nb >= 0 ? nb : (d + 4) % 8;
        moved = true; break;
      }
    }
    if (!moved || (x === sx && y === sy)) break;
    pts.push([x, y]);
  }
  return simplify(pts.map(([px, py]) => [px - 1, py - 1]), 1.2);
}
function simplify(pts, eps) {
  if (pts.length < 4) return pts;
  const keep = new Uint8Array(pts.length); keep[0] = keep[pts.length - 1] = 1;
  const stack = [[0, pts.length - 1]];
  while (stack.length) {
    const [a, b] = stack.pop(); let dmax = 0, idx = -1;
    const [ax, ay] = pts[a], [bx, by] = pts[b], L = Math.hypot(bx - ax, by - ay) || 1;
    for (let i = a + 1; i < b; i++) {
      const d = Math.abs((bx - ax) * (ay - pts[i][1]) - (ax - pts[i][0]) * (by - ay)) / L;
      if (d > dmax) { dmax = d; idx = i; }
    }
    if (dmax > eps) { keep[idx] = 1; stack.push([a, idx], [idx, b]); }
  }
  return pts.filter((_, i) => keep[i]);
}

// ---------------------------------------------------------------------------
// 3. A saved tool record, and its 3D piece
// ---------------------------------------------------------------------------
/** Everything needed to rebuild the tool later (stored with the inventory item). */
export function makeToolRecord(cut, info) {
  const outline = traceOutline(cut.mask, cut.w, cut.h).map(([x, y]) => [+(x / cut.w).toFixed(4), +(y / cut.h).toFixed(4)]);
  return {
    id: 't' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
    name: info.name || 'Tool', lengthIn: +info.lengthIn || 8, thicknessIn: +info.thicknessIn || 0.6,
    aspect: cut.w / cut.h, color: cut.color, outline, img: cut.canvas.toDataURL('image/webp', 0.88),
  };
}

const texCache = new Map();
export function toolMesh(tool) {
  const L = tool.lengthIn, Wi = tool.aspect >= 1 ? L : L * tool.aspect, Hi = tool.aspect >= 1 ? L / tool.aspect : L;
  const shape = new THREE.Shape(tool.outline.map(([u, v]) => new THREE.Vector2((u - 0.5) * Wi, (0.5 - v) * Hi)));
  const t = tool.thicknessIn;
  const geo = new THREE.ExtrudeGeometry(shape, { depth: t, bevelEnabled: false, curveSegments: 1 });
  geo.translate(0, 0, -t / 2);
  let tex = texCache.get(tool.img);
  if (!tex) { tex = new THREE.TextureLoader().load(tool.img); tex.colorSpace = THREE.SRGBColorSpace; texCache.set(tool.img, tex); }
  tex = tex.clone(); tex.repeat.set(1 / Wi, 1 / Hi); tex.offset.set(0.5, 0.5); tex.needsUpdate = true;
  const face = new THREE.MeshStandardMaterial({ map: tex, alphaTest: 0.5, roughness: 0.42, metalness: 0.25, transparent: true });
  const side = new THREE.MeshStandardMaterial({ color: new THREE.Color(tool.color).multiplyScalar(0.7), roughness: 0.5, metalness: 0.4, transparent: true });
  const mesh = new THREE.Mesh(geo, [face, side]);
  mesh.castShadow = true;
  return mesh;
}

// ---------------------------------------------------------------------------
// 4. Carousel: the open drawer's tools hover above it; scroll to pick one
// ---------------------------------------------------------------------------
export class ToolCarousel {
  constructor(scene, camera) {
    this.camera = camera; this.root = new THREE.Group(); scene.add(this.root);
    this.light = new THREE.PointLight(0xffffff, 0, 0, 2); scene.add(this.light);   // follows the carousel so tools stand out
    // game-style backdrop: dims the shop behind the tools while the carousel is open
    this.veil = new THREE.Mesh(new THREE.PlaneGeometry(4000, 4000),
      new THREE.MeshBasicMaterial({ color: 0x07080a, transparent: true, opacity: 0, depthWrite: false }));
    this.veil.visible = false; scene.add(this.veil);
    this.items = []; this.index = 0; this.anchor = null; this.visible = false; this.rise = 0;
  }
  /** tools: tool records; anchor(): world position above the drawer, recomputed every frame. */
  show(tools, anchor) {
    this.hide();
    this.anchor = anchor; this.visible = true; this.rise = 0; this.index = 0;
    for (const tool of tools) {
      // 3D model from the tool library; old photo-cutout records still work as a fallback
      const wrap = new THREE.Group(), mesh = tool.model ? buildTool(tool.model, tool.lengthIn) : toolMesh(tool);
      const mats = [];
      mesh.traverse(o => {
        if (!o.isMesh) return;
        o.material = Array.isArray(o.material) ? o.material.map(m => m.clone()) : o.material.clone();
        for (const m of [].concat(o.material)) { m.transparent = true; mats.push(m); }
      });
      const box = new THREE.Box3().setFromObject(mesh), size = box.getSize(new THREE.Vector3());
      mesh.position.sub(box.getCenter(new THREE.Vector3()));
      wrap.add(mesh); this.root.add(wrap);
      // show small things bigger and huge things smaller, so every tool is easy to see
      const big = Math.max(size.x, size.y), shown = THREE.MathUtils.clamp(big * 1.6, 15, 22);
      this.items.push({ tool, wrap, mesh, mats, fit: shown / big, s: 0.01 });
    }
  }
  /** Swap item i's model for another (e.g. a downloaded realistic one). Shared geometry is not disposed later. */
  replace(i, obj) {
    const it = this.items[i]; if (!it) return;
    it.wrap.remove(it.mesh);
    if (!it.shared) it.mesh.traverse(o => o.geometry?.dispose());
    it.mats.forEach(m => m.dispose());
    const mats = [];
    obj.traverse(o => {
      if (!o.isMesh) return;
      o.material = Array.isArray(o.material) ? o.material.map(m => m.clone()) : o.material.clone();
      for (const m of [].concat(o.material)) { m.transparent = true; mats.push(m); }
    });
    const box = new THREE.Box3().setFromObject(obj), size = box.getSize(new THREE.Vector3());
    const holder = new THREE.Group(); holder.add(obj); obj.position.sub(box.getCenter(new THREE.Vector3()));
    it.wrap.add(holder);
    const big = Math.max(size.x, size.y);
    Object.assign(it, { mesh: holder, mats, shared: true, fit: THREE.MathUtils.clamp(big * 1.6, 15, 22) / big });
  }
  hide() {
    for (const it of this.items) { this.root.remove(it.wrap); if (!it.shared) it.mesh.traverse(o => o.geometry?.dispose()); it.mats.forEach(m => m.dispose()); }
    this.items = []; this.visible = false; this.anchor = null;
    if (this.light) this.light.intensity = 0;
    if (this.veil) { this.veil.visible = false; this.veil.material.opacity = 0; }
  }
  step(d) { if (this.items.length) this.index = (this.index + d + this.items.length) % this.items.length; }
  get current() { return this.items[this.index]?.tool || null; }
  update(t) {
    if (!this.visible || !this.anchor) return;
    const n = this.items.length; if (!n) return;
    this.rise = Math.min(1, this.rise + 0.04);
    const ease = 1 - Math.pow(1 - this.rise, 3);
    const center = this.anchor().add(new THREE.Vector3(0, (ease - 1) * 8, 0));
    const right = new THREE.Vector3(1, 0, 0).applyQuaternion(this.camera.quaternion);
    const toCam = this.camera.position.clone().sub(center).normalize();
    this.light.position.copy(center).addScaledVector(toCam, 28).add(new THREE.Vector3(0, 14, 0));
    this.light.intensity = 1500 * ease;
    this.veil.visible = true;
    this.veil.position.copy(center).addScaledVector(toCam, -7);
    this.veil.quaternion.copy(this.camera.quaternion);
    this.veil.material.opacity = 0.62 * ease;
    this.items.forEach((it, i) => {
      let off = i - this.index; if (off > n / 2) off -= n; if (off < -n / 2) off += n;
      const focus = off === 0, far = Math.abs(off) > 3;
      const target = center.clone()
        .addScaledVector(right, off * 10 + Math.sign(off) * 9)
        .addScaledVector(toCam, focus ? 4 : -Math.abs(off) * 2)
        .add(new THREE.Vector3(0, focus ? Math.sin(t * 2) * 0.6 : 0, 0));
      it.wrap.position.lerp(target, 0.18);
      const sTarget = (far ? 0.001 : focus ? 1 : 0.42) * it.fit * ease;
      it.s += (sTarget - it.s) * 0.18; it.wrap.scale.setScalar(Math.max(0.001, it.s));
      it.wrap.quaternion.copy(this.camera.quaternion);
      it.mesh.rotation.y = focus ? Math.sin(t * 0.9) * 0.6 : 0;
      it.mesh.rotation.x = focus ? Math.sin(t * 0.7) * 0.12 : 0;
      for (const m of it.mats) m.opacity = focus ? 1 : 0.55;
    });
  }
}

// ---------------------------------------------------------------------------
// Sample tools (drawn on a plain background) to try the pipeline without photos
// ---------------------------------------------------------------------------
export function sampleToolImages() {
  const mk = (draw) => { const c = document.createElement('canvas'); c.width = 640; c.height = 320; const g = c.getContext('2d'); g.fillStyle = '#f5f4f0'; g.fillRect(0, 0, 640, 320); draw(g); return c; };
  const steel = (g, x0, y0, x1, y1) => { const gr = g.createLinearGradient(x0, y0, x1, y1); gr.addColorStop(0, '#8d9399'); gr.addColorStop(0.45, '#eef1f3'); gr.addColorStop(0.55, '#c9ced3'); gr.addColorStop(1, '#7a8086'); return gr; };
  const rr = (g, x, y, w, h, r) => { g.beginPath(); g.roundRect(x, y, w, h, r); g.fill(); };
  return [
    { name: 'Combination wrench 1/2"', lengthIn: 7.2, thicknessIn: 0.35, canvas: mk(g => {
      g.fillStyle = steel(g, 0, 140, 0, 180); rr(g, 120, 146, 400, 28, 12);
      g.beginPath(); g.arc(105, 160, 44, 0, Math.PI * 2); g.fill();
      g.beginPath(); g.arc(545, 160, 40, 0, Math.PI * 2); g.fill();
      g.fillStyle = '#f5f4f0'; g.beginPath(); g.arc(105, 160, 24, 0, Math.PI * 2); g.fill();
      g.fillRect(552, 143, 40, 34);
    }) },
    { name: 'Flathead screwdriver', lengthIn: 8, thicknessIn: 1.1, canvas: mk(g => {
      const gr = g.createLinearGradient(0, 120, 0, 200); gr.addColorStop(0, '#e0302a'); gr.addColorStop(0.5, '#ff6a52'); gr.addColorStop(1, '#a3171a');
      g.fillStyle = gr; rr(g, 60, 125, 220, 70, 30);
      g.fillStyle = '#1b1b1b'; rr(g, 250, 132, 40, 56, 10);
      g.fillStyle = steel(g, 0, 152, 0, 168); g.fillRect(288, 152, 250, 16);
      g.beginPath(); g.moveTo(538, 150); g.lineTo(585, 154); g.lineTo(585, 166); g.lineTo(538, 170); g.fill();
    }) },
    { name: 'Claw hammer 16 oz', lengthIn: 13, thicknessIn: 1.1, canvas: mk(g => {
      const wood = g.createLinearGradient(0, 140, 0, 185); wood.addColorStop(0, '#b07a45'); wood.addColorStop(0.5, '#d9a066'); wood.addColorStop(1, '#8a5a2e');
      g.fillStyle = wood; rr(g, 150, 143, 430, 38, 18);
      g.fillStyle = steel(g, 70, 0, 170, 0); rr(g, 95, 70, 70, 120, 10);
      g.beginPath(); g.moveTo(95, 190); g.quadraticCurveTo(60, 240, 75, 282); g.lineTo(105, 270); g.quadraticCurveTo(100, 235, 130, 190); g.fill();
      g.beginPath(); g.moveTo(130, 190); g.quadraticCurveTo(150, 240, 175, 270); g.lineTo(150, 282); g.quadraticCurveTo(120, 240, 120, 190); g.fill();
      g.fillStyle = steel(g, 0, 40, 0, 80); rr(g, 100, 40, 60, 40, 8);
    }) },
    { name: 'Slip-joint pliers', lengthIn: 8, thicknessIn: 0.6, canvas: mk(g => {
      g.fillStyle = steel(g, 0, 120, 0, 200); g.beginPath(); g.moveTo(60, 150); g.lineTo(230, 130); g.lineTo(250, 160); g.lineTo(230, 190); g.lineTo(60, 170); g.fill();
      g.beginPath(); g.arc(250, 160, 26, 0, Math.PI * 2); g.fill();
      g.fillStyle = '#d3242b';
      g.beginPath(); g.moveTo(270, 148); g.quadraticCurveTo(420, 90, 590, 110); g.lineTo(592, 134); g.quadraticCurveTo(430, 120, 272, 168); g.fill();
      g.beginPath(); g.moveTo(270, 172); g.quadraticCurveTo(420, 230, 590, 210); g.lineTo(592, 186); g.quadraticCurveTo(430, 200, 272, 152); g.fill();
    }) },
    { name: '3/8" drive ratchet', lengthIn: 8.5, thicknessIn: 0.9, canvas: mk(g => {
      g.fillStyle = steel(g, 0, 140, 0, 180); rr(g, 150, 145, 420, 30, 14);
      g.beginPath(); g.ellipse(120, 160, 58, 50, 0, 0, Math.PI * 2); g.fill();
      g.fillStyle = '#2a2d31'; g.beginPath(); g.arc(120, 160, 18, 0, Math.PI * 2); g.fill();
      g.fillStyle = '#1d1f22'; rr(g, 330, 147, 230, 26, 12);
    }) },
    { name: 'Tape measure 25 ft', lengthIn: 3.6, thicknessIn: 1.8, canvas: mk(g => {
      const y = g.createLinearGradient(0, 60, 0, 260); y.addColorStop(0, '#ffd21a'); y.addColorStop(1, '#d9a400');
      g.fillStyle = y; rr(g, 200, 60, 230, 200, 60);
      g.fillStyle = '#1e1e1e'; rr(g, 235, 95, 160, 130, 50);
      g.fillStyle = '#ffd21a'; g.beginPath(); g.arc(315, 160, 32, 0, Math.PI * 2); g.fill();
      g.fillStyle = steel(g, 0, 225, 0, 255); g.fillRect(430, 228, 36, 22); g.fillRect(462, 222, 8, 34);
    }) },
  ];
}
