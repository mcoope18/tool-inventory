// Library of 3D tool models built from a small spec the AI returns:
//   { type, variant, colors: { primary, secondary, metal } }  +  length in inches.
// Every tool lies along +x (back end at x≈0), seen in profile from +z, then is centered.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

// ---------------------------------------------------------------------------
// Materials
// ---------------------------------------------------------------------------
const cache = new Map();
const keep = (k, make) => cache.get(k) || (cache.set(k, make()), cache.get(k));
const METAL = {
  chrome: () => keep('chrome', () => new THREE.MeshStandardMaterial({ color: 0xe4e7ea, metalness: 1, roughness: 0.16 })),
  steel: () => keep('steel', () => new THREE.MeshStandardMaterial({ color: 0xa6abb1, metalness: 0.9, roughness: 0.38 })),
  black: () => keep('blackox', () => new THREE.MeshStandardMaterial({ color: 0x2c2e32, metalness: 0.7, roughness: 0.42 })),
  nickel: () => keep('nickel', () => new THREE.MeshStandardMaterial({ color: 0xc9ccd0, metalness: 0.95, roughness: 0.3 })),
};
const metal = k => (METAL[k] || METAL.chrome)();
const paint = (hex, rough = 0.5) => keep(`p${hex}${rough}`, () => new THREE.MeshStandardMaterial({ color: new THREE.Color(hex), roughness: rough, metalness: 0.05 }));
const glossy = hex => keep(`g${hex}`, () => new THREE.MeshPhysicalMaterial({ color: new THREE.Color(hex), roughness: 0.12, clearcoat: 1, transparent: true, opacity: 0.9 }));
const rubber = hex => keep(`r${hex}`, () => new THREE.MeshStandardMaterial({ color: new THREE.Color(hex), roughness: 0.8 }));

// ---------------------------------------------------------------------------
// Geometry helpers (inches)
// ---------------------------------------------------------------------------
const V2 = (x, y) => new THREE.Vector2(x, y), V3 = (x, y, z = 0) => new THREE.Vector3(x, y, z);
const clamp = THREE.MathUtils.clamp;
function add(geo, mat, parent) { const m = new THREE.Mesh(geo, mat); m.castShadow = true; parent.add(m); return m; }
function poly(pts) { const s = new THREE.Shape(); s.moveTo(pts[0][0], pts[0][1]); for (const p of pts.slice(1)) s.lineTo(p[0], p[1]); s.closePath(); return s; }
function smooth(pts) { const s = new THREE.Shape(); s.moveTo(pts[0][0], pts[0][1]); s.splineThru(pts.slice(1).map(p => V2(p[0], p[1]))); s.closePath(); return s; }
function ext(shape, depth, mat, parent, bevel = 0.04, z = 0) {
  const g = new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: bevel > 0, bevelThickness: bevel, bevelSize: bevel, bevelSegments: 2, curveSegments: 20 });
  g.translate(0, 0, -depth / 2 + z); return add(g, mat, parent);
}
function tube(pts, r, mat, parent, z = 0, caps = true) {
  const curve = new THREE.CatmullRomCurve3(pts.map(p => V3(p[0], p[1], z)));
  const m = add(new THREE.TubeGeometry(curve, 48, r, 14, false), mat, parent);
  if (caps) for (const p of [pts[0], pts[pts.length - 1]]) { const s = add(new THREE.SphereGeometry(r, 14, 10), mat, parent); s.position.set(p[0], p[1], z); }
  return m;
}
/** Partial tube along the same path, from fraction a to b (for grips and stripes). */
function tubePart(pts, a, b, r, mat, parent, z = 0, dy = 0) {
  const curve = new THREE.CatmullRomCurve3(pts.map(p => V3(p[0], p[1] + dy, z)));
  const sub = []; for (let i = 0; i <= 24; i++) sub.push(curve.getPointAt(Math.min(1, Math.max(0, a + (b - a) * i / 24))));
  const c2 = new THREE.CatmullRomCurve3(sub);
  add(new THREE.TubeGeometry(c2, 40, r, 14, false), mat, parent);
  for (const p of [sub[0], sub[sub.length - 1]]) { const s = add(new THREE.SphereGeometry(r, 14, 10), mat, parent); s.position.copy(p); }
}
/** Lathe around the x axis. prof = [[radius, x], ...] */
function lathe(prof, mat, parent, segs = 28) {
  const g = new THREE.LatheGeometry(prof.map(([r, x]) => V2(Math.max(0.01, r), x)), segs); g.rotateZ(-Math.PI / 2); return add(g, mat, parent);
}
function cylX(r, len, mat, parent, x, y = 0, z = 0, segs = 20) {
  const g = new THREE.CylinderGeometry(r, r, len, segs); g.rotateZ(Math.PI / 2);
  const m = add(g, mat, parent); m.position.set(x, y, z); return m;
}
function cylZ(r, len, mat, parent, x, y, z = 0) {
  const g = new THREE.CylinderGeometry(r, r, len, 24); g.rotateX(Math.PI / 2);
  const m = add(g, mat, parent); m.position.set(x, y, z); return m;
}
function rbox(w, h, d, mat, parent, x, y, z = 0, r = 0.1) {
  const m = add(new RoundedBoxGeometry(w, h, d, 3, Math.min(r, w / 2 - 0.01, h / 2 - 0.01, d / 2 - 0.01)), mat, parent); m.position.set(x, y, z); return m;
}

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------
function handleMat(c, style) { return style === 'acetate' ? glossy(c.primary) : paint(c.primary, 0.45); }

