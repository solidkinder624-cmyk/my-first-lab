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
const score = require(join(here, "score.js"));
const rhythm = require(join(here, "rhythm.js"));

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

// 7. シールド: ゲージがMAXになるまでは発動できない
{
  let state = core.createShieldState({ maxUses: 5 });
  check("生成直後は発動不可", core.canActivateShield(state) === false);
  state = core.chargeShield(state, 0.5);
  check("半分チャージでは発動不可", core.canActivateShield(state) === false);
  state = core.chargeShield(state, 0.5);
  check("チャージがMAX(1.0)になると発動可能", core.canActivateShield(state) === true);
  check("チャージは1.0を超えない", state.charge <= 1);
}

// 8. シールド: 発動すると無敵時間に入り、ゲージが消費され、残り回数が減る
{
  let state = core.createShieldState({ maxUses: 5 });
  state = core.chargeShield(state, 1);
  const activated = core.activateShield(state, 1000, 1500);
  check("発動後は残り回数が1減る", activated.usesLeft === 4);
  check("発動後はゲージが0に戻る", activated.charge === 0);
  check("発動直後は無敵状態", core.isShieldActive(activated, 1000) === true);
  check("無敵時間中は無敵状態が続く", core.isShieldActive(activated, 2000) === true);
  check("無敵時間を過ぎると無敵ではない", core.isShieldActive(activated, 2600) === false);
}

// 9. シールド: 発動条件を満たさない場合は何も変えずに返す（例: 未チャージで発動しようとする）
{
  let state = core.createShieldState({ maxUses: 5 });
  const attempted = core.activateShield(state, 1000, 1500);
  check("未チャージでの発動は state を変えない", attempted === state);
}

// 10. シールド: 5回使い切ると、たとえチャージがMAXでも発動できない
{
  let state = core.createShieldState({ maxUses: 5 });
  for (let i = 0; i < 5; i++) {
    state = core.chargeShield(state, 1);
    state = core.activateShield(state, i * 10000, 1500);
  }
  check("5回使い切ると残り回数は0", state.usesLeft === 0);
  state = core.chargeShield(state, 1);
  check("残り回数0だとチャージMAXでも発動不可", core.canActivateShield(state) === false);
  const attempted = core.activateShield(state, 99999, 1500);
  check("残り回数0での発動試行は state を変えない", attempted === state);
}

// 11. 規則性スコア: 弾数の多い壁ほど平均への寄与が大きい(加重平均)
{
  const wallRecords = [
    { regularity: 1.0, bulletCount: 1 },
    { regularity: 0.0, bulletCount: 9 },
  ];
  const s = score.computeRegularityScore(wallRecords);
  check(`加重平均が弾数側(0.0)に寄る (got ${s.toFixed(2)})`, approxEqual(s, 0.1, 0.01));
  check("壁が無ければ規則性1(減点なし)", score.computeRegularityScore([]) === 1);
}

// 12. 密度スコア: 目標占有率に達すると頭打ちで1.0を超えない
{
  const canvasW = 720, canvasH = 480;
  const tiny = score.computeDensityScore(
    [{ bulletCount: 1 }],
    canvasW,
    canvasH,
    { bulletRadius: 6, targetOccupancy: 0.05 }
  );
  const huge = score.computeDensityScore(
    [{ bulletCount: 100000 }],
    canvasW,
    canvasH,
    { bulletRadius: 6, targetOccupancy: 0.05 }
  );
  check("弾が少ないと密度スコアは低い", tiny < 0.1);
  check("弾が過剰でも密度スコアは1.0を超えない", huge === 1);
}

// 13. 継続性スコア: 間隔が目標以内なら1.0、大きく空くと下がる
{
  const dense = score.computeContinuityScore([0, 2000, 4000, 6000], { targetGapMs: 2500 });
  const sparse = score.computeContinuityScore([0, 20000], { targetGapMs: 2500 });
  check(`間隔が目標以内なら継続性1.0 (got ${dense})`, dense === 1);
  check(`大きく間隔が空くと継続性が下がる (got ${sparse.toFixed(2)})`, sparse < 0.5);
  check("壁が1つだけなら継続性1.0(判定材料不足として減点しない)", score.computeContinuityScore([1234]) === 1);
  check("壁が無ければ継続性0", score.computeContinuityScore([]) === 0);
}

