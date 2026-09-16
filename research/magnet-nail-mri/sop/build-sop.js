const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, Table, TableRow, TableCell,
  WidthType, ShadingType, BorderStyle, PageNumber, Header, Footer, LevelFormat, PageBreak,
  convertMillimetersToTwip
} = require("docx");
const fs = require("fs");

const FONT = "Meiryo";
const INK = "0F1626", TEAL = "1B9AAA", BERRY = "B5326A", MUTED = "6B7280", SLATE = "2E3A59";
const W = 9638;                         // 本文幅 (A4 - 左右余白20mm)
const HDR_BG = "2E3A59", TINT = "F2F4F8", WARN_BG = "FBE3E6", NOTE_BG = "E6F3F5";

const P = (text, o = {}) => new Paragraph({
  spacing: { before: o.before ?? 0, after: o.after ?? 100, line: o.line ?? 280 },
  alignment: o.align, indent: o.indent, border: o.border, shading: o.shading,
  children: [new TextRun({ text, font: FONT, size: o.size ?? 21, bold: o.bold, color: o.color ?? "1F2430", italics: o.it })],
});
const runs = (arr, o = {}) => new Paragraph({
  spacing: { before: o.before ?? 0, after: o.after ?? 100, line: 280 }, indent: o.indent,
  children: arr.map(a => new TextRun({ text: a.t, font: FONT, size: a.size ?? 21, bold: a.b, color: a.c ?? "1F2430" })),
});
const H1 = (n, t) => new Paragraph({
  heading: HeadingLevel.HEADING_1, spacing: { before: 320, after: 160 },
  children: [new TextRun({ text: `${n}　${t}`, font: FONT, size: 26, bold: true, color: INK })],
});
const H2 = (n, t) => new Paragraph({
  heading: HeadingLevel.HEADING_2, spacing: { before: 220, after: 120 },
  children: [new TextRun({ text: `${n}　${t}`, font: FONT, size: 22, bold: true, color: TEAL })],
});
const li = (text, ref, lvl = 0) => new Paragraph({
  numbering: { reference: ref, level: lvl }, spacing: { after: 80, line: 280 },
  children: [new TextRun({ text, font: FONT, size: 21 })],
});
const cell = (text, w, o = {}) => new TableCell({
  width: { size: w, type: WidthType.DXA },
  shading: o.fill ? { type: ShadingType.CLEAR, color: "auto", fill: o.fill } : undefined,
  margins: { top: 80, bottom: 80, left: 120, right: 120 },
  children: (Array.isArray(text) ? text : [text]).map(t => new Paragraph({
    spacing: { after: 0, line: 260 }, alignment: o.align,
    children: [new TextRun({ text: t, font: FONT, size: o.size ?? 20, bold: o.bold, color: o.color ?? (o.head ? "FFFFFF" : "1F2430") })],
  })),
});
const table = (widths, rows) => new Table({
  columnWidths: widths, width: { size: widths.reduce((a, b) => a + b, 0), type: WidthType.DXA },
  rows,
});
const hdrRow = (cells, widths) => new TableRow({
  tableHeader: true,
  children: cells.map((c, i) => cell(c, widths[i], { fill: HDR_BG, head: true, bold: true, align: AlignmentType.CENTER })),
});
const box = (title, lines, fill, titleColor) => table([W], [
  new TableRow({ children: [new TableCell({
    width: { size: W, type: WidthType.DXA },
    shading: { type: ShadingType.CLEAR, color: "auto", fill },
    margins: { top: 140, bottom: 140, left: 180, right: 180 },
    children: [
      new Paragraph({ spacing: { after: 80 }, children: [new TextRun({ text: title, font: FONT, size: 21, bold: true, color: titleColor })] }),
      ...lines.map(l => new Paragraph({ spacing: { after: 40, line: 270 }, children: [new TextRun({ text: l, font: FONT, size: 20 })] })),
    ],
  })] }),
]);
const gap = (h = 120) => new Paragraph({ spacing: { after: h }, children: [] });

// ---- 手順セクションの共通部品 ----
function procHeader(rows) {
  const w = [1800, W - 1800];
  return table(w, rows.map(([k, v]) => new TableRow({
    children: [cell(k, w[0], { fill: TINT, bold: true }), cell(v, w[1])],
  })));
}

const numbering = {
  config: [
    { reference: "bul", levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 420, hanging: 220 } } } }] },
    ...["prep", "sa", "sb", "sc", "sd", "se1", "se3", "abort", "pack"].map(ref => ({
      reference: ref,
      levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 460, hanging: 320 } } } }],
    })),
  ],
};

const children = [];

