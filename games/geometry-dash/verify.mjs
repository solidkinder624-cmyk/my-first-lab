/*
 * レベルがクリア可能かを検証するツール。
 *
 *   node games/geometry-dash/verify.mjs
 *
 * index.html の CORE-BEGIN / CORE-END で囲まれた純粋ロジックだけを取り出し、
 * 「毎フレーム押す / 押さない」をビームサーチで探索して、ゴールまで到達できる
 * 入力列が存在するかを確かめる。ゲーム本体と同じ物理をそのまま使うので、
 * 「作ったけど実は絶対にクリアできない配置だった」を防げる。
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
  return { T, C, buildLevel, createPlayer, clonePlayer, stepPhysics, decisionMatters };
`)();

const { T, C, buildLevel, createPlayer, clonePlayer, stepPhysics, decisionMatters } = api;

const DT        = 1 / 120;
const BEAM      = Number(process.env.BEAM || 900);
const GRID       = Number(process.env.GRID || 1);   // キューブの入力を何フレーム刻みに制限するか
const SHIP_EVERY = Number(process.env.SHIP || 3);    // 宇宙船モードの操作間隔
const MAX_STEPS = 60 * 120;        // 60秒ぶん

const L = buildLevel();
let states = [Object.assign(createPlayer(), { hold: false })];
let bestX = -Infinity, won = null, deaths = { wall: 0, spike: 0 };

for (let step = 0; step < MAX_STEPS && states.length; step++) {
  const next = [];
  const seen = new Set();
  for (const s of states) {
    let choices;
    if (s.mode === 'ship') choices = (step % SHIP_EVERY === 0) ? [true, false] : [s.hold];
    else if (step % GRID !== 0) choices = [s.hold];
    else choices = decisionMatters(s, L) ? [true, false] : [false];

    for (const h of choices) {
      const q = clonePlayer(s);
      stepPhysics(q, L, DT, h);
      q.hold = h;
      if (q.x > bestX) bestX = q.x;
      if (q.dead) { deaths[q.deathKind] = (deaths[q.deathKind] || 0) + 1; continue; }
      if (q.won) { won = q; break; }
      const key = q.mode + q.gdir + '|' + Math.round(q.y / 5) + '|' + Math.round(q.vy / 35) +
                  '|' + (q.mode === 'ship' ? (h ? 1 : 0) : 0) + '|' + (q.onGround ? 1 : 0);
      if (seen.has(key)) continue;
      seen.add(key);
      next.push(q);
    }
    if (won) break;
  }
  if (won) break;

  if (next.length > BEAM) {                    // 高さがばらけるように間引く
    next.sort((p, q) => p.y - q.y);
    const keep = [];
    for (let i = 0; i < BEAM; i++) keep.push(next[Math.floor(i * next.length / BEAM)]);
    states = keep;
  } else {
    states = next;
  }
}

const pct = (x) => Math.max(0, Math.min(100, (x / L.length) * 100));
console.log(`level : ${L.name}  (${(L.length / T).toFixed(0)} タイル / 約 ${(L.length / C.SPEED).toFixed(1)} 秒)`);
console.log(`blocks=${L.blocks.length} spikes=${L.spikes.length} items=${L.items.length}`);
console.log(`到達率: ${pct(bestX).toFixed(1)}%   (壁 ${deaths.wall || 0} / トゲ ${deaths.spike || 0} 回の分岐が死亡)`);

if (won) {
  console.log(`\x1b[32mOK: クリア可能な入力列が見つかりました (${won.t.toFixed(2)} 秒)\x1b[0m`);
  process.exit(0);
} else {
  console.log(`\x1b[31mNG: ゴールに到達できません。${(bestX / T).toFixed(1)} タイル付近の配置を見直してください\x1b[0m`);
  process.exit(1);
}