// 14. カバレッジ(美しさの下敷き)スコア: 画面全体を使うほど高スコア
{
  const canvasW = 720, canvasH = 480;
  const wide = score.computeCoverageScore(
    [{ points: [{ x: 0, y: 0 }, { x: 720, y: 480 }] }],
    canvasW,
    canvasH
  );
  const narrow = score.computeCoverageScore(
    [{ points: [{ x: 350, y: 240 }, { x: 360, y: 240 }] }],
    canvasW,
    canvasH
  );
  check(`画面全体を使うとカバレッジ1.0に近い (got ${wide.toFixed(2)})`, wide > 0.9);
  check(`狭い範囲だとカバレッジが低い (got ${narrow.toFixed(4)})`, narrow < 0.01);
}

// 15. カスリスコア: 連続カスリはストリークボーナスがつき、被弾でストリークが途切れる
{
  const allGraze = score.computeGrazeScore([
    { type: "graze" }, { type: "graze" }, { type: "graze" },
  ]);
  check("3連続カスリの最大ストリークは3", allGraze.maxStreak === 3);

  const brokenByHit = score.computeGrazeScore([
    { type: "graze" }, { type: "graze" }, { type: "hit" }, { type: "graze" },
  ]);
  check("被弾でストリークがリセットされ、最大は2のまま", brokenByHit.maxStreak === 2);
  check("カスリ総数は被弾を挟んでも3のまま数える", brokenByHit.count === 3);
  check(
    "同じカスリ回数でも連続していた方(ストリークボーナス)がスコアが高い",
    allGraze.score > brokenByHit.score
  );
}

// 16. 被弾(瞬殺)はスコアに加点されない ―
//     企画書「絶対に避けられない壁による瞬殺は評価されない」を満たす
{
  const onlyHits = score.computeGrazeScore([
    { type: "hit" }, { type: "hit" }, { type: "hit" },
  ]);
  check("カスリ無しで被弾だけならスコアは0", onlyHits.score === 0);
}

// 17. computeArtScore: 全体を組み合わせても発散しない(0〜100程度の範囲に収まる)
{
  const result = score.computeArtScore(
    {
      wallRecords: [
        { createdAt: 0, regularity: 0.9, bulletCount: 15, points: [{ x: 100, y: 50 }, { x: 600, y: 400 }] },
        { createdAt: 2000, regularity: 0.95, bulletCount: 18, points: [{ x: 50, y: 300 }, { x: 500, y: 100 }] },
      ],
      events: [{ type: "graze" }, { type: "graze" }, { type: "graze" }],
    },
    { canvasWidth: 720, canvasHeight: 480 }
  );
  check("Grace合計が0〜100の範囲", result.grace.total >= 0 && result.grace.total <= 100);
  check("overallが0〜100の範囲", result.overall >= 0 && result.overall <= 100);
  check("グレイズ内訳が含まれる", result.graze.count === 3);
}

// 18. rhythm: BPM120なら1拍=0.5秒。拍0から0.5秒後は拍1、位相は0に戻る
{
  const clock = rhythm.createClock({ bpm: 120, beatsPerBar: 4, startTime: 0 });
  check("BPM120の1拍は0.5秒", approxEqual(rhythm.beatDuration(clock), 0.5));
  check("0.5秒後は拍インデックス1", rhythm.currentBeatIndex(clock, 0.5) === 1);
  check("拍のちょうど頭では位相0", approxEqual(rhythm.beatPhase(clock, 0.5), 0, 1e-9));
  check("拍の中間(0.25秒進んだ位置)では位相0.5", approxEqual(rhythm.beatPhase(clock, 0.75), 0.5, 1e-9));
}

