// GRAZE & GRACE - Phase 1: スワイプによる弾幕の壁 生成ロジック
//
// DOM/描画に一切依存しない純関数群。ブラウザでは <script> で読み込むと
// window.GrazeCore に生える。Node (verify.mjs) では module.exports から使う。
//
// 責務は「スワイプの軌跡（点列）」→「壁を構成する弾のリスト」への変換だけ。
// 見た目・入力・当たり判定はすべて index.html 側（呼び出し側）に置く。

(function (root) {
  "use strict";

  function dist(a, b) {
    return Math.hypot(b.x - a.x, b.y - a.y);
  }

  function normalize(v) {
    const len = Math.hypot(v.x, v.y);
    if (len < 1e-6) return { x: 0, y: 0 };
    return { x: v.x / len, y: v.y / len };
  }

  // 生のスワイプ点列（マウス/タッチのサンプリングで間隔がバラバラ）を、
  // 弧長ベースで等間隔の点列に変換する。
  // これが Grace 評価軸のうち「規則性」の土台になる: 壁を構成する弾同士の
  // 間隔が揃っていないと、幾何学的に美しい壁にならない。
  function resamplePathEven(points, spacing) {
    if (!Array.isArray(points) || points.length === 0) return [];
    if (points.length === 1) return [{ x: points[0].x, y: points[0].y }];
    if (spacing <= 0) throw new Error("spacing must be > 0");

    const result = [points[0]];
    // carry: 直前に打った点から、このセグメントの始点(prev)までに
    // 「既に進んでしまっている」距離(0以上spacing未満)。次に点を打つまでに
    // 進むべき距離は (spacing - carry) になる。
    let carry = 0;
    let prev = points[0];

    for (let i = 1; i < points.length; i++) {
      const cur = points[i];
      const segLen = dist(prev, cur);
      if (segLen < 1e-9) {
        prev = cur;
        continue;
      }
      const dir = normalize({ x: cur.x - prev.x, y: cur.y - prev.y });
      let cursor = { x: prev.x, y: prev.y };
      let remaining = segLen;
      let need = spacing - carry;

      while (need <= remaining) {
        cursor = { x: cursor.x + dir.x * need, y: cursor.y + dir.y * need };
        result.push({ x: cursor.x, y: cursor.y });
        remaining -= need;
        need = spacing;
      }
      carry = remaining; // 次のセグメントへ繰り越す「進みすぎ分」
      prev = cur;
    }

    // 終点をきれいに拾えていない場合は最後の点を足す（壁の端が途切れないように）
    const last = result[result.length - 1];
    const finalPoint = points[points.length - 1];
    if (dist(last, finalPoint) > spacing * 0.5) {
      result.push({ x: finalPoint.x, y: finalPoint.y });
    }
    return result;
  }

  // スワイプ全体の向きに対して、キャンバス中心により近づく方の法線を選ぶ。
  // = 「壁が勇者側(画面中央)に向かって迫ってくる」自然な押し出し方向。
  function choosePushDirection(points, center) {
    if (points.length < 2) return { x: 0, y: 1 };
    const first = points[0];
    const last = points[points.length - 1];
    const tangent = normalize({ x: last.x - first.x, y: last.y - first.y });
    if (tangent.x === 0 && tangent.y === 0) return { x: 0, y: 1 };

    const normalA = { x: -tangent.y, y: tangent.x };
    const normalB = { x: tangent.y, y: -tangent.x };
    const mid = { x: (first.x + last.x) / 2, y: (first.y + last.y) / 2 };
    const toCenter = { x: center.x - mid.x, y: center.y - mid.y };

    const dotA = normalA.x * toCenter.x + normalA.y * toCenter.y;
    const dotB = normalB.x * toCenter.x + normalB.y * toCenter.y;
    return dotA >= dotB ? normalA : normalB;
  }

  // 弧長に沿った間隔の標準偏差から「規則性」を 0..1 で概算する
  // (企画書 2.1 Grace/規則性 の最小限の下敷き。厳密なスコアリングは Phase 3)
  function estimateRegularity(resampled) {
    if (resampled.length < 3) return 1;
    const gaps = [];
    for (let i = 1; i < resampled.length; i++) {
      gaps.push(dist(resampled[i - 1], resampled[i]));
    }
    const mean = gaps.reduce((a, b) => a + b, 0) / gaps.length;
    if (mean < 1e-6) return 1;
    const variance =
      gaps.reduce((a, g) => a + (g - mean) * (g - mean), 0) / gaps.length;
    const stdev = Math.sqrt(variance);
    const coefficientOfVariation = stdev / mean;
    return Math.max(0, 1 - coefficientOfVariation);
  }

  /**
   * スワイプの点列から「弾幕の壁」を生成する。
   *
   * @param {{x:number,y:number}[]} points 生のスワイプ点列（2点以上）
   * @param {object} opts
   * @param {number} opts.spacing        壁を構成する弾同士の間隔(px) 既定 24
   * @param {number} opts.bulletSpeed    発射後の弾速(px/秒) 既定 220
   * @param {number} opts.telegraphMs    描画完了後、弾が動き出すまでの予告時間(ms) 既定 550
   * @param {number} opts.waveDelayMs    隣接する弾が出現するまでの遅延(ms)。
   *                                     スワイプした順に壁が「描かれていく」演出になる。既定 16
   * @param {number} opts.bulletRadius   弾の当たり判定半径(px) 既定 6
   * @param {{x:number,y:number}} opts.center 押し出し方向を決めるための画面中心
   * @returns {{bullets: object[], pushDir: {x:number,y:number}, resampled: object[], regularity: number}}
   */
  function buildBulletWall(points, opts) {
    const o = Object.assign(
      {
        spacing: 24,
        bulletSpeed: 220,
        telegraphMs: 550,
        waveDelayMs: 16,
        bulletRadius: 6,
        center: { x: 0, y: 0 },
      },
      opts || {}
    );

    if (!Array.isArray(points) || points.length < 2) {
      return { bullets: [], pushDir: { x: 0, y: 1 }, resampled: [], regularity: 1 };
    }

    const resampled = resamplePathEven(points, o.spacing);
    const pushDir = choosePushDirection(points, o.center);
    const regularity = estimateRegularity(resampled);

    const bullets = resampled.map((p, i) => ({
      id: i,
      originX: p.x,
      originY: p.y,
      x: p.x,
      y: p.y,
      vx: pushDir.x * o.bulletSpeed,
      vy: pushDir.y * o.bulletSpeed,
      radius: o.bulletRadius,
      spawnDelayMs: i * o.waveDelayMs,
      telegraphMs: o.telegraphMs,
      launched: false,
    }));

    return { bullets, pushDir, resampled, regularity };
  }

  /**
   * 壁の中の1弾を、生成からの経過時間(ms)にもとづいて更新する。
   * 予告時間が終わるまでは originX/Y に留まり、終わったら pushDir 方向へ直進する。
   * 呼び出し側の状態(bullet)をミューテートせず、新しい状態を返す。
   */
  function advanceBullet(bullet, elapsedMsSinceWallCreated, dtSeconds) {
    if (elapsedMsSinceWallCreated < bullet.spawnDelayMs) {
      return Object.assign({}, bullet, { visible: false });
    }
    const sinceSpawn = elapsedMsSinceWallCreated - bullet.spawnDelayMs;
    if (sinceSpawn < bullet.telegraphMs) {
      return Object.assign({}, bullet, {
        visible: true,
        launched: false,
        x: bullet.originX,
        y: bullet.originY,
      });
    }
    const x = bullet.launched ? bullet.x + bullet.vx * dtSeconds : bullet.originX + bullet.vx * dtSeconds;
    const y = bullet.launched ? bullet.y + bullet.vy * dtSeconds : bullet.originY + bullet.vy * dtSeconds;
    return Object.assign({}, bullet, { visible: true, launched: true, x, y });
  }

  // --- Phase 2: 勇者側のシールドシステム（企画書 3.1) ---
  //
  // ゲージがMAXになると無敵シールド(イージス)を任意発動できる。
  // 発動回数は「1プレイにつき5回まで」。状態はイミュータブルに扱う
  // (関数は新しい状態を返すだけで、渡された state を書き換えない)。

  function createShieldState(opts) {
    const o = Object.assign({ maxUses: 5 }, opts || {});
    return { charge: 0, maxUses: o.maxUses, usesLeft: o.maxUses, invincibleUntil: 0 };
  }

  function chargeShield(state, amount) {
    if (amount <= 0) return state;
    return Object.assign({}, state, { charge: Math.min(1, state.charge + amount) });
  }

  function canActivateShield(state) {
    return state.charge >= 1 && state.usesLeft > 0;
  }

  // 発動条件を満たさない場合は state をそのまま返す(呼び出し側で判定不要)
  function activateShield(state, nowMs, durationMs) {
    if (!canActivateShield(state)) return state;
    return Object.assign({}, state, {
      charge: 0,
      usesLeft: state.usesLeft - 1,
      invincibleUntil: nowMs + durationMs,
    });
  }

  function isShieldActive(state, nowMs) {
    return nowMs < state.invincibleUntil;
  }

  const api = {
    dist,
    normalize,
    resamplePathEven,
    choosePushDirection,
    estimateRegularity,
    buildBulletWall,
    advanceBullet,
    createShieldState,
    chargeShield,
    canActivateShield,
    activateShield,
    isShieldActive,
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else {
    root.GrazeCore = api;
  }
})(typeof window !== "undefined" ? window : globalThis);