function screwdriver(L, v, c, g, isPick = false) {
  const stubby = v === 'stubby' || L < 4.5;
  const H = stubby ? L * 0.6 : clamp(L * 0.4, 2.8, 4.8), R = clamp(L * 0.06, 0.42, 0.62);
  const hm = handleMat(c, c.style || (v === 'acetate' ? 'acetate' : ''));
  lathe([[0.02, 0], [R * 0.78, 0], [R * 0.98, H * 0.07], [R, H * 0.35], [R * 0.96, H * 0.68], [R * 0.72, H * 0.9], [R * 0.4, H], [0.02, H]], hm, g);
  if (c.secondary) lathe([[R * 0.9, H * 0.1], [R * 1.05, H * 0.14], [R * 1.06, H * 0.4], [R * 1.0, H * 0.66], [R * 0.9, H * 0.7]], rubber(c.secondary), g);
  for (let i = 0; i < 6; i++) { // flutes
    const a = i / 6 * Math.PI * 2, f = rbox(H * 0.5, 0.08, 0.08, hm, g, H * 0.42, Math.cos(a) * R * 0.98, Math.sin(a) * R * 0.98, 0.03);
    f.rotation.x = a;
  }
  const m = metal(c.metal || 'chrome');
  if (isPick) {
    const r = 0.07, end = L;
    const pts = v === 'straight' ? [[H, 0], [end, 0]] : v === '90' ? [[H, 0], [end - 0.6, 0], [end - 0.5, 0.05], [end - 0.45, 0.6]] : [[H, 0], [end - 0.9, 0], [end - 0.55, 0.08], [end - 0.42, 0.35], [end - 0.55, 0.55]];
    tube(pts, r, m, g);
    return;
  }
  const sr = L > 9 ? 0.15 : 0.12, tipL = 0.4;
  cylX(sr, L - H - tipL, m, g, H + (L - H - tipL) / 2);
  if (v === 'phillips' || v === 'torx') {
    const cone = add(new THREE.ConeGeometry(sr, tipL, 12), m, g); cone.rotation.z = -Math.PI / 2; cone.position.x = L - tipL / 2;
  } else {
    ext(poly([[L - tipL, -sr], [L, -sr * 1.7], [L, sr * 1.7], [L - tipL, sr]]), 0.07, m, g, 0.01);
  }
}

function pliers(L, v, c, g) {
  const k = L / 8, m = metal(c.metal || 'chrome');
  const jf = { lineman: 0.27, diagonal: 0.19, 'long-nose': 0.4, 'slip-joint': 0.24, 'groove-joint': 0.19, stripper: 0.3, snips: 0.32 }[v] ?? 0.26;
  const J = L * jf, Hl = L - J;
  const wb = ({ lineman: 0.62, diagonal: 0.56, 'long-nose': 0.38, 'slip-joint': 0.5, 'groove-joint': 0.55, stripper: 0.45, snips: 0.6 }[v] ?? 0.5) * k;
  const wt = ({ lineman: 0.42, diagonal: 0.05, 'long-nose': 0.06, 'slip-joint': 0.28, 'groove-joint': 0.36, stripper: 0.32, snips: 0.04 }[v] ?? 0.3) * k;
  const t = 0.2 * Math.sqrt(k), spread = clamp(0.085 * L, 0.5, 1.2);
  const open = v === 'groove-joint' ? 0.07 : 0.045;
  for (const s of [1, -1]) {
    const arm = new THREE.Group(); arm.position.z = s * t / 2; arm.rotation.z = s * open; g.add(arm);
    const jaw = new THREE.Group(); arm.add(jaw);
    if (v === 'groove-joint') jaw.rotation.z = -0.42;   // angled head
    const side = new THREE.Group(); side.scale.y = s; jaw.add(side);
    const pts = v === 'diagonal' || v === 'snips'
      ? [[-0.4 * k, 0.02], [J, 0.01], [J * 0.85, wb * 0.35 + wt], [J * 0.4, wb * 0.95], [-0.4 * k, wb * 0.85]]
      : [[-0.4 * k, 0.02], [J, 0.02], [J, wt], [J * 0.55, wb * 0.75], [J * 0.12, wb], [-0.4 * k, wb * 0.85]];
    ext(v === 'long-nose' ? smooth(pts) : poly(pts), t, m, side, 0.03);
    if (v === 'stripper') for (let i = 0; i < 4; i++) cylZ(0.04 + i * 0.015, t + 0.02, paint('#222', 0.6), side, J * (0.3 + i * 0.17), 0.08);
    cylZ(wb * 0.92, t, m, side, 0, 0);
    // handle: steel core, then the grip
    const hp = [[-0.2 * k, wb * 0.3 * s], [-0.25 * Hl, (wb * 0.5 + 0.06) * s], [-0.6 * Hl, spread * 0.6 * s], [-Hl, spread * s]];
    if (v === 'groove-joint') { hp[1][1] = wb * 0.4 * s; hp[2][1] = spread * 0.45 * s; }
    tube(hp, 0.13 * k, m, arm);
    tubePart(hp, 0.2, 1, 0.25 * Math.max(0.85, k), paint(c.primary || '#c8202a', 0.5), arm);
    if (c.secondary) tubePart(hp, 0.32, 0.92, 0.12 * Math.max(0.85, k), paint(c.secondary, 0.5), arm, 0, 0.17 * s);
  }
  if (v === 'groove-joint') for (let i = 0; i < 4; i++) rbox(0.08, 0.5 * k, t * 2.3, m, g, -0.1 - i * 0.12, -0.15 * k, 0, 0.02);
  cylZ(0.17 * k, t * 2 + 0.12, metal('chrome'), g, 0, 0);
}

