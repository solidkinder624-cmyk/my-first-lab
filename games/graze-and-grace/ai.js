// GRAZE & GRACE - ゲームモード: ソロモード（スコアアタック）用のAI勇者
// 企画書 4.1「敵AIの性格バリエーション」の実装。
//
//   ビギナー型: 弾から遠ざかり、画面端へ逃げる（誘導が必要）
//   スコアラー型: あえて危険地帯に飛び込みグレイズを狙う（罠を張る対象）
//   TAS型: 1ドットの隙間も機械的に避ける（純粋なパズル的包囲網が必要）
//
// DOM に一切依存しない純関数群。core.js の bullet 形状
// ({x, y, vx, vy, radius, launched, visible}) をそのまま受け取る。
// 呼び出し側は毎フレーム decideMove() を呼び、返ってきた単位ベクトル方向へ
// 既存の HERO_SPEED で移動させるだけでよい（キーボード入力の dx/dy と同じ扱い）。

(function (root) {
  "use strict";

  const TYPES = Object.freeze({
    BEGINNER: "beginner",
    SCORER: "scorer",
    TAS: "tas",
  });

  const TYPE_LABELS = Object.freeze({
    beginner: "ビギナー型",
    scorer: "スコアラー型",
    tas: "TAS型",
  });

  function dist(a, b) {
    return Math.hypot(a.x - b.x, a.y - b.y);
  }

  function normalize(v) {
    const len = Math.hypot(v.x, v.y);
    if (len < 1e-6) return { x: 0, y: 0 };
    return { x: v.x / len, y: v.y / len };
  }

  // 弾のうち「動いている(launched)」ものだけを危険源として扱う。
  // 予告中(未発射)の弾は位置が固定なので、これから危険になる場所として
  // 別途 tas 型のみ考慮する。
  function activeBullets(bullets) {
    return bullets.filter((b) => b.visible);
  }

  // --- ビギナー型: 近くの弾から単純に遠ざかる。何もなければ動かない
  // (先読みや安全地帯の探索をしないので、ボス側に画面端へ追い詰められやすい) ---
  function decideBeginner(hero, bullets, opts) {
    const dangerRadius = opts.dangerRadius;
    let push = { x: 0, y: 0 };
    activeBullets(bullets).forEach((b) => {
      const d = dist(hero, b);
      if (d < dangerRadius && d > 1e-6) {
        const weight = (dangerRadius - d) / dangerRadius; // 近いほど強く反応
        push.x += ((hero.x - b.x) / d) * weight;
        push.y += ((hero.y - b.y) / d) * weight;
      }
    });
    return normalize(push);
  }

  // --- スコアラー型: 最寄りの発射済み弾のカスリ判定ギリギりまで自分から近づき、
  // 被弾判定に入りそうなら最低限だけ引く。危険地帯に居座ってカスリを稼ごうとする ---
  function decideScorer(hero, bullets, opts) {
    const active = activeBullets(bullets);
    if (active.length === 0) return { x: 0, y: 0 };

    let nearest = null;
    let nearestDist = Infinity;
    active.forEach((b) => {
      const d = dist(hero, b);
      if (d < nearestDist) {
        nearestDist = d;
        nearest = b;
      }
    });
    if (!nearest) return { x: 0, y: 0 };

    const hitMargin = opts.heroRadius + nearest.radius + opts.safetyMargin;
    const targetDist = opts.heroRadius + nearest.radius + opts.grazeMargin;

    const dir = { x: hero.x - nearest.x, y: hero.y - nearest.y };
    const away = normalize(dir);

    if (nearestDist < hitMargin) {
      // 被弾しそうなら弾から離れる方向へ全力
      return away;
    }
    if (nearestDist > targetDist) {
      // まだ遠いので弾に近づく(=away の逆方向)
      return { x: -away.x, y: -away.y };
    }
    // ちょうど良い距離: 微調整のみ(ほぼ静止してカスリを維持)
    return { x: 0, y: 0 };
  }

  // --- TAS型: 複数方向を先読みし、どの弾からも最も安全な方向へ機械的に移動する ---
  function predictBulletPos(bullet, dtSeconds) {
    if (!bullet.launched) return { x: bullet.x, y: bullet.y };
    return { x: bullet.x + bullet.vx * dtSeconds, y: bullet.y + bullet.vy * dtSeconds };
  }

  function safetyAt(pos, bullets, heroRadius, lookaheadTimes) {
    let minMargin = Infinity;
    bullets.forEach((b) => {
      lookaheadTimes.forEach((t) => {
        const p = predictBulletPos(b, t);
        const margin = dist(pos, p) - (heroRadius + b.radius);
        if (margin < minMargin) minMargin = margin;
      });
    });
    return minMargin === Infinity ? 1e9 : minMargin;
  }

  function decideTas(hero, bullets, opts) {
    const active = activeBullets(bullets);
    if (active.length === 0) return { x: 0, y: 0 };

    const lookaheadTimes = opts.lookaheadTimes || [0.08, 0.16, 0.28];
    const candidateCount = opts.candidateDirections || 16;
    const step = opts.probeDistance || 24;

    let best = { x: 0, y: 0 };
    let bestScore = safetyAt(hero, active, opts.heroRadius, lookaheadTimes);

    for (let i = 0; i < candidateCount; i++) {
      const angle = (i / candidateCount) * Math.PI * 2;
      const dir = { x: Math.cos(angle), y: Math.sin(angle) };
      const probe = { x: hero.x + dir.x * step, y: hero.y + dir.y * step };
      const clamped = {
        x: Math.max(opts.heroRadius, Math.min(opts.width - opts.heroRadius, probe.x)),
        y: Math.max(opts.heroRadius, Math.min(opts.height - opts.heroRadius, probe.y)),
      };
      const score = safetyAt(clamped, active, opts.heroRadius, lookaheadTimes);
      if (score > bestScore) {
        bestScore = score;
        best = dir;
      }
    }
    return normalize(best);
  }

  /**
   * @param {"beginner"|"scorer"|"tas"} type
   * @param {{x:number,y:number}} hero
   * @param {object[]} bullets core.js の advanceBullet が返す形状の弾リスト
   * @param {object} opts
   * @param {number} opts.width, opts.height 画面サイズ
   * @param {number} opts.heroRadius
   * @param {number} [opts.dangerRadius=90] ビギナー型が反応する距離
   * @param {number} [opts.grazeMargin=6] スコアラー型が維持しようとするカスリ距離の余裕
   * @param {number} [opts.safetyMargin=2] スコアラー型が被弾直前とみなす余裕
   * @returns {{x:number, y:number}} 単位ベクトル(移動が無ければ {x:0,y:0})
   */
  function decideMove(type, hero, bullets, opts) {
    const o = Object.assign(
      {
        width: 720,
        height: 480,
        heroRadius: 9,
        dangerRadius: 90,
        grazeMargin: 6,
        safetyMargin: 2,
      },
      opts || {}
    );
    switch (type) {
      case TYPES.BEGINNER:
        return decideBeginner(hero, bullets, o);
      case TYPES.SCORER:
        return decideScorer(hero, bullets, o);
      case TYPES.TAS:
        return decideTas(hero, bullets, o);
      default:
        throw new Error(`unknown AI type: ${type}`);
    }
  }

  const api = { TYPES, TYPE_LABELS, decideMove };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else {
    root.GrazeAI = api;
  }
})(typeof window !== "undefined" ? window : globalThis);