/* ===================== 表紙ブロック ===================== */
children.push(new Paragraph({
  spacing: { after: 60 },
  children: [new TextRun({ text: "実験手順書（SOP）", font: FONT, size: 20, bold: true, color: TEAL })],
}));
children.push(new Paragraph({
  spacing: { after: 200 },
  border: { bottom: { style: BorderStyle.SINGLE, size: 12, color: INK, space: 8 } },
  children: [new TextRun({ text: "マグネットネイル装着者のMRI検査に関する定量評価", font: FONT, size: 32, bold: true, color: INK })],
}));
{
  const w = [1700, 3100, 1700, 3138];
  children.push(table(w, [
    new TableRow({ children: [
      cell("文書番号", w[0], { fill: TINT, bold: true }), cell("MN-MRI-SOP-001", w[1]),
      cell("版数", w[2], { fill: TINT, bold: true }), cell("第 1.0 版", w[3]) ] }),
    new TableRow({ children: [
      cell("作成日", w[0], { fill: TINT, bold: true }), cell("　　　年　　月　　日", w[1]),
      cell("発効日", w[2], { fill: TINT, bold: true }), cell("　　　年　　月　　日", w[3]) ] }),
    new TableRow({ children: [
      cell("作成者", w[0], { fill: TINT, bold: true }), cell("", w[1]),
      cell("承認者", w[2], { fill: TINT, bold: true }), cell("", w[3]) ] }),
    new TableRow({ children: [
      cell("適用施設・装置", w[0], { fill: TINT, bold: true }),
      new TableCell({ columnSpan: 3, width: { size: w[1] + w[2] + w[3], type: WidthType.DXA },
        margins: { top: 80, bottom: 80, left: 120, right: 120 },
        children: [new Paragraph({ spacing: { after: 0 }, children: [] })] }) ] }),
  ]));
}
children.push(gap(200));
children.push(box("この手順書を読む前に", [
  "本手順書は人体を対象としません。撮影はすべてファントム（人体を模した試験体）で行います。自分自身の手を含め、いかなる人体も撮影の対象にしないでください。",
  "強力磁石（ネオジム磁石）は、いかなる理由があってもMRI検査室に持ち込まないでください。試料の模様付けと硬化は検査室外で完了させ、硬化済みの試料のみを持ち込みます。",
  "作業は必ず2名以上で行い、時間外の単独作業は禁止します。",
], WARN_BG, BERRY));

children.push(gap(200));
children.push(P("目次", { bold: true, size: 22, color: INK, after: 80 }));
[
  "1. 目的", "2. 適用範囲", "3. 安全上の遵守事項", "4. 体制と役割", "5. 機材・消耗品",
  "6. 事前準備", "7. 手順A：磁気吸引力の測定（ASTM F2052）", "8. 手順B：画像アーチファクトの測定（ASTM F2119）",
  "9. 手順C：発熱の評価（示温ラベル法）", "10. 手順D：磁性粉の配向異方性", "11. 手順E-1：延期症例の後ろ向き調査",
  "12. 手順E-3：簡易磁石テストの性能評価", "13. 測定順序とバイアス対策", "14. データの記録と管理",
  "15. 中止基準と異常時の対応", "16. 撤収手順", "17. 記録様式一覧", "18. 改訂履歴",
].forEach(t => children.push(P(t, { size: 20, after: 30, indent: { left: 240 } })));

children.push(new Paragraph({ children: [new PageBreak()] }));

/* ===================== 1. 目的 ===================== */
children.push(H1(1, "目的"));
children.push(P("本手順書は、マグネットネイル（磁性粉を含むジェルネイル）がMRI検査に与える影響を定量的に評価するための実験手順を定める。"));
children.push(P("評価の目的は、現行の「マグネットネイル装着者は一律に延期し、除去後に再予約する」という運用が、物理的根拠に照らして妥当かを検証し、必要であれば部位別の運用に置き換えるための根拠を得ることにある。"));
children.push(gap(60));
children.push(P("評価する干渉経路は次の4つとする。", { bold: true, after: 60 }));
{
  const w = [700, 2400, W - 700 - 2400 - 1500, 1500];
  children.push(table(w, [
    hdrRow(["#", "経路", "評価する内容", "位置づけ"], w),
    ...[
      ["①", "磁気吸引力・トルク", "静磁場勾配により試料が受ける力。剥離の可能性", "主軸（手順A）"],
      ["②", "画像アーチファクト", "磁化率差による信号消失域の広がりと、距離による減衰", "主軸（手順B）"],
      ["③", "RF発熱", "導電性フレークへの渦電流誘導による温度上昇", "補助（手順C）"],
      ["④", "配向異方性", "磁性粉の整列方向が①②に与える影響", "発展（手順D）"],
    ].map((r, i) => new TableRow({ children: r.map((t, j) => cell(t, w[j], { fill: i % 2 ? undefined : TINT, align: j === 0 ? AlignmentType.CENTER : undefined })) })),
  ]));
}

/* ===================== 2. 適用範囲 ===================== */
children.push(H1(2, "適用範囲"));
children.push(P("本手順書は、本研究に従事するすべての者に適用する。実機を用いる手順A・B・C・Dは、診療放射線技師の監督下でのみ実施できる。"));
children.push(P("手順E-1（後ろ向き調査）および手順E-3（簡易テストの性能評価）は、実機を使用しないため、別途院内の承認手続きに従って実施する。"));

