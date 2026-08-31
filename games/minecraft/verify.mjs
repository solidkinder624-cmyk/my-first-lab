/*
 * ワールドと物理の自動検証ツール。
 *
 *   node games/minecraft/verify.mjs
 *
 * index.html の CORE-BEGIN / CORE-END で囲まれた純粋ロジック（ゲーム本体と
 * まったく同じコード）だけを取り出し、Node 上で走らせて
 *   ・同じシードなら必ず同じ地形になるか（チャンクの生成順に依存しないか）
 *   ・スポーン地点が本当に立てる場所か
 *   ・落下・歩行でブロックをすり抜けないか
 *   ・レイキャストが総当たり計算と一致するか
 *   ・セーブ / ロードでブロックの改変が復元できるか
 * を確かめる。ブラウザを開かずに「壊れた世界」を検出するのが目的。
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(here, 'index.html'), 'utf8');

const a = html.indexOf('CORE-BEGIN'), b = html.lastIndexOf('CORE-END');
if (a < 0 || b < 0) { console.error('CORE-BEGIN / CORE-END が見つかりません'); process.exit(2); }
const core = html.slice(html.indexOf('*/', a) + 2, html.lastIndexOf('/*', b));

const api = new Function(core + `
  return { CX, CY, CZ, SEA, B, BLOCKS, PW, PH, EYE, idx, ckey, isSolid, isOpaque, isSelectable,
           createWorld, getChunk, getBlock, setBlock, surfaceHeight, groundY, findSpawn,
           createPlayer, stepPlayer, moveAxis, raycast, canPlace, saveData, loadData,
           editCount, skyLight, topAt };
`)();

const { CX, CY, CZ, SEA, B, BLOCKS, PW, PH, EYE, isSolid, createWorld, getChunk, getBlock,
        setBlock, surfaceHeight, groundY, findSpawn, createPlayer, stepPlayer, raycast,
        canPlace, saveData, loadData, editCount } = api;

// ---- ちいさなテストランナー ----
let failed = 0, passed = 0;
const t0 = Date.now();
function check(name, fn){
  let msg = null;
  try { msg = fn(); } catch (e) { msg = (e && e.stack) ? e.stack.split('\n').slice(0, 3).join(' / ') : String(e); }
  if (msg){ failed++; console.log(`\x1b[31mNG\x1b[0m  ${name}\n      ${msg}`); }
  else    { passed++; console.log(`\x1b[32mOK\x1b[0m  ${name}`); }
}
// 決定的な擬似乱数（テスト自体を再現可能にする）
function rng(seed){
  let s = seed >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
}
const DT = 1 / 120;
const insideSolid = (w, p) => {           // AABB を少し縮めて「めり込み」を判定
  const hw = PW / 2 - 0.02;
  for (let x = Math.floor(p.x - hw); x <= Math.floor(p.x + hw); x++)
    for (let y = Math.floor(p.y + 0.02); y <= Math.floor(p.y + PH - 0.02); y++)
      for (let z = Math.floor(p.z - hw); z <= Math.floor(p.z + hw); z++)
        if (isSolid(getBlock(w, x, y, z))) return `(${x},${y},${z}) にめり込み`;
  return null;
};

// ---- 1. 同じシードなら同じ地形 ----
check('同じシードのワールドは完全に一致する', () => {
  const w1 = createWorld(20260831), w2 = createWorld(20260831), r = rng(7);
  for (let i = 0; i < 4000; i++){
    const x = Math.floor((r() - 0.5) * 400), y = Math.floor(r() * CY), z = Math.floor((r() - 0.5) * 400);
    if (getBlock(w1, x, y, z) !== getBlock(w2, x, y, z)) return `(${x},${y},${z}) が食い違う`;
  }
  return null;
});

check('シードが違えば地形も変わる', () => {
  const w1 = createWorld(1), w2 = createWorld(2);
  let diff = 0;
  for (let x = 0; x < 60; x++) for (let z = 0; z < 60; z++)
    if (surfaceHeight(w1.seed, x, z) !== surfaceHeight(w2.seed, x, z)) diff++;
  return diff > 100 ? null : `高さの違いが ${diff} 箇所しかない`;
});

// ---- 2. チャンクの生成順に依存しない（木がチャンクをまたぐため重要） ----
check('チャンクの生成順を変えても結果が同じ', () => {
  const w1 = createWorld(4242), w2 = createWorld(4242);
  const order = [];
  for (let cx = -2; cx <= 2; cx++) for (let cz = -2; cz <= 2; cz++) order.push([cx, cz]);
  for (const c of order) getChunk(w1, c[0], c[1]);
  for (const c of order.slice().reverse()) getChunk(w2, c[0], c[1]);
  for (const c of order){
    const A = getChunk(w1, c[0], c[1]).blocks, C = getChunk(w2, c[0], c[1]).blocks;
    for (let i = 0; i < A.length; i++)
      if (A[i] !== C[i]) return `チャンク(${c[0]},${c[1]}) の ${i} 番目が違う`;
  }
  return null;
});

// ---- 3. 地形の健全性 ----
check('地形が仕様の範囲に収まっている（岩盤・海面・高さ）', () => {
  const w = createWorld(555);
  for (let x = -40; x < 40; x += 3) for (let z = -40; z < 40; z += 3){
    if (getBlock(w, x, 0, z) !== B.BEDROCK) return `(${x},0,${z}) が岩盤でない`;
    const h = surfaceHeight(w.seed, x, z);
    if (h < 3 || h > CY - 14) return `高さ ${h} が範囲外`;
    if (h < SEA && getBlock(w, x, SEA, z) !== B.WATER) return `(${x},${z}) の海面が水でない`;
    for (let y = SEA + 1; y < CY; y++)
      if (getBlock(w, x, y, z) === B.WATER) return `(${x},${y},${z}) 海面より上に水がある`;
  }
  return null;
});

// ---- 4. スポーン地点 ----
check('スポーン地点は地面の上で、頭上に空間がある', () => {
  for (const seed of [1, 2, 7, 99, 1234, 20260831, 424242, 8080]){
    const w = createWorld(seed), p = createPlayer(w);
    const fx = Math.floor(p.x), fy = Math.floor(p.y), fz = Math.floor(p.z);
    if (!isSolid(getBlock(w, fx, fy - 1, fz))) return `seed=${seed}: 足元が空中`;
    if (getBlock(w, fx, fy, fz) !== B.AIR || getBlock(w, fx, fy + 1, fz) !== B.AIR)
      return `seed=${seed}: 頭上が埋まっている`;
    const bad = insideSolid(w, p);
    if (bad) return `seed=${seed}: ${bad}`;
  }
  return null;
});

// ---- 5. 落下してもすり抜けない ----
check('空中から落下しても必ず着地し、地面をすり抜けない', () => {
  const w = createWorld(31337), r = rng(11);
  for (let i = 0; i < 60; i++){
    const p = createPlayer(w);
    p.x = Math.floor((r() - 0.5) * 300) + 0.5;
    p.z = Math.floor((r() - 0.5) * 300) + 0.5;
    p.y = CY - 2; p.vx = p.vy = p.vz = 0; p.flying = false;
    const inp = { mf: 0, mr: 0, jump: false, sneak: false, sprint: false };
    for (let s = 0; s < 120 * 12; s++){
      stepPlayer(w, p, inp, DT);
      if (p.y < -8.5) return `(${p.x},${p.z}) で世界の底を抜けた`;
    }
    if (!p.onGround && !p.inWater) return `(${p.x.toFixed(1)},${p.z.toFixed(1)}) で 12 秒たっても着地しない (y=${p.y.toFixed(2)})`;
    const bad = insideSolid(w, p);
    if (bad) return `落下後に ${bad}`;
  }
  return null;
});

// ---- 6. 走り回ってもブロックをすり抜けない ----
check('走り + ジャンプを続けてもブロックをすり抜けない', () => {
  for (const seed of [5, 77, 909, 20260831]){
    const w = createWorld(seed), p = createPlayer(w), r = rng(seed);
    for (let s = 0; s < 120 * 25; s++){
      if (s % 90 === 0) p.yaw = r() * Math.PI * 2;
      const inp = { mf: 1, mr: 0, jump: (s % 45) < 4, sneak: false, sprint: true };
      stepPlayer(w, p, inp, DT);
      if (p.y < -8.5 || p.y > CY + 2) return `seed=${seed}: y=${p.y.toFixed(2)} に飛び出した`;
      const bad = insideSolid(w, p);
      if (bad) return `seed=${seed}: ${s} フレーム目で ${bad}`;
    }
  }
  return null;
});

// ---- 7. 飛行から着地しても埋まらない ----
check('飛行モードで地中に潜ってから解除しても押し出される', () => {
  const w = createWorld(2024), p = createPlayer(w);
  p.flying = true;
  const down = { mf: 1, mr: 0, jump: false, sneak: true, sprint: false };
  for (let s = 0; s < 120 * 6; s++) stepPlayer(w, p, down, DT);
  p.flying = false;
  const idle = { mf: 0, mr: 0, jump: false, sneak: false, sprint: false };
  for (let s = 0; s < 120 * 4; s++) stepPlayer(w, p, idle, DT);
  return insideSolid(w, p);
});

// ---- 8. レイキャストが総当たりと一致 ----
check('レイキャストが総当たり計算と一致する', () => {
  const w = createWorld(8181), r = rng(3);
  for (let i = 0; i < 1200; i++){
    const ox = (r() - 0.5) * 120, oz = (r() - 0.5) * 120;
    const oy = 5 + r() * (CY - 10);
    if (api.isSelectable(getBlock(w, ox, oy, oz))) continue;      // 始点が壁の中なら飛ばす
    const th = r() * Math.PI * 2, ph = (r() - 0.5) * Math.PI;
    const dx = Math.cos(ph) * Math.cos(th), dy = Math.sin(ph), dz = Math.cos(ph) * Math.sin(th);
    const MAX = 8;
    const hit = raycast(w, ox, oy, oz, dx, dy, dz, MAX);
    let brute = null;                                             // 細かく刻んで最初に当たる格子を探す
    for (let t = 0; t <= MAX; t += 0.002){
      const x = Math.floor(ox + dx * t), y = Math.floor(oy + dy * t), z = Math.floor(oz + dz * t);
      if (api.isSelectable(getBlock(w, x, y, z))){ brute = { x, y, z, t }; break; }
    }
    if (!hit && !brute) continue;
    if (!hit || !brute) return `どちらか一方しか当たらない (${ox.toFixed(2)},${oy.toFixed(2)},${oz.toFixed(2)})`;
    if (hit.x !== brute.x || hit.y !== brute.y || hit.z !== brute.z)
      return `当たるブロックが違う DDA(${hit.x},${hit.y},${hit.z}) vs 総当たり(${brute.x},${brute.y},${brute.z})`;
    const px = hit.x + hit.nx, py = hit.y + hit.ny, pz = hit.z + hit.nz;
    if (api.isSelectable(getBlock(w, px, py, pz)))
      return `法線の先(${px},${py},${pz})が空でない＝設置できない面を返した`;
  }
  return null;
});

// ---- 9. 掘る / 置く ----
check('掘った跡は空気になり、自分の中にはブロックを置けない', () => {
  const w = createWorld(606), p = createPlayer(w);
  const bx = Math.floor(p.x), by = Math.floor(p.y) - 1, bz = Math.floor(p.z);
  setBlock(w, bx, by, bz, B.AIR);
  if (getBlock(w, bx, by, bz) !== B.AIR) return '掘っても空気にならない';
  if (canPlace(w, p, Math.floor(p.x), Math.floor(p.y), Math.floor(p.z)))
    return '自分の足元（体の中）に置けてしまう';
  if (!canPlace(w, p, bx, by, bz)) return '掘った跡に置き直せない';
  if (setBlock(w, bx, by, bz, B.BEDROCK) !== true) return '設置が失敗した';
  return null;
});

// ---- 10. セーブ / ロード ----
check('セーブ→ロードでブロックの改変が完全に復元される', () => {
  const w = createWorld(90210), p = createPlayer(w), r = rng(21);
  const log = [];
  for (let i = 0; i < 300; i++){
    const x = Math.floor(p.x) + Math.floor((r() - 0.5) * 40);
    const z = Math.floor(p.z) + Math.floor((r() - 0.5) * 40);
    const y = 1 + Math.floor(r() * (CY - 2));
    const id = [B.AIR, B.STONE, B.PLANK, B.GLASS, B.LAMP][Math.floor(r() * 5)];
    setBlock(w, x, y, z, id); log.push([x, y, z, id]);
  }
  const json = JSON.parse(JSON.stringify(saveData(w, p)));
  const w2 = loadData(json);
  if (w2.seed !== w.seed) return 'シードが復元されない';
  for (const e of log)
    if (getBlock(w2, e[0], e[1], e[2]) !== e[3])
      return `(${e[0]},${e[1]},${e[2]}) が ${getBlock(w2, e[0], e[1], e[2])} で復元された（期待 ${e[3]}）`;
  if (editCount(w2) !== editCount(w)) return '差分の数が合わない';
  return null;
});

// ---- 11. 空が見える高さ（明るさ計算）の整合 ----
check('スカイライトが地表で最大・地中で減衰する', () => {
  const w = createWorld(3141);
  for (let x = -20; x < 20; x += 5) for (let z = -20; z < 20; z += 5){
    const h = api.topAt(w, x, z);
    if (api.skyLight(w, x, h, z) !== 1) return `(${x},${z}) 地表が最大の明るさでない`;
    if (h > 12 && api.skyLight(w, x, h - 10, z) >= 1) return `(${x},${z}) 地中が明るいまま`;
  }
  return null;
});

// ---- まとめ ----
const w = createWorld(20260831);
const p = createPlayer(w);
console.log(`\nシード 20260831 のスポーン: (${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)})  ` +
            `／ 生成済みチャンク ${w.chunks.size}  ／ ブロック種 ${BLOCKS.filter(Boolean).length}`);
console.log(`${passed + failed} 項目中 ${passed} 成功 / ${failed} 失敗  (${((Date.now() - t0) / 1000).toFixed(1)} 秒)`);
if (failed){ console.log('\x1b[31mNG: 上の項目を直してください\x1b[0m'); process.exit(1); }
console.log('\x1b[32mOK: ワールドと物理はすべて期待どおりに動いています\x1b[0m');