/**
 * Vise-Grip style locking pliers, modelled on the classic curved-jaw shape: a wide stamped fixed handle running
 * from the jaw straight back to the knurled adjusting screw, a narrower movable handle alongside it that flares
 * out at the end (release lever inside), big jaws forming an oval toothed opening, dome rivets and the spring.
 */
function lockingPliers(L, v, c, g) {
  const k = L / 10, m = metal(c.metal || 'nickel'), dark = metal('black'), t = 0.42 * k;
  const X = x => x * k, Y = y => y * k;               // design units: a 10" tool, x 0 (screw) → 10 (jaw tip)
  const rim = (pts, z) => tube(pts.map(([x, y]) => [X(x), Y(y)]), 0.07 * k, m, g, z * t * 0.55, false);
  // adjusting screw + knurled knob
  cylX(Y(0.36), X(0.5), m, g, X(0.25), Y(0.48), 0, 28);
  for (let i = 0; i < 5; i++) cylX(Y(0.37), X(0.03), dark, g, X(0.06 + i * 0.1), Y(0.48), 0, 28);
  cylX(Y(0.17), X(0.7), metal('steel'), g, X(0.85), Y(0.48));
  // fixed handle: one wide stamped body with rolled edges
  const body = [[1.0, 0.02], [4.5, 0.0], [7.0, -0.02], [7.35, 0.22], [7.3, 1.08], [4.5, 1.02], [1.0, 0.95], [0.85, 0.5]];
  ext(smooth(body.map(([x, y]) => [X(x), Y(y)])), t, m, g, 0.06 * k);
  for (const z of [1, -1]) { rim([[1.0, 0.94], [4.5, 1.01], [7.2, 1.06]], z); rim([[1.0, 0.04], [4.5, 0.02], [7.0, 0.0]], z); }
  ext(smooth([[X(5.7), Y(0.38)], [X(6.8), Y(0.42)], [X(6.8), Y(0.62)], [X(5.7), Y(0.6)]]), t * 1.08, dark, g, 0.02 * k);   // slot for the toggle link
  // jaws: an oval toothed opening, fixed jaw on top, movable jaw below
  const cy = v === 'long-nose' ? 0.25 : 0.2;
  const upper = v === 'long-nose'
    ? [[7.0, 1.05], [8.4, 0.85], [10.0, 0.4], [10.0, 0.27], [8.4, 0.3], [7.0, 0.25]]
    : v === 'straight-jaw'
      ? [[7.0, 1.08], [8.4, 1.15], [9.9, 0.9], [9.95, 0.27], [8.4, 0.27], [7.0, 0.25]]
      : [[7.0, 1.08], [8.2, 1.32], [9.35, 1.15], [9.98, 0.58], [9.9, 0.3], [9.25, 0.58], [8.4, 0.68], [7.7, 0.5], [7.25, 0.3]];
  ext(smooth(upper.map(([x, y]) => [X(x), Y(y)])), t * 0.95, m, g, 0.06 * k);
  const lower = upper.map(([x, y]) => [x, 2 * cy - y]);
  ext(smooth([...lower, [6.6, -0.95], [6.2, -0.7]].map(([x, y]) => [X(x), Y(y)])), t * 0.9, m, g, 0.06 * k, -t * 0.05);
  // teeth along both jaw edges
  const inner = upper.filter(([x, y]) => x > 7.4 && y < 0.75);
  for (const [x, y] of inner) for (const s of [1, -1]) {
    const yy = s > 0 ? y : 2 * cy - y;
    rbox(X(0.12), Y(0.12), t * 1.0, dark, g, X(x), Y(yy - s * 0.05), 0, 0.02);
  }
  // movable handle: narrower stamped channel beside the body, flaring out at the end
  const lh = [[6.6, -0.22], [4.5, -0.28], [2.2, -0.34], [1.1, -0.55], [0.55, -0.95], [0.7, -1.32], [1.4, -1.0], [2.4, -0.92], [4.5, -0.9], [6.4, -0.92]];
  ext(smooth(lh.map(([x, y]) => [X(x), Y(y)])), t * 0.85, c.primary ? paint(c.primary, 0.5) : m, g, 0.06 * k);
  for (const z of [1, -1]) rim([[6.4, -0.9], [4.5, -0.88], [2.4, -0.9], [1.4, -0.98]], z);
  // release lever tucked inside the movable handle
  tube([[X(3.3), Y(-0.62)], [X(2.2), Y(-0.6)], [X(1.3), Y(-0.78)], [X(0.95), Y(-1.08)]], 0.08 * k, c.secondary ? paint(c.secondary) : metal('steel'), g, t * 0.5);
  // coil spring across the gap
  const pts = [], a = V3(X(6.3), Y(0.05), 0), b = V3(X(4.4), Y(-0.25), 0), turns = 11;
  for (let i = 0; i <= turns * 12; i++) {
    const u = i / (turns * 12), p = a.clone().lerp(b, u), ang = u * turns * Math.PI * 2;
    pts.push([p.x, p.y + Math.sin(ang) * 0.1 * k, Math.cos(ang) * 0.1 * k]);
  }
  add(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts.map(([x, y, z]) => V3(x, y, z))), 300, 0.025 * k, 6, false), dark, g);
  // dome rivets
  for (const [x, y] of [[7.05, 0.65], [6.55, -0.42], [5.55, -0.6], [3.4, -0.62]]) {
    for (const s of [1, -1]) {
      const d = add(new THREE.SphereGeometry(0.17 * k, 18, 10, 0, Math.PI * 2, 0, Math.PI / 2), metal('chrome'), g);
      d.rotation.x = s * Math.PI / 2; d.position.set(X(x), Y(y), s * t * 0.5);
    }
  }
}