/* ===================== 3. 安全 ===================== */
children.push(H1(3, "安全上の遵守事項"));
children.push(P("以下は例外を認めない。1つでも満たせない場合、その日の作業は実施しない。", { bold: true, color: BERRY }));
{
  const w = [600, 3000, W - 600 - 3000];
  const rows = [
    ["1", "人体を撮影しない", "自分自身の手を含め、いかなる人体も撮影の対象にしない。撮影はファントムのみ。"],
    ["2", "強力磁石を持ち込まない", "ネオジム磁石は検査室に持ち込まない。模様付けと硬化は検査室外で完了させ、硬化済み試料のみ持ち込む。"],
    ["3", "磁性体・金属を持ち込まない", "金属製の温度計・工具・治具・クリップ類を持ち込まない。治具は樹脂・木材など非磁性材で製作する。"],
    ["4", "試料を固定し索を付ける", "微小な試料でも吸着の可能性を前提とする。全試料を確実に固定し、回収用の索を付ける。"],
    ["5", "2名以上で実施する", "時間外の単独作業を禁止する。緊急時の対応者を確保する。"],
    ["6", "中止基準を事前共有する", "異音、試料のズレ、示温ラベルの想定外の変色を認めた場合は即時中断する（第15章）。"],
    ["7", "持ち込み物を記録する", "入室前と退室後に持ち込み物を数え、一致を確認する。"],
    ["8", "院内の承認を得る", "データの利用範囲、施設名・装置機種の公表可否について事前に承認を得る。"],
  ];
  children.push(table(w, [
    hdrRow(["#", "遵守事項", "内容"], w),
    ...rows.map((r, i) => new TableRow({ children: r.map((t, j) => cell(t, w[j], { fill: i % 2 ? undefined : TINT, align: j === 0 ? AlignmentType.CENTER : undefined })) })),
  ]));
}
children.push(gap(120));
children.push(box("なぜ強力磁石の持ち込みが特に危険か", [
  "ネオジム磁石は静磁場に強く引かれ、手から離れた瞬間にガントリーへ高速で飛翔する。装置の損傷だけでなく、経路上にいる人に重傷を負わせる。作業の都合でその場に持ち込みたくなる場面が必ず生じるが、例外を作らないこと。",
], WARN_BG, BERRY));

/* ===================== 4. 体制 ===================== */
children.push(H1(4, "体制と役割"));
{
  const w = [2200, 2600, W - 2200 - 2600];
  children.push(table(w, [
    hdrRow(["役割", "担当", "責務"], w),
    ...[
      ["実施責任者", "", "全体の統括。中止判断。院内手続き。記録の最終確認。"],
      ["撮影担当", "", "装置の操作。撮影条件の設定と記録。"],
      ["試料担当", "", "試料の作製・搬入・設置・回収。点数の照合。"],
      ["記録担当", "", "ワークブックへの入力。撮影ログと安全チェックリストの記入。"],
    ].map((r, i) => new TableRow({ children: r.map((t, j) => cell(t, w[j], { fill: i % 2 ? undefined : TINT })) })),
  ]));
}
children.push(gap(80));
children.push(P("1名が複数の役割を兼ねてよいが、実施責任者と撮影担当を同一人物が兼ねる場合でも、立会者を含め必ず2名以上とする。", { size: 20, color: MUTED }));

/* ===================== 5. 機材 ===================== */
children.push(H1(5, "機材・消耗品"));
{
  const w = [2600, W - 2600 - 1400, 1400];
  const mk = (rows) => table(w, [hdrRow(["品目", "仕様・用途", "数量"], w),
    ...rows.map((r, i) => new TableRow({ children: r.map((t, j) => cell(t, w[j], { fill: i % 2 ? undefined : TINT, align: j === 2 ? AlignmentType.CENTER : undefined })) }))]);
  children.push(H2("5.1", "試料の作製"));
  children.push(mk([
    ["マグネットネイル", "供試製品。製品名は伏せて製品A・B…と記号化する", "10製品以上"],
    ["対照試料", "透明ジェル、カラージェル、ラメ入り", "各1"],
    ["ネイルチップ", "規格の揃った付け爪。爪の個体差を排除するため", "各条件 10枚"],
    ["UVライト", "硬化用", "1"],
    ["ネオジム磁石", "模様付け用。検査室には持ち込まない", "1"],
    ["精密秤", "0.001 g 単位。塗布量の管理", "1"],
  ]));
  children.push(H2("5.2", "測定"));
  children.push(mk([
    ["非磁性吊り下げ治具", "樹脂・木材製。釣り糸と分度器。手順Aで使用", "1"],
    ["ファントム", "硫酸銅水溶液または寒天。手順Bで使用", "1"],
    ["固定材", "非磁性のテープ・面ファスナー。試料の固定用", "適量"],
    ["回収用の索", "全試料に取り付ける", "試料数分"],
    ["不可逆性示温ラベル", "40 / 45 / 50 / 55 / 60℃ の複数温度段", "試料数分"],
    ["角度測定", "分度器、または傾斜角測定アプリを入れた端末", "1"],
    ["ImageJ", "画像解析用。PCにインストールしておく", "1"],
  ]));
}

