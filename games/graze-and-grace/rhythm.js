// GRAZE & GRACE - Phase 4: 音楽との同期システム（企画書 2.2 のリズム・ドローイングUI、
// 5.Phase4 の「BGMのBPM/拍に合わせて弾幕ジェネレーターを制御する仕組み」の核）
//
// AudioContext や setInterval など「実際に音を鳴らす」部分には一切依存しない、
// 「拍の時刻計算」だけを扱う純関数群。単位は呼び出し側で統一していれば何でもよいが、
// Web Audio API の audioContext.currentTime に合わせて「秒」を渡すことを想定している。
//
// clock = { bpm, beatsPerBar, startTime } という不変のレコードで表す。
// startTime は「拍0(曲の先頭/小節の先頭)」に相当する時刻。

(function (root) {
  "use strict";

  function createClock(opts) {
    const o = Object.assign({ bpm: 120, beatsPerBar: 4, startTime: 0 }, opts || {});
    if (o.bpm <= 0) throw new Error("bpm must be > 0");
    return { bpm: o.bpm, beatsPerBar: o.beatsPerBar, startTime: o.startTime };
  }

  function beatDuration(clock) {
    return 60 / clock.bpm;
  }

  // 曲頭から数えて、指定時刻が何拍目(小数)にあたるか
  function elapsedBeats(clock, time) {
    return (time - clock.startTime) / beatDuration(clock);
  }

  function currentBeatIndex(clock, time) {
    return Math.floor(elapsedBeats(clock, time));
  }

  // 現在の拍の中でどれだけ進んだか (0=拍の頭、1に近いほど次の拍の直前)
  function beatPhase(clock, time) {
    const e = elapsedBeats(clock, time);
    return e - Math.floor(e);
  }

  // 小節の頭（1拍目）付近かどうか。toleranceBeats は許容誤差(拍単位)
  function isDownbeat(clock, time, toleranceBeats) {
    const tol = toleranceBeats == null ? 0.08 : toleranceBeats;
    const idx = currentBeatIndex(clock, time);
    const phase = beatPhase(clock, time);
    const nearBoundary = phase < tol || phase > 1 - tol;
    const beatInBar = ((idx % clock.beatsPerBar) + clock.beatsPerBar) % clock.beatsPerBar;
    return nearBoundary && beatInBar === 0;
  }

  // 指定時刻より後にくる、直近の拍の時刻(必ず time より大きい値を返す)
  function nextBeatTime(clock, time) {
    const bd = beatDuration(clock);
    const idx = currentBeatIndex(clock, time);
    let candidate = clock.startTime + (idx + 1) * bd;
    while (candidate <= time) candidate += bd;
    return candidate;
  }

  // 指定時刻に最も近い拍の時刻(前後どちらもありうる)
  function nearestBeatTime(clock, time) {
    const bd = beatDuration(clock);
    const roundedIdx = Math.round(elapsedBeats(clock, time));
    return clock.startTime + roundedIdx * bd;
  }

  // 拍にどれだけピッタリ合っているか (0=完全にオフビート, 1=拍のジャストタイミング)
  // 企画書 2.1「シンクロ率」の最小限の実装。
  function syncAccuracy(clock, time) {
    const phase = beatPhase(clock, time);
    const distanceToNearestBeat = Math.min(phase, 1 - phase); // 0(拍上)〜0.5(オフビート)
    return Math.max(0, 1 - distanceToNearestBeat * 2);
  }

  const api = {
    createClock,
    beatDuration,
    elapsedBeats,
    currentBeatIndex,
    beatPhase,
    isDownbeat,
    nextBeatTime,
    nearestBeatTime,
    syncAccuracy,
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else {
    root.GrazeRhythm = api;
  }
})(typeof window !== "undefined" ? window : globalThis);