function lockingPliersOld(L, v, c, g) {
  const k = L / 10, m = metal(c.metal || 'chrome'), J = L * (v === 'long-nose' ? 0.34 : 0.22), H = L - J, t = 0.42 * k;
  const curved = v !== 'straight-jaw' && v !== 'long-nose';
  // big curved jaws (the gap in the middle is what makes them read as Vise-Grips)
  const jawPts = curved
    ? [[-0.4 * k, 0.05 * k], [0.3 * J, 0.32 * k], [0.72 * J, 0.26 * k], [J, 0.06 * k], [J * 1.03, 0.5 * k], [0.66 * J, 0.95 * k], [0.15 * J, 1.08 * k], [-0.4 * k, 1.02 * k]]
    : [[-0.4 * k, 0.04 * k], [J, 0.04 * k], [J, 0.3 * k], [0.4 * J, 0.8 * k], [-0.4 * k, 0.95 * k]];
  for (const s of [1, -1]) { const side = new THREE.Group(); side.scale.y = s; g.add(side); ext(curved ? smooth(jawPts) : poly(jawPts), t, m, side, 0.05); }
  // upper handle: a stamped steel channel running straight back to the adjusting screw
  ext(poly([[-0.3 * k, 0.2 * k], [-0.3 * k, 1.05 * k], [-H, 0.92 * k], [-H, 0.32 * k]]), t * 1.2, m, g, 0.06);
  rbox(H * 0.8, 0.3 * k, 0.06, metal('black'), g, -H * 0.53, 0.63 * k, t * 0.62, 0.03);
  // adjusting screw and knurled knob
  cylX(0.17 * k, 0.1 * L, metal('steel'), g, -H - 0.05 * L, 0.62 * k);
  cylX(0.36 * k, 0.07 * L, m, g, -H - 0.13 * L, 0.62 * k, 0, 28);
  for (let i = 0; i < 4; i++) cylX(0.37 * k, 0.01 * L, metal('black'), g, -H - 0.105 * L - i * 0.016 * L, 0.62 * k, 0, 28);
  // lower handle swings away below, with the link and the release lever inside it
  const lp = [[0.05 * k, -0.62 * k], [-0.25 * H, -1.3 * k], [-0.6 * H, -1.85 * k], [-0.96 * H, -2.1 * k]];
  tube(lp, 0.3 * k, c.primary && c.grips !== false ? paint(c.primary, 0.5) : m, g).scale.z = 0.65;
  tube([[-0.1 * H, -0.85 * k], [-0.45 * H, 0.45 * k]], 0.12 * k, metal('steel'), g);
  tube([[-0.42 * H, -1.3 * k], [-0.86 * H, -1.62 * k]], 0.09 * k, c.secondary ? paint(c.secondary) : metal('steel'), g, 0.12 * k);
  for (const y of [0.55 * k, -0.55 * k]) cylZ(0.16 * k, t * 1.5, metal('chrome'), g, 0, y);
}