/* ===================== 6. 事前準備 ===================== */
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(H1(6, "事前準備"));

children.push(H2("6.1", "試料の作製"));
children.push(P("すべて検査室外で行う。", { size: 20, color: BERRY, bold: true }));
[
  "ネイルチップを秤に載せ、施術前の質量を 0.001 g 単位で記録する。",
  "ジェルを塗布する。塗布量は条件間でそろえる。塗布後の質量との差を塗布量として記録する。",
  "マグネットネイルの配列条件に従い、磁石を所定の向きで当てて磁性粉を整列させる（未配列の試料には磁石を当てない）。",
  "UVライトで硬化させる。硬化時間は製品の指示に従い、条件間でそろえる。",
  "硬化後の質量を測定し、塗布量を確定する。",
  "試料IDを油性ペンで裏面に記入し、回収用の索を取り付ける。",
  "ワークブック「01_試料マスタ」に、試料ID・製品記号・カテゴリ・色・ロット・施術日・磁石配列・塗布量を登録する。",
].forEach(t => children.push(li(t, "prep")));
children.push(gap(60));
children.push(box("塗布量をそろえる理由", [
  "アーチファクトの大きさも吸引力も、含まれる磁性粉の量に依存する。塗布量がばらつくと、製品間の差なのか塗布量の差なのかが区別できなくなる。秤で管理し、実測値を必ず残すこと。",
], NOTE_BG, TEAL));

children.push(H2("6.2", "非磁性治具の準備"));
children.push(P("手順Aで使用する吊り下げ治具を、樹脂・木材など非磁性材で製作する。金属のねじ・クリップを使わないこと。糸は釣り糸など軽量で伸びの少ないものを用いる。"));
children.push(P("製作後、治具単体を静磁場に近づけ、治具自体が力を受けないことを確認する。治具が振れる場合は磁性材が混入しているため、作り直す。", { bold: true }));

children.push(H2("6.3", "ファントムの準備"));
children.push(P("硫酸銅水溶液または寒天でファントムを作製する。気泡が残ると信号欠損と紛らわしいため、静置して気泡を抜く。試料を規則的に配置できるよう、非磁性の固定材をあらかじめ用意する。"));

children.push(H2("6.4", "空間磁場勾配マップの確認"));
children.push(P("装置ごとに、メーカーの空間磁場勾配マップから ∂B/∂z が最大となる位置を特定し、記録する。"));
children.push(box("ガウスラインマップと取り違えないこと", [
  "吸引力を決めるのは磁場強度 B ではなく B・(∂B/∂z) である。ガウスラインマップ（磁場強度の等高線）ではなく、空間磁場勾配マップを参照する。",
  "最大勾配位置は多くの装置でボア入口付近の体軸上にあるが、機種差がある。マップ上の位置を、試験片を吊るして振れが最大になる点を探る方法で実測確認し、その結果も記録する。",
], NOTE_BG, TEAL));

/* ===================== 7. 手順A ===================== */
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(H1(7, "手順A：磁気吸引力の測定（ASTM F2052 準拠）"));
children.push(procHeader([
  ["目的", "試料が静磁場から受ける磁気力を偏向角として定量し、規格の許容基準と照合する"],
  ["装置", "1.5T および 3T"],
  ["試料数", "各試料 × 各装置 で n = 10"],
  ["所要時間", "1装置あたり 2〜3 時間（試料数による）"],
  ["記録先", "ワークブック「02_偏向角_記録」"],
]));
children.push(gap(120));
children.push(H2("7.1", "手順"));
[
  "検査室に入る前に、第3章の遵守事項と第15章の中止基準を全員で読み合わせる。安全チェックリスト（11_安全チェックリスト）の実施前項目を確認し、記入する。",
  "持ち込む試料と治具の点数を数え、記録する。",
  "治具を、6.4 で特定した最大空間磁場勾配位置に設置する。設置位置は毎回同一とし、床面にマーキングしておく。",
  "試料を糸で吊るす。静止するまで待つ。",
  "糸の傾き角 θ を測定し、0.5° 単位で読む。",
  "試料を一度取り外し、再度取り付けてから測定する。これを 10 回繰り返す。取り外して付け直すことで、設置のばらつきを含めた再現性が評価できる。",
  "測定ごとに、測定ID・測定日・装置・試料ID・反復No・質量・偏向角・測定者をワークブックに記録する。磁気力と45°判定は自動計算される。",
  "全試料について 3〜7 を繰り返す。試料の測定順序は 13.1 に従って無作為化する。",
  "トルク（ASTM F2213）は、試料を低摩擦の非磁性台に載せ、磁場中で回転するかを観察して定性的に評価し、備考欄に記録する。",
  "終了後、試料を全数回収し、点数の一致を確認する。安全チェックリストの実施後項目を記入する。",
].forEach(t => children.push(li(t, "sa")));
children.push(gap(60));
children.push(H2("7.2", "判定"));
children.push(runs([
  { t: "磁気力 F = m・g・tan θ", b: true, size: 22 },
  { t: "　（m：試料質量、g：重力加速度、θ：偏向角）", c: MUTED, size: 19 },
]));
children.push(P("ASTM F2052 は θ < 45°、すなわち磁気力が重力以下であることを一般に許容可能とする。この基準に照らして各試料を判定する。同一試料・同一装置で 45° 以上の測定が1件でもあれば「要確認」とし、その試料は追加で検討する。"));

