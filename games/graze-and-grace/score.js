// GRAZE & GRACE - Phase 3: Grace & Graze 評価システム（芸術点）
//
// 企画書 2.1 のうち、音楽同期を前提としない4項目を実装する:
//   規則性 / 美しさ(画面の使い方) / 密度 / 継続性
// 「シンクロ率」は BGM の展開情報が要る (企画書2.1・Phase4) ため、ここでは扱わない。
// Grace の重み付けは Phase4 でシンクロ率を追加する際に見直す前提の均等割り。
//
// Graze（カスリ）側は「連続カスリ回数」を評価する。被弾(hit)はスコアに加点せず
// 連続カスリのストリークをリセットするだけなので、企画書の
// 「絶対に避けられない壁による瞬殺は評価されない」は自然に満たされる
// （瞬殺=被弾はそもそも加点対象ではない）。
//
// DOM に一切依存しない純関数群。core.js と同じ形で window.GrazeScore /
// module.exports に生える。

(function (root) {
  "use strict";

  // 1. 規則性: 壁ごとの regularity (core.js の estimateRegularity) を
  //    弾数で重み付け平均したもの。弾数が多い壁ほどスコアへの寄与を大きくする。
  function computeRegularityScore(wallRecords) {
    if (!wallRecords || wallRecords.length === 0) return 1;
    let weightedSum = 0;
    let totalWeight = 0;
    wallRecords.forEach((w) => {
      const weight = Math.max(1, w.bulletCount);
      weightedSum += w.regularity * weight;
      totalWeight += weight;
    });
    return totalWeight > 0 ? weightedSum / totalWeight : 1;
  }

  // 2. 密度: 壁1つあたりの「弾が占める面積 / 画面面積」を、目標占有率で正規化する。
  //    目標占有率に達したら頭打ち(1.0)にして、弾を無限に増やせば勝てる状態を避ける。
  function computeDensityScore(wallRecords, canvasWidth, canvasHeight, opts) {
    const o = Object.assign({ bulletRadius: 6, targetOccupancy: 0.05 }, opts || {});
    if (!wallRecords || wallRecords.length === 0) return 0;
    const canvasArea = canvasWidth * canvasHeight;
    const bulletArea = Math.PI * o.bulletRadius * o.bulletRadius;
    let sum = 0;
    wallRecords.forEach((w) => {
      const occupied = (w.bulletCount * bulletArea) / canvasArea;
      sum += Math.min(1, occupied / o.targetOccupancy);
    });
    return sum / wallRecords.length;
  }

  // 3. 継続性: 壁と壁の間隔が目標間隔(targetGapMs)を超えるほど減点する。
  //    弾幕の波が長く途切れないほど高スコアになる。
  function computeContinuityScore(wallTimestampsMs, opts) {
    const o = Object.assign({ targetGapMs: 2500 }, opts || {});
    if (!wallTimestampsMs || wallTimestampsMs.length === 0) return 0;
    if (wallTimestampsMs.length === 1) return 1;

    const sorted = wallTimestampsMs.slice().sort((a, b) => a - b);
    let overagePenaltySum = 0;
    for (let i = 1; i < sorted.length; i++) {
      const gap = sorted[i] - sorted[i - 1];
      const overage = Math.max(0, gap - o.targetGapMs) / o.targetGapMs;
      overagePenaltySum += Math.min(1, overage);
    }
    const avgPenalty = overagePenaltySum / (sorted.length - 1);
    return Math.max(0, 1 - avgPenalty);
  }

  // 4. 美しさ(画面の使い方の下敷き): 壁が画面のどれだけ広い範囲を使っているかを
  //    バウンディングボックスの面積比で概算する。1点に固まった壁ばかりだと低スコア。
  function computeCoverageScore(wallRecords, canvasWidth, canvasHeight) {
    if (!wallRecords || wallRecords.length === 0) return 0;
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    wallRecords.forEach((w) => {
      (w.points || []).forEach((p) => {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      });
    });
    if (minX > maxX || minY > maxY) return 0;
    const w = Math.max(1, maxX - minX);
    const h = Math.max(1, maxY - minY);
    return Math.min(1, (w * h) / (canvasWidth * canvasHeight));
  }

  // Graze: イベント列(出現順)から連続カスリ数と得点を計算する。
  // events: [{type: "graze"} | {type: "hit"}, ...] (時系列順)
  function computeGrazeScore(events, opts) {
    const o = Object.assign({ perGraze: 10, streakBonus: 15 }, opts || {});
    let count = 0;
    let streak = 0;
    let maxStreak = 0;
    let base = 0;
    (events || []).forEach((e) => {
      if (e.type === "graze") {
        count++;
        streak++;
        maxStreak = Math.max(maxStreak, streak);
        base += o.perGraze;
      } else if (e.type === "hit") {
        streak = 0;
      }
    });
    return { count, maxStreak, score: base + maxStreak * o.streakBonus };
  }

  /**
   * セッション全体の芸術点(Grace & Graze)を算出する。
   *
   * @param {object} session
   * @param {{createdAt:number, regularity:number, bulletCount:number, points:{x,y}[]}[]} session.wallRecords
   *   スワイプのたびに記録する壁の履歴(ゲームプレイ用の walls とは別に、消えても残す)
   * @param {{type:"graze"|"hit"}[]} session.events 時系列順のカスリ/被弾イベント
   * @param {object} opts 画面サイズ等
   * @returns {{grace: object, graze: object, overall: number}}
   */
  function computeArtScore(session, opts) {
    const o = Object.assign({ canvasWidth: 720, canvasHeight: 480 }, opts || {});
    const wallRecords = (session && session.wallRecords) || [];
    const wallTimestamps = wallRecords.map((w) => w.createdAt);

    const grace = {
      regularity: computeRegularityScore(wallRecords),
      density: computeDensityScore(wallRecords, o.canvasWidth, o.canvasHeight),
      continuity: computeContinuityScore(wallTimestamps),
      coverage: computeCoverageScore(wallRecords, o.canvasWidth, o.canvasHeight),
    };
    const graceTotal =
      ((grace.regularity + grace.density + grace.continuity + grace.coverage) / 4) * 100;

    const grazeResult = computeGrazeScore((session && session.events) || []);
    const overall = (graceTotal + Math.min(100, grazeResult.score)) / 2;

    return {
      grace: Object.assign({}, grace, { total: graceTotal }),
      graze: grazeResult,
      overall,
    };
  }

  const api = {
    computeRegularityScore,
    computeDensityScore,
    computeContinuityScore,
    computeCoverageScore,
    computeGrazeScore,
    computeArtScore,
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else {
    root.GrazeScore = api;
  }
})(typeof window !== "undefined" ? window : globalThis);