function wrench(L, v, c, g) {
  const m = metal(c.metal || 'chrome'), h = clamp(0.1 * L, 0.42, 1.1), r1 = clamp(0.085 * L, 0.42, 1.0), r2 = r1 * 1.08, t = clamp(0.045 * L, 0.2, 0.45);
  ext(poly([[r1 * 0.7, -h / 2], [L - r2 * 0.8, -h * 0.42], [L - r2 * 0.8, h * 0.42], [r1 * 0.7, h / 2]]), t, m, g, 0.05);
  rbox(L - r1 - r2 - 0.4, h * 0.45, 0.05, metal('steel'), g, (r1 + L - r2) / 2, 0, t / 2 + 0.04, 0.05);
  const ring = new THREE.Shape(); ring.absarc(r1, 0, r1, 0, Math.PI * 2);
  const hole = new THREE.Path(); for (let i = 0; i <= 12; i++) { const a = i / 12 * Math.PI * 2, rr = r1 * (i % 2 ? 0.5 : 0.56); (i ? hole.lineTo.bind(hole) : hole.moveTo.bind(hole))(r1 + Math.cos(a) * rr, Math.sin(a) * rr); }
  ring.holes.push(hole);
  ext(ring, t * 1.2, m, g, 0.05);
  const cx = L - r2, a = Math.asin(0.78), w = r2 * 0.95, pts = [];
  for (let th = a; th <= Math.PI * 2 - a; th += 0.12) pts.push([cx + r2 * Math.cos(th), r2 * Math.sin(th)]);
  const fx = cx + r2 * Math.cos(a);
  pts.push([fx, -w / 2], [cx - 0.1 * r2, -w / 2], [cx - 0.1 * r2, w / 2], [fx, w / 2]);
  const rot = 0.26, rp = pts.map(([x, y]) => [cx + (x - cx) * Math.cos(rot) - y * Math.sin(rot), (x - cx) * Math.sin(rot) + y * Math.cos(rot)]);
  ext(poly(rp), t * 1.1, m, g, 0.05);
}

function adjustableWrench(L, v, c, g) {
  const m = metal(c.metal || 'chrome'), k = L / 10, t = 0.38 * k;
  ext(smooth([[0, -0.3 * k], [0.66 * L, -0.42 * k], [0.72 * L, 0], [0.66 * L, 0.42 * k], [0, 0.3 * k], [-0.25 * k, 0]]), t, m, g, 0.05);
  cylZ(0.14 * k, t + 0.1, paint('#111', 0.8), g, 0.12 * k, 0);   // hang hole
  ext(poly([[0.66 * L, -0.5 * k], [0.93 * L, -0.62 * k], [L, -0.3 * k], [L, 0.32 * k], [0.975 * L, 1.32 * k], [0.905 * L, 1.36 * k], [0.88 * L, 0.55 * k], [0.76 * L, 0.55 * k], [0.69 * L, 0.42 * k]]), t * 1.15, m, g, 0.05);
  rbox(0.1 * L, 0.68 * k, t * 1.05, m, g, 0.81 * L, 0.95 * k, 0, 0.05);
  cylX(0.2 * k, 0.1 * L, metal('steel'), g, 0.8 * L, 0.25 * k, t * 0.35, 18);   // knurled worm
  for (let i = 0; i < 6; i++) cylX(0.22 * k, 0.006 * L, metal('black'), g, 0.755 * L + i * 0.017 * L, 0.25 * k, t * 0.35, 18);
  if (c.primary) ext(smooth([[0.02 * L, -0.33 * k], [0.55 * L, -0.45 * k], [0.55 * L, 0.45 * k], [0.02 * L, 0.33 * k]]), t * 1.35, rubber(c.primary), g, 0.06);
}