/* ===================== 8. 手順B ===================== */
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(H1(8, "手順B：画像アーチファクトの測定（ASTM F2119 準拠）"));
children.push(procHeader([
  ["目的", "信号消失域の大きさを、磁場強度・シーケンス・TE・距離の関数として定量する"],
  ["装置", "1.5T および 3T"],
  ["反復", "各条件 n = 3 以上（主要条件は n = 5）"],
  ["所要時間", "1装置あたり 4〜6 時間。複数日に分けてよい"],
  ["記録先", "ワークブック「04_アーチファクト_記録」"],
]));
children.push(gap(120));
children.push(H2("8.1", "撮影マトリクス"));
{
  const w = [3000, W - 3000];
  children.push(table(w, [
    hdrRow(["因子", "水準"], w),
    ...[
      ["磁場強度", "1.5T / 3T"],
      ["シーケンス", "SE / TSE / GRE / EPI / 脂肪抑制"],
      ["TE", "GRE で 5 段階（例：5・10・15・20・30 ms）"],
      ["受信バンド幅", "3 段階"],
      ["周波数エンコード方向", "2 方向"],
      ["試料からの距離", "0 / 2 / 5 / 10 / 20 cm"],
      ["配置角度", "0° / 45° / 90°（手順Dと共有）"],
    ].map((r, i) => new TableRow({ children: r.map((t, j) => cell(t, w[j], { fill: i % 2 ? undefined : TINT })) })),
  ]));
}
children.push(gap(120));
children.push(H2("8.2", "手順"));
[
  "第3章の遵守事項を確認し、安全チェックリストの実施前項目を記入する。持ち込み点数を数える。",
  "ファントムを寝台に設置する。位置は毎回同一とし、再現できるようマーキングする。",
  "試料を装着しない状態で、使用するすべてのシーケンスについて参照画像を撮影する。参照画像はASTM F2119のアーチファクト判定の基準となるため、省略しない。",
  "試料をファントム表面の所定位置に固定する。固定が緩いと撮影中に動き、測定値が無効になる。",
  "撮影マトリクスに従って撮影する。1条件ごとに、撮影条件をすべてワークブックに記録する。",
  "距離を変える条件では、試料の位置のみを変え、ファントムと寝台の位置は動かさない。",
  "各撮影の直後に、試料の位置がずれていないことを目視で確認する。ずれていた場合はその条件を再撮影し、備考にその旨を記録する。",
  "全条件の撮影終了後、試料を全数回収し、点数の一致を確認する。安全チェックリストの実施後項目を記入する。",
].forEach(t => children.push(li(t, "sb")));
children.push(gap(120));
children.push(H2("8.3", "画像の計測"));
children.push(P("計測は検査室外で、撮影とは別の日に行ってよい。"));
children.push(P("ASTM F2119 の定義に従い、参照画像との画素値の差が 30% を超える領域をアーチファクトとする。ImageJ で閾値処理を行い、面積（mm²）と最大径（mm）を計測してワークブックに記録する。", { after: 60 }));
children.push(box("計測の客観性を確保する", [
  "計測者には撮影条件（装置・シーケンス・試料）を伏せた状態で計測させる。ファイル名を無作為な記号に置き換えてから渡すとよい。",
  "主要な条件については2名が独立に計測し、値の一致度を確認する。大きく食い違う条件は、閾値処理の手順を見直す。",
  "閾値処理の手順（前処理・閾値の決め方・面積の取り方）を文書化し、全画像で同一の手順を適用する。途中で手順を変えない。",
], NOTE_BG, TEAL));

