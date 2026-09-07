// GRAZE & GRACE - ゲームモード「2. 実証実験モード（セルフチャレンジ）」
// 企画書4.2: 自分で作成（記録）した弾幕譜面に対し、自らが「勇者側」となって
// 回避に挑む。クリアチェック機能。
//
// ここでは「スペルカード」＝記録されたスワイプ列（相対時刻つき）の
// 作成・再生タイミング判定だけを扱う。実際の弾幕生成(buildBulletWall)や
// 描画・入力は呼び出し側(index.html / App.jsx)が担当する。
//
// DOM に一切依存しない純関数群。core.js と同じ形で window.GrazeSpellCard /
// module.exports に生える。

(function (root) {
  "use strict";

  // 空のスペルカードを作る
  function createSpellCard() {
    return { events: [] };
  }

  // 録画開始からの経過時間(ms)とスワイプ点列を1件、末尾に記録する。
  // offsetMs は録画開始を0とした相対時刻(単調増加であることを呼び出し側が保証する:
  // 録画は常に時系列順に finishSwipe されるので自然に満たされる)。
  function recordSwipe(card, offsetMs, points) {
    return { events: card.events.concat([{ offsetMs, points }]) };
  }

  // カードの総再生時間(ms)。空なら0。
  function cardDurationMs(card) {
    if (card.events.length === 0) return 0;
    return card.events[card.events.length - 1].offsetMs;
  }

  /**
   * 再生開始からの経過時間(elapsedMs)時点で「発火すべきだがまだ発火していない」
   * イベントを返す。fromIndex 以降を線形に見て、offsetMs <= elapsedMs の間だけ集める。
   * 呼び出し側は返ってきた nextIndex を次回呼び出しの fromIndex として使う
   * (毎フレーム呼んでも同じイベントを二重に発火しない)。
   */
  function dueEvents(card, elapsedMs, fromIndex) {
    const due = [];
    let i = fromIndex;
    while (i < card.events.length && card.events[i].offsetMs <= elapsedMs) {
      due.push(card.events[i]);
      i++;
    }
    return { due, nextIndex: i };
  }

  // 記録されている全イベントを発火し終えたか(まだ弾が画面に残っているかは別問題)
  function isPlaybackComplete(card, index) {
    return index >= card.events.length;
  }

  const api = { createSpellCard, recordSwipe, cardDurationMs, dueEvents, isPlaybackComplete };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else {
    root.GrazeSpellCard = api;
  }
})(typeof window !== "undefined" ? window : globalThis);