function hammer(L, v, c, g) {
  const k = L / 13 * 1.35, m = metal(c.metal || 'steel'), hx = L - 0.55 * k;   // head drawn a bit large so it reads at a glance
  const handle = c.style === 'wood' || !c.primary ? paint('#c48a52', 0.6) : paint(c.primary, 0.5);
  lathe([[0.42 * k, 0], [0.46 * k, 0.1 * L], [0.36 * k, 0.5 * L], [0.32 * k, 0.85 * L], [0.36 * k, L - 0.5 * k], [0.01, L - 0.5 * k]], handle, g, 20).scale.z = 0.65;
  if (c.secondary) lathe([[0.5 * k, 0.02 * L], [0.52 * k, 0.1 * L], [0.44 * k, 0.33 * L], [0.38 * k, 0.36 * L]], rubber(c.secondary), g, 20).scale.z = 0.7;
  if (v === 'ball-peen') {
    const head = add(new THREE.CylinderGeometry(0.5 * k, 0.5 * k, 2.4 * k, 24), m, g); head.position.set(hx, 0.2 * k, 0);
    const ball = add(new THREE.SphereGeometry(0.62 * k, 24, 16), m, g); ball.position.set(hx, -1.2 * k, 0);
  } else {
    const head = add(new THREE.CylinderGeometry(0.5 * k, 0.45 * k, 1.4 * k, 24), m, g); head.position.set(hx, 0.85 * k, 0);
    const face = add(new THREE.CylinderGeometry(0.58 * k, 0.58 * k, 0.3 * k, 24), m, g); face.position.set(hx, 1.6 * k, 0);
    rbox(1.0 * k, 0.9 * k, 0.9 * k, m, g, hx, 0.05 * k, 0, 0.15 * k);
    for (const z of [0.18 * k, -0.18 * k]) tube([[hx, -0.3 * k], [hx - 0.15 * k, -1.2 * k], [hx - 0.6 * k, -2.0 * k], [hx - 1.1 * k, -2.3 * k]], 0.2 * k, m, g, z);
  }
}

function utilityKnife(L, v, c, g) {
  const k = L / 6.5, body = paint(c.primary || '#d8262c', 0.45);
  if (v === 'folding') {
    ext(smooth([[0, -0.35 * k], [0.62 * L, -0.42 * k], [0.7 * L, 0], [0.62 * L, 0.42 * k], [0, 0.35 * k], [-0.15 * k, 0]]), 0.42 * k, body, g, 0.06);
    ext(poly([[0.64 * L, -0.25 * k], [L, -0.05 * k], [0.86 * L, 0.32 * k], [0.64 * L, 0.3 * k]]), 0.05, metal('chrome'), g, 0.01);
  } else {
    ext(smooth([[0, -0.5 * k], [0.55 * L, -0.55 * k], [0.86 * L, -0.25 * k], [0.86 * L, 0.32 * k], [0.4 * L, 0.6 * k], [0, 0.5 * k], [-0.12 * k, 0]]), 0.6 * k, body, g, 0.08);
    ext(poly([[0.84 * L, -0.2 * k], [L, -0.05 * k], [0.9 * L, 0.26 * k], [0.84 * L, 0.26 * k]]), 0.05, metal('chrome'), g, 0.01);
  }
  if (c.secondary) ext(smooth([[0.05 * L, -0.38 * k], [0.45 * L, -0.42 * k], [0.45 * L, 0.38 * k], [0.05 * L, 0.36 * k]]), (v === 'folding' ? 0.48 : 0.68) * k, rubber(c.secondary), g, 0.04);
  rbox(0.5 * k, 0.18 * k, 0.12, metal('steel'), g, 0.45 * L, 0.5 * k, 0, 0.05);
}

function tapeMeasure(L, v, c, g) {
  const s = clamp(L, 2.5, 4.5), body = paint(c.primary || '#ffd21a', 0.45);
  rbox(s, s * 0.95, s * 0.48, body, g, 0, 0, 0, s * 0.22);
  cylZ(s * 0.32, s * 0.5, rubber(c.secondary || '#1d1d1d'), g, -0.05 * s, 0.03 * s);
  cylZ(s * 0.12, s * 0.52, body, g, -0.05 * s, 0.03 * s);
  rbox(s * 0.35, 0.05, s * 0.36, paint('#f2e14a', 0.4), g, s * 0.58, -s * 0.44, 0, 0.02);
  rbox(0.05, s * 0.14, s * 0.38, metal('steel'), g, s * 0.75, -s * 0.38, 0, 0.02);
  rbox(s * 0.12, s * 0.1, s * 0.22, rubber('#1d1d1d'), g, s * 0.3, s * 0.48, 0, 0.03);
}

function pryBar(L, v, c, g) {
  const mat = c.primary ? paint(c.primary, 0.45) : metal(c.metal || 'steel'), k = L / 12;
  const pts = v === 'straight' ? [[0, 0], [L, 0]] : [[0, 0.6 * k], [0.05 * L, 0.15 * k], [0.12 * L, 0], [0.88 * L, 0], [0.95 * L, 0.2 * k], [L, 0.9 * k]];
  tube(pts, 0.42 * k, mat, g, 0, false).scale.z = 0.28;
}