/* ===================== 9. 手順C ===================== */
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(H1(9, "手順C：発熱の評価（示温ラベル法）"));
children.push(procHeader([
  ["目的", "高SAR条件での最高到達温度を記録し、熱傷リスクの有無を評価する"],
  ["装置", "1.5T および 3T"],
  ["反復", "各条件 n = 10"],
  ["所要時間", "1条件あたり 30〜40 分"],
  ["記録先", "ワークブック「06_発熱_記録」"],
]));
children.push(gap(120));
children.push(box("本手順は ASTM F2182 準拠ではない", [
  "MRI対応の光ファイバー温度計が使用できないため、規格準拠のRF発熱測定は実施できない。本手順は不可逆性示温ラベルによる最高到達温度の記録で代替するものであり、以下の限界を伴う。発表・論文では必ずこの限界を明記すること。",
  "・温度の時間変化（上昇速度、定常値、時定数）は取得できない。",
  "・ファントムは血流による冷却を再現していないため、生体より高温側に出る。すなわち安全側の評価となる。",
  "・温度分解能は示温ラベルの温度段に制限される。",
], WARN_BG, BERRY));
children.push(gap(120));
children.push(H2("9.1", "手順"));
[
  "試料に不可逆性示温ラベルを貼付する。40・45・50・55・60℃ の複数温度段をすべて貼る。",
  "貼付直後の状態を写真に記録する（変色の有無の判定基準とする）。",
  "試料をファントムに固定する。位置は手順Bと同一とする。",
  "高SARシーケンス（TSE、大フリップ角、短TR）を選択し、SAR値を記録する。",
  "30分間連続で撮像する。撮像中は操作室から試料の状態を監視する。",
  "撮像終了後、速やかに試料を取り出し、各温度段のラベルの変色の有無を判定して記録する。ラベルは不可逆であるため、取り出しまでの時間は判定に影響しない。",
  "補助として、取り出し直後に非接触赤外温度計で表面温度を測定し、備考欄に記録する。ただし遅延により過小評価となることを明記する。",
  "対照として、試料を貼らないファントムでも同一条件を実施し、ラベルが変色しないことを確認する。",
].forEach(t => children.push(li(t, "sc")));
children.push(gap(60));
children.push(P("推定最高到達温度はワークブックで自動判定される。40℃段階でも変色が見られない場合、それ自体が有用な陰性所見であり、無理に主軸に据える必要はない。", { size: 20, color: MUTED }));

/* ===================== 10. 手順D ===================== */
children.push(H1(10, "手順D：磁性粉の配向異方性"));
children.push(procHeader([
  ["目的", "硬化時の磁性粉の整列方向が、吸引力とアーチファクトを変えるかを検証する"],
  ["試料", "同一製品・同一塗布量で、磁石の当て方のみを変えたもの"],
  ["条件", "配列：未配列 / 縦 / 横 / 斜め　×　静磁場に対する配置角度：0° / 45° / 90°"],
  ["記録先", "「02_偏向角_記録」および「04_アーチファクト_記録」の配置角度欄"],
]));
children.push(gap(120));
[
  "6.1 の手順で、磁石の当て方のみを変えた試料を作製する。塗布量は条件間で必ずそろえる。",
  "手順Aと同一の方法で、配置角度 0°・45°・90° の各々について偏向角を測定する。",
  "手順Bと同一の方法で、同じ3つの配置角度についてアーチファクトを撮影・計測する。",
  "配列条件と配置角度の組み合わせごとに集計し、差の有無を検定する。",
].forEach(t => children.push(li(t, "sd")));
children.push(gap(60));
children.push(box("差が出なくても報告価値がある", [
  "先行研究は磁性粉を含む化粧品としてしか扱っておらず、「粉が揃って固まっている」というマグネットネイル固有の条件を検討したものは見当たらない。有意差が出なければ「整列の向きは影響しない」という知見として報告できる。空振りを恐れて省略しないこと。",
], NOTE_BG, TEAL));

/* ===================== 11. 手順E-1 ===================== */
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(H1(11, "手順E-1：延期症例の後ろ向き調査"));
children.push(procHeader([
  ["目的", "現行運用が患者と施設にもたらしている負担を定量する"],
  ["対象", "調査対象期間内に、ネイルを理由に延期となった全症例"],
  ["実機", "使用しない。実験と並行して着手できる"],
  ["記録先", "ワークブック「07_延期症例」"],
]));
children.push(gap(120));
children.push(H2("11.1", "手順"));
[
  "院内の承認手続きを経る。データの利用範囲と公表可否を事前に確認する。",
  "調査対象期間を決める（試験運用の前後比較を行う場合は、変更前6か月・変更後6か月など対称に取る）。",
  "予約・実施記録から、ネイルを理由に延期となった症例を抽出する。",
  "各症例について、症例No・依頼日・初回予約日・実施日・撮影部位・ネイル種別・延期の有無・延期理由・未受検の該当を記録する。症例Noは連番とし、個人が特定できる情報は記録しない。",
  "延期しなかった症例も対照として同様に記録する。日数の比較に必要となる。",
  "延期後に再予約されず、検査が実施されないまま終わった症例を「未受検」として漏れなく拾う。",
  "可能であれば、問診票の記載と実際のネイル種別が一致していたかを確認し、備考に記録する。",
].forEach(t => children.push(li(t, "se1")));
children.push(gap(120));
children.push(box("拾い漏らしてはいけない2つの指標", [
  "依頼日から実施日までの日数：件数よりもこちらが効く。「年間○件の延期」は行政的な数字だが、「診断が中央値○日遅れている」は臨床の数字である。",
  "未受検（脱落）症例：延期後に再予約されず終わった症例。一定数いるなら、安全のための運用が「未受検」という別のリスクを生んでいることになる。本研究で最も重い指摘になりうる。",
], WARN_BG, BERRY));
children.push(gap(120));
children.push(P("撮影部位の内訳は必ず取る。手順Bで距離依存性が示せた場合、頭部・体幹部の延期件数がそのまま「回避できたはずの遅れ」として提示できる。", { bold: true }));

