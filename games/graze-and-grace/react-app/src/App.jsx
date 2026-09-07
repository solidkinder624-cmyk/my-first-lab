import { useEffect, useRef } from "react";
import {
  buildBulletWall,
  advanceBullet,
  createShieldState,
  chargeShield,
  canActivateShield,
  activateShield,
  isShieldActive,
} from "graze-and-grace-core/core.js";
import { computeArtScore } from "graze-and-grace-core/score.js";
import {
  createClock,
  beatDuration,
  beatPhase,
  isDownbeat,
  nextBeatTime,
  syncAccuracy,
} from "graze-and-grace-core/rhythm.js";
import { decideMove as decideAiMove } from "graze-and-grace-core/ai.js";
import {
  createSpellCard,
  recordSwipe,
  cardDurationMs,
  dueEvents,
  isPlaybackComplete,
} from "graze-and-grace-core/spellcard.js";
import "./App.css";

// GRAZE & GRACE ― Phase 1+2+3+4 プロトタイプ (React版)
//
// core.js / score.js / rhythm.js は DOM に一切依存しない純関数群で、
// games/graze-and-grace/index.html (Canvas + Vanilla JS版) と全く同じものを
// そのまま import している。ゲームロジックは verify.mjs で共通してテスト済み。
//
// 描画対象やHUDの数値は毎フレーム(60fps)更新されるため、React の state に
// 乗せて毎フレーム再レンダリングするのではなく、DOM ノードへの ref を保持して
// requestAnimationFrame ループの中で直接書き換える(Canvasゲームでは一般的な手法)。
// React の state/JSX が担うのは「画面の構造」だけで、ゲームの可変状態そのものは
// useRef に閉じ込めている。

const WIDTH = 720;
const HEIGHT = 480;
const HERO_RADIUS = 9;
const HERO_SPEED = 260; // px/s
const GRAZE_RADIUS = 26; // ヒーローの当たり判定より広い「カスリ」判定
const MIN_SAMPLE_DIST = 6; // スワイプ点を間引く最小距離(px)
const SHIELD_MAX_USES = 5; // 企画書 3.1: シールド発動上限は1プレイにつき5回まで
const SHIELD_CHARGE_PER_GRAZE = 0.14; // カスリ約7回でゲージがMAXになる
const SHIELD_INVINCIBLE_MS = 1500;
const SCHEDULE_AHEAD_SEC = 0.12;
const SCHEDULER_INTERVAL_MS = 25;
const FALLBACK_TELEGRAPH_MS = 500; // 音楽未再生時の固定予告時間(Phase1〜3と同じ)
const MIN_TELEGRAPH_MS = 150; // 拍がすぐ来すぎる場合に確保する最低反応時間