// 19. rhythm: 小節の頭(ダウンビート)は beatsPerBar 拍ごと
{
  const clock = rhythm.createClock({ bpm: 120, beatsPerBar: 4, startTime: 0 });
  check("拍0は小節の頭", rhythm.isDownbeat(clock, 0));
  check("拍4(次の小節の頭)も小節の頭", rhythm.isDownbeat(clock, 4 * 0.5));
  check("拍1は小節の頭ではない", !rhythm.isDownbeat(clock, 1 * 0.5));
  check("拍2も小節の頭ではない", !rhythm.isDownbeat(clock, 2 * 0.5));
}

// 20. rhythm: nextBeatTime は常に渡した時刻より後になる
{
  const clock = rhythm.createClock({ bpm: 140, beatsPerBar: 4, startTime: 0 });
  const bd = rhythm.beatDuration(clock);
  for (const t of [0, bd - 0.001, bd, bd + 0.001, bd * 3.7]) {
    const next = rhythm.nextBeatTime(clock, t);
    check(`nextBeatTime(${t.toFixed(3)}) > ${t.toFixed(3)}`, next > t);
    check(`nextBeatTime(${t.toFixed(3)}) は拍の境界上`, approxEqual(rhythm.beatPhase(clock, next), 0, 1e-6) || approxEqual(rhythm.beatPhase(clock, next), 1, 1e-6));
  }
}

// 21. rhythm: syncAccuracy は拍のジャストタイミングで1、オフビート(位相0.5)で0
{
  const clock = rhythm.createClock({ bpm: 100, beatsPerBar: 4, startTime: 0 });
  const bd = rhythm.beatDuration(clock);
  check("拍ジャストでシンクロ度1.0", approxEqual(rhythm.syncAccuracy(clock, bd * 2), 1, 1e-9));
  check("完全オフビートでシンクロ度0.0", approxEqual(rhythm.syncAccuracy(clock, bd * 2.5), 0, 1e-9));
  const near = rhythm.syncAccuracy(clock, bd * 2 + 0.01);
  check(`拍に近いほどシンクロ度が高い (got ${near.toFixed(3)})`, near > 0.9 && near < 1);
}

// 22. rhythm: nearestBeatTime は前後どちらの拍にも丸められる
{
  const clock = rhythm.createClock({ bpm: 120, beatsPerBar: 4, startTime: 0 });
  const bd = rhythm.beatDuration(clock);
  check("わずかに進んだ時刻は直前の拍に丸められる", approxEqual(rhythm.nearestBeatTime(clock, bd * 2 + 0.01), bd * 2));
  check("わずかに手前の時刻は直後の拍に丸められる", approxEqual(rhythm.nearestBeatTime(clock, bd * 3 - 0.01), bd * 3));
}

// 23. スコア: シンクロ率はサンプルの平均。データが無ければ0(他項目と同様に未達成扱い)
{
  check("サンプル無しならシンクロスコア0", score.computeSyncScore([]) === 0);
  check("サンプル無しならシンクロスコア0(undefined)", score.computeSyncScore(undefined) === 0);
  const s = score.computeSyncScore([1, 0.5, 0]);
  check(`平均値になる (got ${s.toFixed(3)})`, approxEqual(s, 0.5));
}

// 24. computeArtScore: シンクロ率が Grace の内訳に含まれ、サンプルが良いほどGraceが上がる
{
  const base = {
    wallRecords: [{ createdAt: 0, regularity: 0.8, bulletCount: 10, points: [{ x: 0, y: 0 }, { x: 100, y: 100 }] }],
    events: [],
  };
  const withoutSync = score.computeArtScore(base, { canvasWidth: 720, canvasHeight: 480 });
  const withGoodSync = score.computeArtScore(
    Object.assign({}, base, { syncSamples: [1, 1, 1] }),
    { canvasWidth: 720, canvasHeight: 480 }
  );
  check("グレース内訳にsyncが含まれる", typeof withoutSync.grace.sync === "number");
  check("シンクロ良好だとGrace合計が上がる", withGoodSync.grace.total > withoutSync.grace.total);
}

console.log("");
if (failures > 0) {
  console.error(`${failures} 件失敗`);
  process.exit(1);
} else {
  console.log("全チェック通過");
}