/* ===================== 12. 手順E-3 ===================== */
children.push(H1(12, "手順E-3：簡易磁石テストの性能評価"));
children.push(procHeader([
  ["目的", "受付や更衣室で数秒で行える判定法が、実用に足る精度を持つか評価する"],
  ["正解ラベル", "手順A・手順Bの結果から決めた「磁性あり／なし」"],
  ["記録先", "ワークブック「09_スクリーニング検証」"],
]));
children.push(gap(120));
[
  "テストの手順を定める（磁石の種類、爪からの距離、判定にかける時間）。手順は全試料で同一とする。",
  "判定者には、その試料が何であるかを伏せた状態で判定させる。",
  "各試料について、テスト結果（陽性／陰性）と基準判定（磁性あり／なし）を記録する。",
  "2×2表から感度・特異度・陽性的中率・陰性的中率・正確度を算出する（ワークブックで自動計算される）。",
  "判定者を変えて再度実施し、判定者間の一致度を確認する。",
].forEach(t => children.push(li(t, "se3")));
children.push(gap(60));
children.push(P("受付で使うテストであるため、重視すべきは感度（磁性ありを見逃さないこと）である。特異度が多少低くても、見逃しが少ないほうが運用上望ましい。", { bold: true, color: BERRY }));

/* ===================== 13. バイアス対策 ===================== */
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(H1(13, "測定順序とバイアス対策"));
children.push(H2("13.1", "無作為化"));
children.push(P("試料の測定順序は、条件ごとにまとめず、乱数を用いて無作為化する。装置の状態や測定者の慣れが特定の条件に偏って影響することを避けるためである。使用した順序は記録に残す。"));
children.push(H2("13.2", "盲検化"));
children.push(P("画像計測（8.3）と簡易磁石テストの判定（手順E-3）は、対象の素性を伏せた状態で行う。ファイル名や試料の外観から条件が分かる場合は、記号に置き換えてから渡す。"));
children.push(H2("13.3", "反復数"));
children.push(P("各条件 n は手順ごとに定めた値を下限とする。時間に余裕がある場合は増やしてよいが、条件間で n を大きく変えない。撮影枠の制約が小さいという本研究の利点は、ここに充てるのが最も効果的である。"));
children.push(H2("13.4", "記録のタイミング"));
children.push(P("測定値はその場でワークブックに記録する。メモから後でまとめて転記する方法は、転記ミスと記憶による補正が入るため行わない。"));

/* ===================== 14. データ管理 ===================== */
children.push(H1(14, "データの記録と管理"));
{
  const w = [3200, W - 3200];
  children.push(table(w, [
    hdrRow(["項目", "取り扱い"], w),
    ...[
      ["記録先", "ワークブック（magnet-nail-mri_workbook.xlsx）。黄色のセルのみ入力し、灰色の自動計算セルは上書きしない"],
      ["画像データ", "装置から書き出し、撮影日・装置・条件が分かる規則でファイル名を付けて保存する"],
      ["バックアップ", "作業日ごとに複製を取る。複製先は院内の規定に従う"],
      ["個人情報", "症例Noは連番とし、氏名・ID・生年月日は記録しない"],
      ["公表", "施設名・装置機種の公表可否は事前に院内の承認を得る"],
      ["保管期間", "院内規定に従う"],
    ].map((r, i) => new TableRow({ children: r.map((t, j) => cell(t, w[j], { fill: i % 2 ? undefined : TINT })) })),
  ]));
}

/* ===================== 15. 中止基準 ===================== */
children.push(H1(15, "中止基準と異常時の対応"));
children.push(P("次のいずれかを認めた場合、直ちに撮像を中断する。判断に迷う場合は中断を選ぶ。", { bold: true, color: BERRY }));
[
  "装置から異音がした。",
  "試料の位置がずれた、または脱落した。",
  "示温ラベルが想定外の温度段で変色した。",
  "試料の外観に変化（変形・変色・剥離）が生じた。",
  "治具に想定外の動きが見られた。",
  "その他、実施者の誰かが危険を感じた。",
].forEach(t => children.push(li(t, "abort")));
children.push(gap(120));
children.push(H2("15.1", "中断後の対応"));
children.push(P("1. 撮像を停止し、寝台を退室位置まで戻す。　2. 実施責任者に報告する。　3. 試料と治具を回収し、点数を確認する。　4. 状況・時刻・条件を撮影ログの特記事項に記録する。　5. 原因が特定できるまで、同一条件での再実施は行わない。"));
children.push(gap(60));
children.push(box("吸着が起きた場合", [
  "試料や治具が装置に吸着した場合、無理に引き剥がさない。装置の緊急停止（クエンチ）は重大な措置であり、実施責任者以外は判断しない。施設の緊急時手順に従うこと。",
], WARN_BG, BERRY));