function dist(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

export default function App() {
  const canvasRef = useRef(null);
  const statWallsRef = useRef(null);
  const statBulletsRef = useRef(null);
  const statGrazeRef = useRef(null);
  const statHitsRef = useRef(null);
  const statRegularityRef = useRef(null);
  const statShieldUsesRef = useRef(null);
  const shieldGaugeFillRef = useRef(null);
  const shieldBtnRef = useRef(null);
  const scoreOverallRef = useRef(null);
  const scoreRegularityRef = useRef(null);
  const scoreDensityRef = useRef(null);
  const scoreContinuityRef = useRef(null);
  const scoreCoverageRef = useRef(null);
  const scoreSyncRef = useRef(null);
  const scoreGrazeRef = useRef(null);
  const scoreMaxStreakRef = useRef(null);
  const bpmInputRef = useRef(null);
  const musicBtnRef = useRef(null);
  const beatPulseRef = useRef(null);
  const resetBtnRef = useRef(null);
  const heroModeSelectRef = useRef(null);
  const recordBtnRef = useRef(null);
  const playbackBtnRef = useRef(null);
  const exitChallengeBtnRef = useRef(null);
  const spellcardStatusRef = useRef(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas.getContext("2d");

    let walls = []; // {createdAt, bullets, pushDir, regularity}
    let drawingPoints = null; // 現在ドロー中のスワイプ点列
    let hero = { x: WIDTH / 2, y: HEIGHT - 60 };
    const keys = {};
    let grazedIds = new Set();
    let hitFlash = 0;
    let lastTs = null;
    let shield = createShieldState({ maxUses: SHIELD_MAX_USES });

    // Phase 3: 芸術点(Grace & Graze)の計算材料。ゲームプレイ用の walls とは別に、
    // 画面外に消えた壁もスコア計算のためにセッション終了まで残す。
    let scoreLog = { wallRecords: [], events: [], syncSamples: [] };

    // Phase 4: 音楽同期。AudioContext.currentTime を基準にした拍クロック。
    // rAF の ts (performance.now(), ミリ秒) とは別の時間軸なので、
    // audioOffsetMs = 「performance.now() 換算した AudioContext の起点」を介して変換する。
    let audioCtx = null;
    let rhythmClock = null; // null の間は音楽未再生(固定テレグラフ時間にフォールバック)
    let audioOffsetMs = 0;
    let nextClickBeat = 0;
    let schedulerTimer = null;

    let stats = { wallCount: 0, bulletCount: 0, grazeCount: 0, hits: 0, regularity: 1 };
    let rafId = null;

    // ゲームモード「実証実験モード（セルフチャレンジ）」の状態。
    //   freeplay   : 通常どおり自由にスワイプして弾幕を組む(既定)
    //   recording  : freeplay と同じ挙動だが、スワイプを spellcard.js で記録する
    //   challenge  : スワイプ入力は無効。記録済みカードを自動再生し、回避に専念する
    let mode = "freeplay";
    let recordedCard = createSpellCard();
    let recordingStartedAt = 0;
    let challengeCard = null;
    let challengeStartedAt = 0;
    let challengeIndex = 0;
    let challengeResult = null; // null | "clear" | "failed"

    function audioTimeSecFromTs(ts) {
      return (ts - audioOffsetMs) / 1000;
    }

    function renderHud() {
      statWallsRef.current.textContent = stats.wallCount;
      statBulletsRef.current.textContent = stats.bulletCount;
      statGrazeRef.current.textContent = stats.grazeCount;
      statHitsRef.current.textContent = stats.hits;
      statRegularityRef.current.textContent = stats.regularity.toFixed(2);

      statShieldUsesRef.current.textContent = shield.usesLeft;
      shieldGaugeFillRef.current.style.width = `${Math.round(shield.charge * 100)}%`;
      const ready = canActivateShield(shield);
      shieldGaugeFillRef.current.classList.toggle("ready", ready);
      shieldBtnRef.current.disabled = !ready;

      const art = computeArtScore(scoreLog, { canvasWidth: WIDTH, canvasHeight: HEIGHT });
      scoreOverallRef.current.textContent = art.overall.toFixed(1);
      scoreRegularityRef.current.textContent = (art.grace.regularity * 100).toFixed(1);
      scoreDensityRef.current.textContent = (art.grace.density * 100).toFixed(1);
      scoreContinuityRef.current.textContent = (art.grace.continuity * 100).toFixed(1);
      scoreCoverageRef.current.textContent = (art.grace.coverage * 100).toFixed(1);
      scoreSyncRef.current.textContent = (art.grace.sync * 100).toFixed(1);
      scoreGrazeRef.current.textContent = art.graze.score;
      scoreMaxStreakRef.current.textContent = art.graze.maxStreak;
    }

    function resetGame() {
      walls = [];
      hero = { x: WIDTH / 2, y: HEIGHT - 60 };
      grazedIds = new Set();
      hitFlash = 0;
      shield = createShieldState({ maxUses: SHIELD_MAX_USES });
      scoreLog = { wallRecords: [], events: [], syncSamples: [] };
      stats = { wallCount: 0, bulletCount: 0, grazeCount: 0, hits: 0, regularity: 1 };
      renderHud();
    }

    function tryActivateShield() {
      if (!canActivateShield(shield)) return;
      shield = activateShield(shield, performance.now(), SHIELD_INVINCIBLE_MS);
      renderHud();
    }

    // --- ゲームモード: 実証実験モード（セルフチャレンジ、企画書4.2） ---
    function renderSpellcardUi() {
      const recordBtn = recordBtnRef.current;
      const playbackBtn = playbackBtnRef.current;
      const exitBtn = exitChallengeBtnRef.current;
      const status = spellcardStatusRef.current;
      status.classList.remove("clear", "failed");

      if (mode === "recording") {
        recordBtn.textContent = "■ 録画終了";
        recordBtn.classList.add("recording");
        playbackBtn.disabled = true;
        exitBtn.hidden = true;
        status.textContent = `録画中… ${recordedCard.events.length}個の壁`;
      } else if (mode === "challenge") {
        recordBtn.disabled = true;
        playbackBtn.disabled = true;
        exitBtn.hidden = false;
        if (challengeResult === "clear") {
          status.textContent = "クリア！ 被弾せずに耐え切りました";
          status.classList.add("clear");
        } else if (challengeResult === "failed") {
          status.textContent = "被弾……もう一度挑戦しますか？";
          status.classList.add("failed");
        } else {
          status.textContent = `再生中… (${challengeIndex}/${challengeCard.events.length})`;
        }
      } else {
        recordBtn.disabled = false;
        recordBtn.textContent = "● 録画開始";
        recordBtn.classList.remove("recording");
        exitBtn.hidden = true;
        playbackBtn.disabled = recordedCard.events.length === 0;
        status.textContent = recordedCard.events.length
          ? `記録済み: ${recordedCard.events.length}個の壁 (${(cardDurationMs(recordedCard) / 1000).toFixed(1)}秒)`
          : "";
      }
    }

    function toggleRecording() {
      if (mode === "recording") {
        mode = "freeplay";
      } else if (mode === "freeplay") {
        mode = "recording";
        recordedCard = createSpellCard();
        recordingStartedAt = performance.now();
        resetGame();
      }
      renderSpellcardUi();
    }

    function startPlayback() {
      if (mode !== "freeplay" || recordedCard.events.length === 0) return;
      mode = "challenge";
      challengeCard = recordedCard;
      challengeStartedAt = performance.now();
      challengeIndex = 0;
      challengeResult = null;
      resetGame();
      renderSpellcardUi();
    }

    function exitChallenge() {
      mode = "freeplay";
      challengeCard = null;
      challengeResult = null;
      resetGame();
      renderSpellcardUi();
    }

    // 実証実験モードの再生: 記録済みカードのイベントを経過時間どおりに発火する。
    // tick() から毎フレーム呼ぶ。
    function playbackTick(ts) {
      const elapsedMs = ts - challengeStartedAt;
      const { due, nextIndex } = dueEvents(challengeCard, elapsedMs, challengeIndex);
      challengeIndex = nextIndex;
      due.forEach((event) => spawnWallFromPoints(event.points, ts));
    }

    // --- Phase 4: 音楽同期。WebAudio でメトロノーム(拍のクリック音)を合成する ---
    function playClick(time, isDownbeatClick) {
      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();
      osc.type = "sine";
      osc.frequency.value = isDownbeatClick ? 880 : 660;
      gain.gain.setValueAtTime(0.0001, time);
      gain.gain.exponentialRampToValueAtTime(isDownbeatClick ? 0.35 : 0.2, time + 0.005);
      gain.gain.exponentialRampToValueAtTime(0.0001, time + 0.08);
      osc.connect(gain);
      gain.connect(audioCtx.destination);
      osc.start(time);
      osc.stop(time + 0.09);
    }

    function schedulerTick() {
      if (!audioCtx || !rhythmClock) return;
      const bd = beatDuration(rhythmClock);
      while (rhythmClock.startTime + nextClickBeat * bd < audioCtx.currentTime + SCHEDULE_AHEAD_SEC) {
        const beatTime = rhythmClock.startTime + nextClickBeat * bd;
        const beatInBar =
          ((nextClickBeat % rhythmClock.beatsPerBar) + rhythmClock.beatsPerBar) % rhythmClock.beatsPerBar;
        if (beatTime >= audioCtx.currentTime) playClick(beatTime, beatInBar === 0);
        nextClickBeat++;
      }
    }

    function startMusic() {
      if (audioCtx) return;
      const AudioCtor = window.AudioContext || window.webkitAudioContext;
      audioCtx = new AudioCtor();
      const bpm = Math.max(60, Math.min(220, Number(bpmInputRef.current.value) || 128));
      const startTime = audioCtx.currentTime + 0.15;
      rhythmClock = createClock({ bpm, beatsPerBar: 4, startTime });
      audioOffsetMs = performance.now() - audioCtx.currentTime * 1000;
      nextClickBeat = 0;
      schedulerTimer = setInterval(schedulerTick, SCHEDULER_INTERVAL_MS);
      schedulerTick();
      musicBtnRef.current.textContent = "■ BGM停止 (M)";
      bpmInputRef.current.disabled = true;
    }

    function stopMusic() {
      if (!audioCtx) return;
      clearInterval(schedulerTimer);
      schedulerTimer = null;
      audioCtx.close();
      audioCtx = null;
      rhythmClock = null;
      musicBtnRef.current.textContent = "♪ BGM開始 (M)";
      bpmInputRef.current.disabled = false;
    }

    function toggleMusic() {
      if (audioCtx) stopMusic();
      else startMusic();
    }

    // --- スワイプ入力: pointerdown/move/up で弾幕の壁を生成する ---
    function toCanvasPoint(evt) {
      const rect = canvas.getBoundingClientRect();
      return {
        x: ((evt.clientX - rect.left) / rect.width) * WIDTH,
        y: ((evt.clientY - rect.top) / rect.height) * HEIGHT,
      };
    }

    function onPointerDown(evt) {
      if (mode === "challenge") return; // 実証実験モード中はスワイプで壁を作れない
      canvas.setPointerCapture(evt.pointerId);
      drawingPoints = [toCanvasPoint(evt)];
    }

    function onPointerMove(evt) {
      if (!drawingPoints) return;
      const p = toCanvasPoint(evt);
      const last = drawingPoints[drawingPoints.length - 1];
      if (dist(last, p) >= MIN_SAMPLE_DIST) {
        drawingPoints.push(p);
      }
    }

    // スワイプ点列から壁を1つ生成して walls / scoreLog に積む。
    // ライブ入力(finishSwipe)と実証実験モードの再生(playbackTick)の両方から呼ばれる。
    function spawnWallFromPoints(points, createdAt) {
      // Phase 4: 音楽が鳴っていれば、予告時間をスワイプ完了時刻から
      // 「一番近い次の拍」までの時間に合わせる ―― 壁は常に拍ピッタリで発射される。
      let telegraphMs = FALLBACK_TELEGRAPH_MS;
      if (rhythmClock) {
        const nowSec = audioTimeSecFromTs(createdAt);
        let launchSec = nextBeatTime(rhythmClock, nowSec);
        if ((launchSec - nowSec) * 1000 < MIN_TELEGRAPH_MS) {
          launchSec = nextBeatTime(rhythmClock, launchSec);
        }
        telegraphMs = (launchSec - nowSec) * 1000;
        scoreLog.syncSamples.push(syncAccuracy(rhythmClock, nowSec));
      }

      const { bullets, regularity, resampled } = buildBulletWall(points, {
        spacing: 22,
        bulletSpeed: 210,
        telegraphMs,
        waveDelayMs: 14,
        bulletRadius: 6,
        center: { x: WIDTH / 2, y: HEIGHT / 2 },
      });
      if (bullets.length === 0) return;

      walls.push({ createdAt, bullets, regularity });
      // Phase 3 のスコア計算用に、画面外に消えても残る履歴として記録する
      scoreLog.wallRecords.push({
        createdAt,
        regularity,
        bulletCount: bullets.length,
        points: resampled,
      });
    }

    function finishSwipe() {
      const points = drawingPoints;
      drawingPoints = null;
      if (mode === "challenge") return; // 実証実験モード中は再生される壁だけが表示される
      if (!points || points.length < 2) return;

      const createdAt = performance.now();
      if (mode === "recording") {
        recordedCard = recordSwipe(recordedCard, createdAt - recordingStartedAt, points);
        renderSpellcardUi();
      }
      spawnWallFromPoints(points, createdAt);
    }

    function onKeyDown(e) {
      keys[e.key.toLowerCase()] = true;
      if (e.key === " " || e.code === "Space") {
        e.preventDefault();
        tryActivateShield();
      }
      if (e.key.toLowerCase() === "m") {
        toggleMusic();
      }
    }
    function onKeyUp(e) {
      keys[e.key.toLowerCase()] = false;
    }

    // --- 描画 ---
    function draw() {
      ctx.clearRect(0, 0, WIDTH, HEIGHT);

      if (drawingPoints && drawingPoints.length > 1) {
        ctx.save();
        ctx.strokeStyle = "rgba(150, 180, 255, 0.55)";
        ctx.lineWidth = 2;
        ctx.setLineDash([6, 6]);
        ctx.beginPath();
        ctx.moveTo(drawingPoints[0].x, drawingPoints[0].y);
        for (let i = 1; i < drawingPoints.length; i++) ctx.lineTo(drawingPoints[i].x, drawingPoints[i].y);
        ctx.stroke();
        ctx.restore();
      }

      walls.forEach((wall) => {
        wall.bullets.forEach((b) => {
          if (!b.visible) return;
          ctx.beginPath();
          if (!b.launched) {
            ctx.fillStyle = "rgba(255, 210, 120, 0.55)";
            ctx.arc(b.x, b.y, b.radius * 0.7, 0, Math.PI * 2);
          } else {
            ctx.fillStyle = "#ff5d7a";
            ctx.shadowColor = "#ff5d7a";
            ctx.shadowBlur = 6;
            ctx.arc(b.x, b.y, b.radius, 0, Math.PI * 2);
          }
          ctx.fill();
          ctx.shadowBlur = 0;
        });
      });

      const invincible = isShieldActive(shield, performance.now());

      ctx.beginPath();
      ctx.fillStyle = hitFlash > 0 ? `rgba(255,255,255,${0.5 + hitFlash * 0.5})` : "#7ee0ff";
      ctx.arc(hero.x, hero.y, HERO_RADIUS, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.strokeStyle = "rgba(126, 224, 255, 0.25)";
      ctx.lineWidth = 1;
      ctx.arc(hero.x, hero.y, GRAZE_RADIUS, 0, Math.PI * 2);
      ctx.stroke();

      if (invincible) {
        // イージス(無敵シールド)発動中: 金色のオーラで視覚的に明示する
        ctx.beginPath();
        ctx.strokeStyle = "#ffd24f";
        ctx.lineWidth = 3;
        ctx.shadowColor = "#ffd24f";
        ctx.shadowBlur = 12;
        ctx.arc(hero.x, hero.y, HERO_RADIUS + 6, 0, Math.PI * 2);
        ctx.stroke();
        ctx.shadowBlur = 0;
      }
    }

    // --- 拍のビジュアル表示 ---
    function updateBeatPulse(ts) {
      const el = beatPulseRef.current;
      if (!rhythmClock) {
        el.classList.remove("on-beat", "downbeat");
        return;
      }
      const nowSec = audioTimeSecFromTs(ts);
      const phase = beatPhase(rhythmClock, nowSec);
      const onBeat = phase < 0.12;
      el.classList.toggle("on-beat", onBeat);
      el.classList.toggle("downbeat", isDownbeat(rhythmClock, nowSec, 0.12));
    }

    // --- ゲームループ ---
    function tick(ts) {
      if (lastTs == null) lastTs = ts;
      const dt = Math.min((ts - lastTs) / 1000, 1 / 20);
      lastTs = ts;

      updateBeatPulse(ts);

      if (mode === "challenge") playbackTick(ts);

      let dx = 0, dy = 0;
      const heroMode = heroModeSelectRef.current.value;
      if (heroMode === "manual") {
        if (keys["arrowleft"] || keys["a"]) dx -= 1;
        if (keys["arrowright"] || keys["d"]) dx += 1;
        if (keys["arrowup"] || keys["w"]) dy -= 1;
        if (keys["arrowdown"] || keys["s"]) dy += 1;
      } else {
        const allBullets = [];
        walls.forEach((wall) => allBullets.push(...wall.bullets));
        const dir = decideAiMove(heroMode, hero, allBullets, {
          width: WIDTH,
          height: HEIGHT,
          heroRadius: HERO_RADIUS,
        });
        dx = dir.x;
        dy = dir.y;
      }
      if (dx !== 0 || dy !== 0) {
        const len = Math.hypot(dx, dy) || 1;
        hero = {
          x: Math.max(HERO_RADIUS, Math.min(WIDTH - HERO_RADIUS, hero.x + (dx / len) * HERO_SPEED * dt)),
          y: Math.max(HERO_RADIUS, Math.min(HEIGHT - HERO_RADIUS, hero.y + (dy / len) * HERO_SPEED * dt)),
        };
      }

      let bulletCount = 0;
      let grazeThisFrame = 0;
      let hitThisFrame = false;
      const invincible = isShieldActive(shield, ts);

      walls = walls
        .map((wall) => {
          const elapsed = ts - wall.createdAt;
          const bullets = wall.bullets
            .map((b) => advanceBullet(b, elapsed, dt))
            .filter((b) => b.x > -40 && b.x < WIDTH + 40 && b.y > -40 && b.y < HEIGHT + 40);
          return Object.assign({}, wall, { bullets });
        })
        .filter((wall) => wall.bullets.length > 0 || ts - wall.createdAt < 60000);

      walls.forEach((wall) => {
        wall.bullets.forEach((b) => {
          if (!b.visible) return;
          bulletCount++;
          const d = dist(hero, b);
          const key = wall.createdAt + ":" + b.id;
          if (d < HERO_RADIUS + b.radius) {
            if (!invincible) hitThisFrame = true;
          } else if (b.launched && d < GRAZE_RADIUS && !grazedIds.has(key)) {
            grazedIds.add(key);
            grazeThisFrame++;
          }
        });
      });

      if (hitThisFrame) hitFlash = 1;
      hitFlash = Math.max(0, hitFlash - dt * 2);

      if (grazeThisFrame > 0) {
        shield = chargeShield(shield, grazeThisFrame * SHIELD_CHARGE_PER_GRAZE);
      }

      // Phase 3: 芸術点計算用に、起きた順でカスリ/被弾イベントを記録する
      for (let i = 0; i < grazeThisFrame; i++) scoreLog.events.push({ type: "graze" });
      if (hitThisFrame) scoreLog.events.push({ type: "hit" });

      stats.wallCount = walls.length;
      stats.bulletCount = bulletCount;
      stats.grazeCount += grazeThisFrame;
      stats.hits += hitThisFrame ? 1 : 0;
      if (walls.length) stats.regularity = walls[walls.length - 1].regularity;
      renderHud();

      if (mode === "challenge" && challengeResult === null) {
        if (hitThisFrame) {
          challengeResult = "failed";
        } else if (isPlaybackComplete(challengeCard, challengeIndex) && bulletCount === 0) {
          challengeResult = "clear";
        }
        renderSpellcardUi();
      } else if (mode === "challenge") {
        renderSpellcardUi();
      }

      draw();
      rafId = requestAnimationFrame(tick);
    }

    const resetBtn = resetBtnRef.current;
    const shieldBtn = shieldBtnRef.current;
    const musicBtn = musicBtnRef.current;
    const recordBtn = recordBtnRef.current;
    const playbackBtn = playbackBtnRef.current;
    const exitChallengeBtn = exitChallengeBtnRef.current;

    canvas.addEventListener("pointerdown", onPointerDown);
    canvas.addEventListener("pointermove", onPointerMove);
    canvas.addEventListener("pointerup", finishSwipe);
    canvas.addEventListener("pointercancel", finishSwipe);
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    resetBtn.addEventListener("click", resetGame);
    shieldBtn.addEventListener("click", tryActivateShield);
    musicBtn.addEventListener("click", toggleMusic);
    recordBtn.addEventListener("click", toggleRecording);
    playbackBtn.addEventListener("click", startPlayback);
    exitChallengeBtn.addEventListener("click", exitChallenge);

    renderHud();
    renderSpellcardUi();
    rafId = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(rafId);
      if (schedulerTimer) clearInterval(schedulerTimer);
      if (audioCtx) audioCtx.close();
      canvas.removeEventListener("pointerdown", onPointerDown);
      canvas.removeEventListener("pointermove", onPointerMove);
      canvas.removeEventListener("pointerup", finishSwipe);
      canvas.removeEventListener("pointercancel", finishSwipe);
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
      resetBtn.removeEventListener("click", resetGame);
      shieldBtn.removeEventListener("click", tryActivateShield);
      musicBtn.removeEventListener("click", toggleMusic);
      recordBtn.removeEventListener("click", toggleRecording);
      playbackBtn.removeEventListener("click", startPlayback);
      exitChallengeBtn.removeEventListener("click", exitChallenge);
    };
  }, []);

  return (
    <div id="game-root">
      <h1>GRAZE &amp; GRACE ― Phase 1+2+3+4 ＋ ソロモードAI (React版)</h1>
      <div id="stage-wrap">
        <canvas ref={canvasRef} id="stage" width={WIDTH} height={HEIGHT} />
      </div>
      <div id="hud">
        <span>壁の数: <b ref={statWallsRef}>0</b></span>
        <span>現在の弾数: <b ref={statBulletsRef}>0</b></span>
        <span>カスリ: <b ref={statGrazeRef}>0</b></span>
        <span>被弾: <b ref={statHitsRef}>0</b></span>
        <span>規則性(直近の壁): <b ref={statRegularityRef}>1.00</b></span>
        <button id="reset-btn" ref={resetBtnRef} type="button">リセット</button>
      </div>
      <div id="hero-mode-row">
        <span>勇者の操作:</span>
        <select id="hero-mode-select" ref={heroModeSelectRef} defaultValue="manual">
          <option value="manual">手動 (WASD/矢印キー)</option>
          <option value="beginner">AI: ビギナー型</option>
          <option value="scorer">AI: スコアラー型</option>
          <option value="tas">AI: TAS型</option>
        </select>
      </div>
      <div id="spellcard-row">
        <span>実証実験モード:</span>
        <button id="record-btn" ref={recordBtnRef} type="button">● 録画開始</button>
        <button id="playback-btn" ref={playbackBtnRef} type="button" disabled>▶ 再生してクリア判定</button>
        <button id="exit-challenge-btn" ref={exitChallengeBtnRef} type="button" hidden>■ 退出(自由に弾幕作成へ戻る)</button>
        <span id="spellcard-status" ref={spellcardStatusRef}></span>
      </div>
      <div id="shield-row">
        <span>シールド:</span>
        <div id="shield-gauge"><div id="shield-gauge-fill" ref={shieldGaugeFillRef} /></div>
        <span>残り <b ref={statShieldUsesRef}>5</b>/5</span>
        <button id="shield-btn" ref={shieldBtnRef} type="button" disabled>発動 (Space)</button>
      </div>
      <div id="music-row">
        <span>BPM:</span>
        <input ref={bpmInputRef} type="number" id="bpm-input" defaultValue={128} min={60} max={220} step={1} />
        <button id="music-btn" ref={musicBtnRef} type="button">♪ BGM開始 (M)</button>
        <span>拍:</span>
        <div id="beat-pulse" ref={beatPulseRef} />
      </div>
      <div id="score-panel">
        <span className="overall">芸術点: <b ref={scoreOverallRef}>0.0</b></span>
        <span>規則性: <b ref={scoreRegularityRef}>0.0</b></span>
        <span>密度: <b ref={scoreDensityRef}>0.0</b></span>
        <span>継続性: <b ref={scoreContinuityRef}>0.0</b></span>
        <span>美しさ(画面の使い方): <b ref={scoreCoverageRef}>0.0</b></span>
        <span>シンクロ率: <b ref={scoreSyncRef}>0.0</b></span>
        <span>カスリ得点: <b ref={scoreGrazeRef}>0</b> (最大連続 <b ref={scoreMaxStreakRef}>0</b>)</span>
      </div>
      <p id="help">
        画面上でスワイプすると、その軌跡に沿って一定間隔の弾が並び（＝弾幕の壁）、
        少し予告してからスワイプと直交する向き（画面中央側）へ一斉に飛び出します。<br />
        <kbd>WASD</kbd> / <kbd>矢印キー</kbd> でヒーロー（水色の点）を動かし、壁の隙間（安置）を通り抜けられるか試してください。
        水色の輪はカスリ判定の範囲です。カスリを重ねるとシールドゲージが溜まり、MAXで
        <kbd>Space</kbd> を押すと一定時間の無敵「イージス」を発動できます（1プレイ5回まで）。<br />
        <kbd>M</kbd> / ♪ボタンでBGM（WebAudioで合成したメトロノーム）を開始すると、
        スワイプを終えた瞬間から一番近い次の拍まで自動的に予告時間が調整され、弾幕の壁は
        必ず拍にピッタリ合わせて発射されます。壁を描き終えたタイミングが拍に近いほど
        「シンクロ率」が上がります（芸術点は Grace＝規則性・密度・継続性・美しさ・シンクロ率、
        ＋ Graze＝連続カスリ、から算出）。<br />
        「勇者の操作」を切り替えると、企画書4.1のソロモード用AIで遊べます。
        <b>ビギナー型</b>は近い弾から単純に逃げるだけ（誘導して追い詰められる）、
        <b>スコアラー型</b>はわざと弾に寄ってカスリを稼ごうとする（罠を張りやすい）、
        <b>TAS型</b>は周囲の弾を先読みしてほぼ機械的に回避する（隙間で囲む弾幕が必要）。<br />
        「実証実験モード」（企画書4.2）では、● 録画開始 を押してからスワイプで弾幕を組むと、
        その順序とタイミングがそのまま記録されます。■ 録画終了 の後、▶ 再生してクリア判定
        を押すと同じ弾幕がもう一度自動再生され、今度は自分（または選んだAI）がそれを回避します。
        最後まで被弾しなければ「クリア」。■ 退出 でいつでも自由な作成モードに戻れます。
      </p>
    </div>
  );
}