function powerTool(L, v, c, g) {
  const k = L / 8, body = paint(c.primary || '#c8202a', 0.42), dark = paint(c.secondary || '#1d1e20', 0.65);
  const bl = (v === 'drill' ? 0.62 : 0.55) * L;
  lathe([[0.7 * k, 0], [0.95 * k, 0.1 * bl], [0.98 * k, 0.55 * bl], [0.8 * k, 0.85 * bl], [0.58 * k, bl], [0.01, bl]], body, g);
  ext(smooth([[0.1 * bl, -0.4 * k], [0.52 * bl, -0.4 * k], [0.44 * bl, -2.9 * k], [0.06 * bl, -2.9 * k]]), 1.25 * k, body, g, 0.15);
  ext(smooth([[0.06 * bl, -0.9 * k], [0.3 * bl, -0.9 * k], [0.26 * bl, -2.8 * k], [0.02 * bl, -2.8 * k]]), 1.4 * k, dark, g, 0.12);
  ext(poly([[0.44 * bl, -0.55 * k], [0.56 * bl, -0.55 * k], [0.52 * bl, -1.1 * k], [0.43 * bl, -1.1 * k]]), 0.3 * k, dark, g, 0.05);
  rbox(2.6 * k, 1.1 * k, 1.8 * k, dark, g, 0.26 * bl, -3.35 * k, 0, 0.18 * k);
  rbox(2.5 * k, 0.25 * k, 1.82 * k, body, g, 0.26 * bl, -2.95 * k, 0, 0.08 * k);
  if (v === 'drill' || v === 'driver' || v === 'screwdriver') {
    lathe([[0.48 * k, bl], [0.5 * k, bl + 0.08 * L], [0.36 * k, bl + 0.22 * L], [0.01, bl + 0.22 * L]], paint('#1d1e20', 0.5), g);
    cylX(0.09 * k, 0.12 * L, metal('steel'), g, bl + 0.28 * L);
  } else {
    lathe([[0.42 * k, bl], [0.42 * k, bl + 0.1 * L], [0.25 * k, bl + 0.14 * L], [0.01, bl + 0.14 * L]], metal('steel'), g);
  }
}

function ratchet(L, v, c, g) {
  const k = L / 9, m = metal(c.metal || 'chrome'), hr = 0.95 * k;
  lathe([[0.36 * k, 0], [0.46 * k, 0.05 * L], [0.42 * k, 0.55 * L], [0.3 * k, L - 1.6 * hr], [0.45 * k, L - hr], [0.01, L - hr]], m, g).scale.z = 0.75;
  if (c.primary) lathe([[0.44 * k, 0.03 * L], [0.54 * k, 0.08 * L], [0.52 * k, 0.48 * L], [0.44 * k, 0.53 * L]], rubber(c.primary), g).scale.z = 0.8;
  cylZ(hr, 0.7 * k, m, g, L - hr, 0);
  cylZ(hr * 0.55, 0.74 * k, metal('steel'), g, L - hr, 0);
  rbox(0.5 * k, 0.5 * k, 0.5 * k, metal('steel'), g, L - hr, 0, -0.6 * k, 0.05);
  rbox(0.75 * k, 0.22 * k, 0.16 * k, metal('black'), g, L - hr, 0.35 * k, 0.4 * k, 0.05);
}

function socket(L, v, c, g) {
  const r = clamp(L * 0.35, 0.35, 0.9), m = metal(c.metal || 'chrome');
  lathe([[r * 0.85, 0], [r * 0.85, L * 0.35], [r, L * 0.45], [r, L], [0.01, L]], m, g);
  cylX(r * 0.6, 0.02, paint('#111', 0.8), g, L + 0.005);
}

function hexKey(L, v, c, g) { tube([[0, 0], [L, 0], [L + 0.25, 0.1], [L + 0.3, 0.3 * L]], clamp(L * 0.025, 0.05, 0.2), metal(c.metal || 'black'), g); }

function punch(L, v, c, g) {
  const m = metal(c.metal || 'black'), r = clamp(L * 0.05, 0.18, 0.4);
  cylX(r, L * 0.65, m, g, L * 0.325, 0, 0, 6);
  lathe([[r, L * 0.65], [r * 0.4, L * 0.95], [v === 'chisel' ? r * 0.7 : r * 0.25, L]], metal('steel'), g, 6);
}

function file(L, v, c, g) {
  const H = L * 0.3;
  lathe([[0.3, 0], [0.42, 0.1 * H], [0.38, H], [0.1, H]], c.primary ? paint(c.primary) : paint('#2a2a2a'), g);
  ext(poly([[H, -0.08], [H + 0.2, -0.38], [L - 0.5, -0.25], [L, -0.05], [L, 0.05], [L - 0.5, 0.25], [H + 0.2, 0.38], [H, 0.08]]), 0.12, metal('steel'), g, 0.01);
}

function flashlight(L, v, c, g) {
  const b = c.primary ? paint(c.primary, 0.4) : metal('black'), r = clamp(L * 0.07, 0.35, 0.8);
  lathe([[r * 0.8, 0], [r, 0.05 * L], [r, 0.7 * L], [r * 1.4, 0.82 * L], [r * 1.4, L], [0.01, L]], b, g);
  cylX(r * 1.25, 0.02, paint('#fffbe0', 0.1), g, L + 0.01);
}

function genericBox(L, v, c, g) {
  rbox(L, L * 0.62, L * 0.32, paint(c.primary || '#c8202a', 0.5), g, L / 2, 0, 0, 0.15);
  if (c.secondary) rbox(L * 0.7, L * 0.35, 0.02, paint(c.secondary, 0.4), g, L / 2, 0, L * 0.16, 0.01);
}

