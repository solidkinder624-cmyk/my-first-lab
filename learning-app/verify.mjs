/*
 * core.js(採点・進捗管理のロジック)が満たすべき性質を検証する。
 *
 *   node learning-app/verify.mjs
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

// node環境にはlocalStorageが無いので、同じインターフェースを持つ簡易モックを使う。
function makeMemoryStorage() {
  const data = {};
  return {
    getItem: (k) => (Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null),
    setItem: (k, v) => {
      data[k] = String(v);
    },
  };
}

// 1. コース教材データそのものの整合性
{
  check("コースが1つ以上ある", core.COURSES.length > 0);
  core.COURSES.forEach((course) => {
    check(`コース[${course.id}]にレッスンがある`, course.lessons.length > 0);
    course.lessons.forEach((lesson) => {
      check(`レッスン[${course.id}/${lesson.id}]にステップがある`, lesson.steps.length > 0);
      lesson.steps.forEach((step) => {
        check(
          `ステップ[${course.id}/${lesson.id}/${step.id}]のtypeが既知の形式`,
          ["lesson", "quiz", "fill-blank", "code-output"].includes(step.type)
        );
      });
    });
  });
}

// 2. fill-blank の採点: 想定どおりの答えは正解、違う答えは不正解になる
{
  const step = { blanks: [{ accepted: ["let", "const"] }] };
  check("fill-blank: letは正解", core.checkFillBlank(step, ["let"]).correct === true);
  check("fill-blank: constも正解(複数の正解を許容できる)", core.checkFillBlank(step, ["const"]).correct === true);
  check("fill-blank: 前後の空白は無視される", core.checkFillBlank(step, ["  let  "]).correct === true);
  check("fill-blank: varは不正解", core.checkFillBlank(step, ["var"]).correct === false);
  check("fill-blank: 未入力は不正解", core.checkFillBlank(step, [""]).correct === false);
}

// 3. quiz の採点: 正しい選択肢の番号のときだけ正解になる
{
  const step = { choices: ["a", "b", "c"], correctIndex: 1 };
  check("quiz: 正しい番号は正解", core.checkQuiz(step, 1).correct === true);
  check("quiz: 違う番号は不正解", core.checkQuiz(step, 0).correct === false);
}

// 4. code-output の採点: 改行や空白の差はゆるく無視しつつ、内容が違えば不正解にする
{
  const step = { expectedOutput: "1\n2\n3" };
  check("code-output: 完全一致は正解", core.checkCodeOutput(step, "1\n2\n3").correct === true);
  check("code-output: 前後の空行や余分な空白は無視される", core.checkCodeOutput(step, "\n1 \n 2\n3\n\n").correct === true);
  check("code-output: 内容が違えば不正解", core.checkCodeOutput(step, "1\n2").correct === false);
}

// 5. checkAnswer: ステップのtypeに応じて正しい採点関数へ振り分けられる
{
  check(
    "checkAnswer: lessonタイプは読むだけで常に正解扱い",
    core.checkAnswer({ type: "lesson" }, null).correct === true
  );
  check(
    "checkAnswer: quizタイプはchoicesの判定を使う",
    core.checkAnswer({ type: "quiz", correctIndex: 0 }, 0).correct === true
  );
}

// 6. 進捗の保存と読み込みが正しく往復する
{
  const storage = makeMemoryStorage();
  let progress = core.loadProgress(storage);
  check("初回は完了ステップが空", Object.keys(progress.completedSteps).length === 0);
  check("初回のXPは0", progress.xp === 0);

  progress = core.markStepComplete(storage, "js-basics", "variables", "explain");
  check("ステップ完了後、完了扱いになる", core.isStepCompleted(progress, "js-basics", "variables", "explain"));
  check("ステップ完了でXPが加算される", progress.xp === core.XP_PER_STEP);

  const reloaded = core.loadProgress(storage);
  check("保存した進捗が再読み込みでも残る", core.isStepCompleted(reloaded, "js-basics", "variables", "explain"));

  const again = core.markStepComplete(storage, "js-basics", "variables", "explain");
  check("同じステップを2回完了してもXPが二重に増えない", again.xp === core.XP_PER_STEP);
}

// 7. レッスン/ステップのアンロック順序(Progateのような一本道)
{
  const storage = makeMemoryStorage();
  const course = core.findCourse("js-basics");
  let progress = core.loadProgress(storage);

  check("1つ目のレッスンは最初から開いている", core.isLessonUnlocked(course, 0, progress));
  check("2つ目のレッスンは最初は閉じている", core.isLessonUnlocked(course, 1, progress) === false);
  check("1つ目のレッスンの1問目は最初から解ける", core.isStepUnlocked(course, 0, 0, progress));
  check("1つ目のレッスンの2問目はまだ解けない", core.isStepUnlocked(course, 0, 1, progress) === false);

  const lesson0 = course.lessons[0];
  lesson0.steps.forEach((step) => {
    progress = core.markStepComplete(storage, course.id, lesson0.id, step.id);
  });

  check("1つ目のレッスンを全部終えると2つ目のレッスンが開く", core.isLessonUnlocked(course, 1, progress));
  check("1つ目のレッスンを全部終えると2問目以降も解ける", core.isStepUnlocked(course, 0, 1, progress));
}

// 8. コース/レッスンの進捗率(パーセント)の計算
{
  const storage = makeMemoryStorage();
  const course = core.findCourse("js-basics");
  let progress = core.loadProgress(storage);

  const before = core.courseProgressCount(course, progress);
  check("何も終えていないときは進捗0%", before.percent === 0);

  const lesson0 = course.lessons[0];
  progress = core.markStepComplete(storage, course.id, lesson0.id, lesson0.steps[0].id);
  const lessonCount = core.lessonProgressCount(course, lesson0, progress);
  check("レッスン内の完了数が正しく数えられる", lessonCount.completed === 1);

  const after = core.courseProgressCount(course, progress);
  check("1ステップ終えるとコース全体の進捗率が上がる", after.percent > before.percent);
}

// 9. 次に進む位置の計算(レッスンをまたぐ場合も含む)
{
  const course = core.findCourse("js-basics");
  const next = core.getNextPosition(course, 0, 0);
  check("同じレッスン内では次のステップに進む", next.lessonIndex === 0 && next.stepIndex === 1);

  const lastStepIndex = course.lessons[0].steps.length - 1;
  const crossLesson = core.getNextPosition(course, 0, lastStepIndex);
  check("レッスンの最後のステップからは次のレッスンの1問目に進む", crossLesson.lessonIndex === 1 && crossLesson.stepIndex === 0);

  const lastLessonIndex = course.lessons.length - 1;
  const lastStepOfLastLesson = course.lessons[lastLessonIndex].steps.length - 1;
  const end = core.getNextPosition(course, lastLessonIndex, lastStepOfLastLesson);
  check("コースの最後のステップの次はnull(これ以上先が無い)", end === null);
}

console.log("");
if (failures > 0) {
  console.error(`${failures} 件失敗`);
  process.exit(1);
} else {
  console.log("全チェック通過");
}