/* ===================== 16. 撤収 ===================== */
children.push(H1(16, "撤収手順"));
[
  "全試料を回収し、持ち込み時の点数と一致することを確認する。",
  "治具・固定材・示温ラベルの残りを回収する。",
  "ファントムを片付け、寝台とガントリー内に持ち込み物が残っていないことを目視で確認する。",
  "装置を通常の状態に戻す。",
  "撮影ログ（10_撮影ログ）に、実施日・装置・開始終了時刻・目的・立会者・試料点数・特記事項を記入する。",
  "安全チェックリスト（11_安全チェックリスト）の実施後項目を記入し、実施者が署名する。",
  "その日の測定値がワークブックに入力済みであることを確認する。",
].forEach(t => children.push(li(t, "pack")));

/* ===================== 17. 記録様式 ===================== */
children.push(H1(17, "記録様式一覧"));
children.push(P("記録はすべてワークブック（magnet-nail-mri_workbook.xlsx）に集約する。", { after: 80 }));
{
  const w = [3400, 1500, W - 3400 - 1500];
  children.push(table(w, [
    hdrRow(["シート", "対応手順", "内容"], w),
    ...[
      ["01_試料マスタ", "6.1", "供試試料の台帳。最初に登録する"],
      ["02_偏向角_記録", "手順A", "偏向角の生データ。磁気力と45°判定は自動"],
      ["03_偏向角_集計", "手順A", "試料×装置の集計。入力不要"],
      ["04_アーチファクト_記録", "手順B・D", "撮影条件と計測値"],
      ["05_アーチファクト_集計", "手順B", "シーケンス別・TE別・距離別の集計。入力不要"],
      ["06_発熱_記録", "手順C", "示温ラベルの変色と推定最高到達温度"],
      ["07_延期症例", "手順E-1", "後ろ向き調査の生データ"],
      ["08_延期集計", "手順E-1", "延期率・日数・部位別内訳。入力不要"],
      ["09_スクリーニング検証", "手順E-3", "2×2表と感度・特異度。入力不要"],
      ["10_撮影ログ", "第16章", "実施記録"],
      ["11_安全チェックリスト", "第3・16章", "実施前後の確認"],
    ].map((r, i) => new TableRow({ children: r.map((t, j) => cell(t, w[j], { fill: i % 2 ? undefined : TINT })) })),
  ]));
}

/* ===================== 18. 改訂履歴 ===================== */
children.push(H1(18, "改訂履歴"));
{
  const w = [1200, 1800, W - 1200 - 1800 - 1800, 1800];
  children.push(table(w, [
    hdrRow(["版数", "改訂日", "改訂内容", "承認者"], w),
    new TableRow({ children: [cell("1.0", w[0], { align: AlignmentType.CENTER }), cell("", w[1]), cell("初版", w[2]), cell("", w[3])] }),
    ...[0, 1, 2].map(() => new TableRow({ children: w.map(x => cell("", x)) })),
  ]));
}
children.push(gap(200));
children.push(P("本手順書は、研究計画書（PRESENTATION_PLAN.md）の案A〜案F に対応する。計画を変更した場合は、本手順書も改訂し、版数を更新すること。", { size: 20, color: MUTED }));

/* ===================== 出力 ===================== */
const doc = new Document({
  numbering,
  styles: {
    default: {
      document: { run: { font: FONT, size: 21, color: "1F2430" }, paragraph: { spacing: { line: 280 } } },
      heading1: { run: { font: FONT, size: 26, bold: true, color: INK } },
      heading2: { run: { font: FONT, size: 22, bold: true, color: TEAL } },
    },
  },
  sections: [{
    properties: {
      page: {
        size: { width: convertMillimetersToTwip(210), height: convertMillimetersToTwip(297) },
        margin: { top: convertMillimetersToTwip(20), bottom: convertMillimetersToTwip(20),
                  left: convertMillimetersToTwip(20), right: convertMillimetersToTwip(20) },
      },
    },
    headers: { default: new Header({ children: [new Paragraph({
      alignment: AlignmentType.RIGHT, spacing: { after: 0 },
      children: [new TextRun({ text: "MN-MRI-SOP-001　第1.0版", font: FONT, size: 16, color: MUTED })],
    })] }) },
    footers: { default: new Footer({ children: [new Paragraph({
      alignment: AlignmentType.CENTER, spacing: { before: 0 },
      children: [new TextRun({ children: ["", PageNumber.CURRENT, " / ", PageNumber.TOTAL_PAGES], font: FONT, size: 16, color: MUTED })],
    })] }) },
    children,
  }],
});

Packer.toBuffer(doc).then(buf => {
  const out = process.argv[2] || "sop.docx";
  fs.writeFileSync(out, buf);
  console.log("written:", out, buf.length, "bytes");
});
