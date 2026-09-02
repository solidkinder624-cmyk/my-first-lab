/*
 * コード学習アプリの「ロジック部分」だけを集めたファイル。
 *
 * 画面の見た目(index.html側)とは分離してあり、DOMに依存しない純粋な関数だけで
 * できているので、ブラウザなしで node で直接テストできる(verify.mjs参照)。
 *
 *   node learning-app/verify.mjs
 */
(function (root) {
  "use strict";

  // ---------------------------------------------------------------------
  // コース内容(教材データ)
  // ---------------------------------------------------------------------
  // step.type の種類(=このアプリが対応する「様々な形式」の演習):
  //   "lesson"      : 説明を読むだけのスライド。読んだら次に進める。
  //   "quiz"        : 選択肢から正しいものを選ぶ形式。
  //   "fill-blank"  : コードの空欄(___0___ のような印)を埋める形式。
  //   "code-output" : 実際にJavaScriptコードを書いて実行し、出力(console.logの結果)を
  //                   お手本と比較する形式。ブラウザ側でのみ実行する。
  const COURSES = [
    {
      id: "js-basics",
      title: "JavaScript入門",
      description: "プログラムに命令を出す言語のひとつ、JavaScript(略してJS)の基本を学びます。",
      lessons: [
        {
          id: "variables",
          title: "変数(へんすう)を使ってみよう",
          steps: [
            {
              id: "explain",
              type: "lesson",
              title: "変数とは",
              body:
                "変数(へんすう) とは、データを一時的にしまっておく「箱」のようなものです。\n" +
                "JavaScriptでは let という言葉(キーワード)を使って箱を作り、= (イコール)で" +
                "箱の中身を決めます。\n\n" +
                "例: let name = \"太郎\";\n" +
                "これで name という箱に \"太郎\" という文字が入りました。",
            },
            {
              id: "fill-let",
              type: "fill-blank",
              title: "空欄を埋めよう",
              body: "新しい変数を作るためのキーワードを空欄に入れてください。",
              template: '___0___ score = 100;',
              blanks: [{ accepted: ["let", "const"] }],
              hint: "変数を作るときに使うキーワードです(letかconst)。",
            },
            {
              id: "output-variable",
              type: "code-output",
              title: "実行してみよう",
              body:
                "console.log(...) は、カッコの中身を画面(コンソール)に表示する命令です。\n" +
                "message という変数に好きな文字を入れて、console.logで表示してみましょう。",
              starterCode: 'let message = "Hello";\nconsole.log(message);',
              expectedOutput: "Hello",
              hint: "starterCodeのHelloの部分を書き換えても、最終的にHelloと表示されればOKです。",
            },
          ],
        },
        {
          id: "conditionals",
          title: "条件分岐(じょうけんぶんき)",
          steps: [
            {
              id: "explain",
              type: "lesson",
              title: "if文とは",
              body:
                "条件分岐(じょうけんぶんき) とは、「もし〜ならこうする」という判断を" +
                "プログラムにさせる仕組みです。JavaScriptでは if という言葉を使います。\n\n" +
                "例:\nif (score >= 60) {\n  console.log(\"合格\");\n}",
            },
            {
              id: "quiz-if",
              type: "quiz",
              title: "クイズ",
              body: "if (score >= 60) { ... } の >= は何を意味する記号でしょう?",
              choices: [
                "左が右より大きいか等しい(以上)",
                "左と右が等しくない",
                "左に右を足す",
              ],
              correctIndex: 0,
            },
            {
              id: "output-if",
              type: "code-output",
              title: "実行してみよう",
              body: "scoreが80のとき「合格」と表示されるようにコードを完成させ、実行してください。",
              starterCode:
                'let score = 80;\nif (score >= 60) {\n  console.log("合格");\n} else {\n  console.log("不合格");\n}',
              expectedOutput: "合格",
              hint: "scoreは80なので、if の条件(60以上)を満たします。",
            },
          ],
        },
        {
          id: "arrays-loops",
          title: "配列(はいれつ)とくり返し",
          steps: [
            {
              id: "explain",
              type: "lesson",
              title: "配列とfor文",
              body:
                "配列(はいれつ) とは、複数のデータを1つの箱に順番に並べて入れられるものです。\n" +
                "例: let fruits = [\"りんご\", \"みかん\"];\n\n" +
                "くり返し(ループ) を使うと、配列の中身をひとつずつ順番に処理できます。\n" +
                "for (let i = 0; i < fruits.length; i++) { ... } のように書きます。",
            },
            {
              id: "fill-array",
              type: "fill-blank",
              title: "空欄を埋めよう",
              body: "配列を作るときに使う記号を空欄に入れてください。",
              template: "let nums = ___0___1, 2, 3___1___;",
              blanks: [{ accepted: ["["] }, { accepted: ["]"] }],
              hint: "配列は角カッコで囲みます。",
            },
            {
              id: "output-loop",
              type: "code-output",
              title: "実行してみよう",
              body: "配列numsの中身を、for文を使って1行ずつconsole.logで表示してください。",
              starterCode:
                "let nums = [1, 2, 3];\nfor (let i = 0; i < nums.length; i++) {\n  console.log(nums[i]);\n}",
              expectedOutput: "1\n2\n3",
              hint: "console.logが3回呼ばれ、1・2・3が順番に表示されればOKです。",
            },
          ],
        },
      ],
    },
    {
      id: "html-basics",
      title: "HTML入門",
      description:
        "ウェブページの骨組みを作るための言語、HTML(HyperText Markup Language、" +
        "ウェブページの文章構造を決める言語)の基本を学びます。",
      lessons: [
        {
          id: "tags",
          title: "タグの基本",
          steps: [
            {
              id: "explain",
              type: "lesson",
              title: "タグとは",
              body:
                "タグ とは、< と > で囲まれた印(しるし)で、文章に「ここは見出しです」" +
                "「ここは段落です」のような意味を持たせるものです。\n\n" +
                "例: <h1>大見出し</h1>\n" +
                "<p>ここに文章を書きます</p>\n\n" +
                "多くのタグは <h1>〜</h1> のように、開始タグと終了タグ(/がついたタグ)で" +
                "中身をはさみます。",
            },
            {
              id: "fill-heading",
              type: "fill-blank",
              title: "空欄を埋めよう",
              body: "一番大きい見出しを作るタグ名を空欄に入れてください。",
              template: "<___0___>自己紹介</___0___>",
              blanks: [{ accepted: ["h1"] }],
              hint: "見出しタグは h1 〜 h6 まであり、h1が一番大きい見出しです。",
            },
            {
              id: "quiz-tag",
              type: "quiz",
              title: "クイズ",
              body: "段落(まとまった文章)を表すタグはどれでしょう?",
              choices: ["<p>", "<h1>", "<img>"],
              correctIndex: 0,
            },
          ],
        },
        {
          id: "links-images",
          title: "リンクと画像",
          steps: [
            {
              id: "explain",
              type: "lesson",
              title: "aタグとimgタグ",
              body:
                "リンク(他のページへの移動)を作るには a タグを使い、href という" +
                "属性(タグに追加情報を渡す書き方)にリンク先を指定します。\n\n" +
                "例: <a href=\"https://example.com\">サイトへ</a>\n\n" +
                "画像を表示するには img タグを使い、src属性で画像の場所を指定します。\n" +
                "例: <img src=\"photo.png\">",
            },
            {
              id: "fill-link",
              type: "fill-blank",
              title: "空欄を埋めよう",
              body: "リンク先を指定する属性名を空欄に入れてください。",
              template: '<a ___0___="https://example.com">サイトへ</a>',
              blanks: [{ accepted: ["href"] }],
              hint: "リンク先(移動先のURL)を指定する属性です。",
            },
            {
              id: "quiz-img",
              type: "quiz",
              title: "クイズ",
              body: "画像ファイルの場所を指定する属性はどれでしょう?",
              choices: ["src", "href", "alt"],
              correctIndex: 0,
            },
          ],
        },
      ],
    },
  ];

  // ---------------------------------------------------------------------
  // 正誤判定(採点)のロジック
  // ---------------------------------------------------------------------

  // 空欄(fill-blank)やコード出力の比較用に、前後の空白や改行の差を無視する正規化。
  function normalizeCode(s) {
    return String(s == null ? "" : s)
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line.length > 0)
      .join("\n");
  }

  function normalizeToken(s) {
    return String(s == null ? "" : s).trim();
  }

  function checkFillBlank(step, userAnswers) {
    const blanks = step.blanks || [];
    const answers = userAnswers || [];
    for (let i = 0; i < blanks.length; i++) {
      const given = normalizeToken(answers[i]);
      const accepted = blanks[i].accepted.map(normalizeToken);
      if (!accepted.includes(given)) {
        return { correct: false, blankIndex: i };
      }
    }
    return { correct: true };
  }

  function checkQuiz(step, choiceIndex) {
    return { correct: choiceIndex === step.correctIndex };
  }

  function checkCodeOutput(step, actualOutput) {
    const correct = normalizeCode(actualOutput) === normalizeCode(step.expectedOutput);
    return { correct };
  }

  // ステップの種類に応じて、上の判定関数へ振り分ける窓口。
  function checkAnswer(step, payload) {
    switch (step.type) {
      case "fill-blank":
        return checkFillBlank(step, payload);
      case "quiz":
        return checkQuiz(step, payload);
      case "code-output":
        return checkCodeOutput(step, payload);
      case "lesson":
        return { correct: true };
      default:
        return { correct: false };
    }
  }

  // ---------------------------------------------------------------------
  // 進捗(どこまで終えたか)の管理
  // ---------------------------------------------------------------------
  const STORAGE_KEY = "learningApp.progress.v1";
  const XP_PER_STEP = 10;

  function defaultProgress() {
    return { completedSteps: {}, xp: 0 };
  }

  function stepKey(courseId, lessonId, stepId) {
    return courseId + "/" + lessonId + "/" + stepId;
  }

  function loadProgress(storage) {
    try {
      const raw = storage.getItem(STORAGE_KEY);
      if (!raw) return defaultProgress();
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object") return defaultProgress();
      return {
        completedSteps: parsed.completedSteps && typeof parsed.completedSteps === "object" ? parsed.completedSteps : {},
        xp: typeof parsed.xp === "number" ? parsed.xp : 0,
      };
    } catch (e) {
      return defaultProgress();
    }
  }

  function saveProgress(storage, progress) {
    storage.setItem(STORAGE_KEY, JSON.stringify(progress));
  }

  function isStepCompleted(progress, courseId, lessonId, stepId) {
    return Boolean(progress.completedSteps[stepKey(courseId, lessonId, stepId)]);
  }

  // ステップを完了済みにして、保存し、更新後の進捗を返す。
  // 二重に完了させてもXPが増えすぎないようにしている(何度やり直しても加算は1回だけ)。
  function markStepComplete(storage, courseId, lessonId, stepId) {
    const progress = loadProgress(storage);
    const key = stepKey(courseId, lessonId, stepId);
    if (!progress.completedSteps[key]) {
      progress.completedSteps[key] = true;
      progress.xp += XP_PER_STEP;
    }
    saveProgress(storage, progress);
    return progress;
  }

  function isLessonCompleted(course, lesson, progress) {
    return lesson.steps.every((step) => isStepCompleted(progress, course.id, lesson.id, step.id));
  }

  // 1つ目のレッスンは常に開いている。2つ目以降は、直前のレッスンを
  // 全ステップ終えていないと開かない(Progateのような一本道の学習順序を作るため)。
  function isLessonUnlocked(course, lessonIndex, progress) {
    if (lessonIndex === 0) return true;
    const prevLesson = course.lessons[lessonIndex - 1];
    return isLessonCompleted(course, prevLesson, progress);
  }

  // レッスン内でも、1問目以降は直前のステップを終えないと進めない。
  function isStepUnlocked(course, lessonIndex, stepIndex, progress) {
    if (!isLessonUnlocked(course, lessonIndex, progress)) return false;
    if (stepIndex === 0) return true;
    const lesson = course.lessons[lessonIndex];
    const prevStep = lesson.steps[stepIndex - 1];
    return isStepCompleted(progress, course.id, lesson.id, prevStep.id);
  }

  function lessonProgressCount(course, lesson, progress) {
    const total = lesson.steps.length;
    const completed = lesson.steps.filter((step) => isStepCompleted(progress, course.id, lesson.id, step.id)).length;
    return { completed, total };
  }

  function courseProgressCount(course, progress) {
    let completed = 0;
    let total = 0;
    course.lessons.forEach((lesson) => {
      const c = lessonProgressCount(course, lesson, progress);
      completed += c.completed;
      total += c.total;
    });
    const percent = total === 0 ? 0 : Math.round((completed / total) * 100);
    return { completed, total, percent };
  }

  // 現在位置の次のステップ(レッスンをまたぐ場合も考慮)を返す。もう先がなければnull。
  function getNextPosition(course, lessonIndex, stepIndex) {
    const lesson = course.lessons[lessonIndex];
    if (stepIndex + 1 < lesson.steps.length) {
      return { lessonIndex, stepIndex: stepIndex + 1 };
    }
    if (lessonIndex + 1 < course.lessons.length) {
      return { lessonIndex: lessonIndex + 1, stepIndex: 0 };
    }
    return null;
  }

  function findCourse(courseId) {
    return COURSES.find((c) => c.id === courseId) || null;
  }

  const api = {
    COURSES,
    normalizeCode,
    checkAnswer,
    checkFillBlank,
    checkQuiz,
    checkCodeOutput,
    STORAGE_KEY,
    XP_PER_STEP,
    defaultProgress,
    stepKey,
    loadProgress,
    saveProgress,
    isStepCompleted,
    isLessonCompleted,
    isLessonUnlocked,
    isStepUnlocked,
    lessonProgressCount,
    courseProgressCount,
    getNextPosition,
    markStepComplete,
    findCourse,
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else {
    root.LearningCore = api;
  }
})(typeof window !== "undefined" ? window : globalThis);