const BUILD = {
  screwdriver, pick: (L, v, c, g) => screwdriver(L, v, c, g, true), pliers, 'locking-pliers': lockingPliers,
  wrench, 'adjustable-wrench': adjustableWrench, hammer, 'utility-knife': utilityKnife, 'tape-measure': tapeMeasure,
  'pry-bar': pryBar, 'power-tool': powerTool, ratchet, socket, 'hex-key': hexKey, punch, file, flashlight, box: genericBox,
};
export const TOOL_TYPES = Object.keys(BUILD);
export const TOOL_VARIANTS = {
  screwdriver: ['flat', 'phillips', 'torx', 'stubby'], pick: ['hook', '90', 'straight'],
  pliers: ['lineman', 'diagonal', 'long-nose', 'slip-joint', 'groove-joint', 'stripper', 'snips'],
  'locking-pliers': ['curved-jaw', 'straight-jaw', 'long-nose'], wrench: ['combination'], hammer: ['claw', 'ball-peen'],
  'utility-knife': ['fixed', 'folding'], 'pry-bar': ['flat', 'straight'], 'power-tool': ['drill', 'impact', 'driver', 'screwdriver'],
  punch: ['punch', 'chisel'],
};
/** A few ready-made tools to try the carousel without a photo. */
export const SAMPLE_TOOLS = [
  { name: 'Vise-Grip 10" curved-jaw locking pliers', lengthIn: 10, model: { type: 'locking-pliers', variant: 'curved-jaw', colors: { metal: 'chrome' } } },
  { name: 'Irwin 9" lineman pliers', lengthIn: 9, model: { type: 'pliers', variant: 'lineman', colors: { primary: '#1f4fa8', secondary: '#f2c200' } } },
  { name: 'Red diagonal cutters', lengthIn: 8, model: { type: 'pliers', variant: 'diagonal', colors: { primary: '#c8202a' } } },
  { name: '#2 Phillips screwdriver', lengthIn: 8, model: { type: 'screwdriver', variant: 'phillips', colors: { primary: '#c8202a', secondary: '#1d1d1d' } } },
  { name: '10" adjustable wrench', lengthIn: 10, model: { type: 'adjustable-wrench', colors: { primary: '#e05a1a' } } },
  { name: 'Utility knife', lengthIn: 6.5, model: { type: 'utility-knife', variant: 'fixed', colors: { primary: '#d8262c', secondary: '#1d1d1d' } } },
  { name: 'M12 cordless drill', lengthIn: 8, model: { type: 'power-tool', variant: 'drill', colors: { primary: '#c8202a', secondary: '#1d1e20' } } },
  { name: '25 ft tape measure', lengthIn: 3.5, model: { type: 'tape-measure', colors: { primary: '#ffd21a', secondary: '#1d1d1d' } } },
];

/** Builds a tool. model = { type, variant, colors }, lengthIn = real length. Centered at the origin, lying along x. */
export function buildTool(model = {}, lengthIn = 8) {
  const g = new THREE.Group(), inner = new THREE.Group(); g.add(inner);
  const L = clamp(+lengthIn || 8, 0.8, 60);
  (BUILD[model.type] || genericBox)(L, model.variant || '', model.colors || {}, inner);
  const c = new THREE.Box3().setFromObject(inner).getCenter(new THREE.Vector3());
  inner.position.sub(c);
  return g;
}

// ---------------------------------------------------------------------------
// Thumbnails (for the review screen)
// ---------------------------------------------------------------------------
let T = null;
export function toolThumb(model, lengthIn, w = 240, h = 100) {
  if (!T) {
    const r = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
    r.toneMapping = THREE.NeutralToneMapping; r.toneMappingExposure = 0.9;
    const s = new THREE.Scene();
    s.environment = new THREE.PMREMGenerator(r).fromScene(new RoomEnvironment(), 0.04).texture;
    const d = new THREE.DirectionalLight(0xffffff, 1.6); d.position.set(2, 4, 6); s.add(d);
    T = { r, s, cam: new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 500) };
  }
  T.r.setSize(w, h, false);
  const tool = buildTool(model, lengthIn); tool.rotation.set(-0.35, 0.25, 0); T.s.add(tool);
  const b = new THREE.Box3().setFromObject(tool), sz = b.getSize(new THREE.Vector3()), c = b.getCenter(new THREE.Vector3());
  const half = Math.max(sz.x / 2 / (w / h), sz.y / 2) * 1.12;
  Object.assign(T.cam, { left: -half * w / h, right: half * w / h, top: half, bottom: -half });
  T.cam.position.set(c.x, c.y, c.z + 100); T.cam.lookAt(c); T.cam.updateProjectionMatrix();
  T.r.render(T.s, T.cam);
  const url = T.r.domElement.toDataURL('image/png');
  T.s.remove(tool); tool.traverse(o => o.geometry?.dispose());
  return url;
}
