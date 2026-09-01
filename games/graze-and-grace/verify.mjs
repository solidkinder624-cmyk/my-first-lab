/*
 * core.js（スワイプ→弾幕の壁 生成ロジック）が満たすべき性質を検証する。
 *
 *   node games/graze-and-grace/verify.mjs
 *
 * DOM に依存しない純関数だけを対象にしているので、ブラウザなしで実行できる。
 */
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const core = require(join(here, "core.js"));

let failures = 0;
function check(name, cond) {
  if (cond) {
    console.log(`OK   ${name}`);
  } else {
    console.error(`FAIL ${name}`);
    failures++;
  }
}

function approxEqual(a, b, eps = 1e-6) {
  return Math.abs(a - b) <= eps;
}

// 1. 直線を等間隔でリサンプルすると、区間長どおりの点数になる
{
  const points = [
    { x: 0, y: 0 },
    { x: 100, y: 0 },
  ];
  const resampled = core.resamplePathEven(points, 10);
  check(
    "直線100pxを間隔10pxでリサンプルすると11点前後になる",
    resampled.length >= 10 && resampled.length <= 12
  );
  for (let i = 1; i < resampled.length - 1; i++) {
    const gap = core.dist(resampled[i - 1], resampled[i]);
    check(`区間[${i}]の間隔が10pxに近い (${gap.toFixed(2)})`, approxEqual(gap, 10, 0.5));
  }
}

// 2. 折れ線（L字）でも間隔が一定に保たれる（角で弾が詰まったり飛んだりしない）
{
  const points = [
    { x: 0, y: 0 },
    { x: 60, y: 0 },
    { x: 60, y: 60 },
  ];
  const resampled = core.resamplePathEven(points, 12);
  let maxGap = 0;
  let minGap = Infinity;
  for (let i = 1; i < resampled.length; i++) {
    const gap = core.dist(resampled[i - 1], resampled[i]);
    maxGap = Math.max(maxGap, gap);
    minGap = Math.min(minGap, gap);
  }
  check(
    `L字経路でも間隔のブレが小さい (min=${minGap.toFixed(2)}, max=${maxGap.toFixed(2)})`,
    maxGap - minGap < 12
  );
}

// 3. 押し出し方向は単位ベクトルで、スワイプの向きと直交する
{
  const points = [
    { x: -50, y: 0 },
    { x: 50, y: 0 },
  ];
  const pushDir = core.choosePushDirection(points, { x: 0, y: 100 });
  const len = Math.hypot(pushDir.x, pushDir.y);
  check("pushDir が単位ベクトル", approxEqual(len, 1, 1e-4));
  check("水平スワイプの押し出し方向は垂直 (x成分がほぼ0)", approxEqual(pushDir.x, 0, 1e-4));
  check("中心が下側にあるとき、下方向(+y)へ押し出す", pushDir.y > 0);
}

// 4. buildBulletWall: 弾がスワイプ順に遅延して出現する(waveDelayMs)
{
  const points = [
    { x: 0, y: 0 },
    { x: 200, y: 0 },
  ];
  const { bullets } = core.buildBulletWall(points, {
    spacing: 20,
    waveDelayMs: 10,
    center: { x: 0, y: 100 },
  });
  check("弾が複数生成される", bullets.length >= 8);
  let increasing = true;
  for (let i = 1; i < bullets.length; i++) {
    if (bullets[i].spawnDelayMs < bullets[i - 1].spawnDelayMs) increasing = false;
  }
  check("spawnDelayMs がスワイプ順に単調増加する", increasing);
}

// 5. advanceBullet: 予告時間中は静止し、その後は一定速度で直進する
{
  const { bullets } = core.buildBulletWall(
    [
      { x: 0, y: 0 },
      { x: 40, y: 0 },
    ],
    { spacing: 40, bulletSpeed: 100, telegraphMs: 500, waveDelayMs: 0, center: { x: 0, y: 100 } }
  );
  const bullet = bullets[0];
  const duringTelegraph = core.advanceBullet(bullet, 100, 1 / 60);
  check("予告時間中は原点に留まる", approxEqual(duringTelegraph.x, bullet.originX) && approxEqual(duringTelegraph.y, bullet.originY));

  let moving = core.advanceBullet(bullet, 500, 1 / 60);
  check("予告時間を過ぎると動き出す", moving.launched === true);
  const before = { x: moving.x, y: moving.y };
  moving = core.advanceBullet(moving, 500 + 1000 / 60, 1 / 60);
  const moved = core.dist(before, moving) > 0;
  check("動き出した弾は毎フレーム位置が変わる", moved);
}

// 6. 出現前の弾は visible=false（描画側が誤って表示しないようにするための契約）
{
  const { bullets } = core.buildBulletWall(
    [
      { x: 0, y: 0 },
      { x: 100, y: 0 },
    ],
    { spacing: 20, waveDelayMs: 50, center: { x: 0, y: 100 } }
  );
  const lastBullet = bullets[bullets.length - 1];
  const tooEarly = core.advanceBullet(lastBullet, 0, 1 / 60);
  check("出現時刻より前は visible=false", tooEarly.visible === false);
}

console.log("");
if (failures > 0) {
  console.error(`${failures} 件失敗`);
  process.exit(1);
} else {
  console.log("全チェック通過");
}
