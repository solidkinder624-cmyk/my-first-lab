const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";            // 13.33 x 7.5 in
pres.author = "";
pres.title = "マグネットネイル装着者のMRI検査";

// ---- palette (MRIモニタの黒 × 画像の青緑 × ネイルのベリー) ----
const INK   = "0F1626";
const INK2  = "1C2437";
const SLATE = "2E3A59";
const BERRY = "B5326A";
const TEAL  = "1B9AAA";
const PAPER = "FFFFFF";
const MIST  = "F2F4F8";
const MUTED = "6B7280";
const TEXT  = "1F2430";
const AMBER = "C2700F";
const F = "Meiryo";

const W = 13.33, H = 7.5, M = 0.7;

function sh(){ return { type:"outer", color:"9AA5B5", blur:8, offset:2, angle:90, opacity:0.25 }; }

// 見出し（light slide）
function head(s, no, title, kicker){
  if (kicker){
    s.addText(kicker, { x:M, y:0.42, w:W-2*M-1.1, h:0.28, isTextBox:true, margin:0,
      fontFace:F, fontSize:12, bold:true, color:TEAL, charSpacing:2 });
  }
  s.addText(title, { x:M, y: kicker?0.72:0.55, w:W-2*M-1.1, h:0.8, isTextBox:true, margin:0,
    fontFace:F, fontSize:30, bold:true, color:INK, valign:"top" });
  // motif: 右上のスライド番号バッジ
  s.addShape(pres.ShapeType.ellipse, { x:W-M-0.52, y:0.5, w:0.52, h:0.52, fill:{color:MIST}, line:{color:"FFFFFF",width:0} });
  s.addText(String(no), { x:W-M-0.52, y:0.5, w:0.52, h:0.52, isTextBox:true, margin:0,
    fontFace:F, fontSize:13, bold:true, color:SLATE, align:"center", valign:"middle" });
}

// ダミー値バッジ
function dummy(s, x){
  const bx = (x===undefined) ? W-M-2.05 : x;
  s.addShape(pres.ShapeType.roundRect, { x:bx, y:H-0.58, w:1.55, h:0.3, rectRadius:0.14,
    fill:{color:"FDF3E3"}, line:{color:AMBER, width:0.75} });
  s.addText("ダミー値", { x:bx, y:H-0.58, w:1.55, h:0.3, isTextBox:true, margin:0,
    fontFace:F, fontSize:10, bold:true, color:AMBER, align:"center", valign:"middle" });
}

function note(s, t){
  s.addText(t, { x:M, y:H-0.56, w:W-2*M-2.2, h:0.3, isTextBox:true, margin:0,
    fontFace:F, fontSize:10, color:MUTED, valign:"middle" });
}

function card(s, x, y, w, h, fill){
  s.addShape(pres.ShapeType.roundRect, { x, y, w, h, rectRadius:0.06,
    fill:{color: fill||MIST}, line:{color:"FFFFFF", width:0}, shadow:sh() });
}

function badgeNum(s, x, y, d, label, color){
  s.addShape(pres.ShapeType.ellipse, { x, y, w:d, h:d, fill:{color:color||TEAL}, line:{color:"FFFFFF",width:0} });
  s.addText(label, { x, y, w:d, h:d, isTextBox:true, margin:0,
    fontFace:F, fontSize:14, bold:true, color:"FFFFFF", align:"center", valign:"middle" });
}

const chartBase = {
  chartColors:[TEAL, BERRY, SLATE, "9AA5B5"],
  catAxisLabelColor: SLATE, valAxisLabelColor: SLATE,
  catAxisLabelFontFace:F, valAxisLabelFontFace:F,
  catAxisLabelFontSize:10, valAxisLabelFontSize:10,
  valGridLine:{ color:"E3E7EE", size:1 }, catGridLine:{ style:"none" },
  dataLabelFontFace:F, dataLabelFontSize:9,
  titleFontFace:F, titleFontSize:12, titleColor:INK,
};

/* =====================  1. タイトル  ===================== */
{
  const s = pres.addSlide();
  s.background = { color: INK };
  // cat-eye motif
  s.addShape(pres.ShapeType.ellipse, { x:9.3, y:1.25, w:4.6, h:4.6, fill:{color:BERRY, transparency:72}, line:{color:"FFFFFF",width:0} });
  s.addShape(pres.ShapeType.ellipse, { x:10.0, y:1.95, w:3.2, h:3.2, fill:{color:TEAL, transparency:60}, line:{color:"FFFFFF",width:0} });
  s.addShape(pres.ShapeType.ellipse, { x:10.55, y:2.2,  w:0.55, h:2.7, fill:{color:"FFFFFF", transparency:35}, line:{color:"FFFFFF",width:0}, rotate:20 });

  s.addText("MRI SAFETY", { x:M, y:1.45, w:8.2, h:0.3, isTextBox:true, margin:0,
    fontFace:F, fontSize:12, bold:true, color:TEAL, charSpacing:3 });
  s.addText("マグネットネイル装着者のMRI検査は\n一律に延期すべきか", {
    x:M, y:1.95, w:8.4, h:1.9, isTextBox:true, margin:0,
    fontFace:F, fontSize:34, bold:true, color:"FFFFFF", lineSpacing:46 });
  s.addText("1.5T / 3T における磁気吸引力と画像アーチファクトの定量評価", {
    x:M, y:3.95, w:8.4, h:0.4, isTextBox:true, margin:0,
    fontFace:F, fontSize:15, color:"C9D2E0" });
  s.addText([
    { text:"所属・氏名を記入", options:{ breakLine:true } },
    { text:"◯◯学会／研究発表会　20XX年X月X日" }
  ], { x:M, y:4.75, w:8.4, h:0.8, isTextBox:true, margin:0, fontFace:F, fontSize:12, color:"8E9AAE", lineSpacing:20 });

  s.addShape(pres.ShapeType.roundRect, { x:M, y:6.35, w:5.6, h:0.42, rectRadius:0.2,
    fill:{color:"3A2A12"}, line:{color:AMBER, width:1} });
  s.addText("本スライドの数値・グラフ・画像はすべてダミーです", { x:M, y:6.35, w:5.6, h:0.42, isTextBox:true, margin:0,
    fontFace:F, fontSize:11, bold:true, color:"F0B860", align:"center", valign:"middle" });
  s.addNotes("実データが出るまでの構成検証用。数値はすべて仮。発表時は必ず差し替える。");
}

/* =====================  2. 導入：延期の実態  ===================== */
{
  const s = pres.addSlide();
  head(s, 2, "延期は「中止」ではない。しかし無害でもない", "現状");
  const stats = [
    { v:"68", u:"件／年", l:"ネイルを理由とした延期", c:SLATE },
    { v:"24", u:"日", l:"依頼から実施までの日数（中央値）", c:BERRY },
    { v:"5",  u:"件", l:"再予約に至らず未受検のまま脱落", c:BERRY },
    { v:"41", u:"%",  l:"延期症例のうち頭部MRIが占める割合", c:TEAL },
  ];
  stats.forEach((st,i)=>{
    const x = M + i*3.07, w = 2.85;
    card(s, x, 1.75, w, 2.5);
    s.addText([{ text:st.v, options:{ fontSize:52, bold:true, color:st.c } },
               { text:" "+st.u, options:{ fontSize:15, bold:true, color:st.c } }],
      { x:x+0.25, y:1.95, w:w-0.5, h:1.2, isTextBox:true, margin:0, fontFace:F, align:"left", valign:"middle" });
    s.addText(st.l, { x:x+0.25, y:3.15, w:w-0.5, h:0.95, isTextBox:true, margin:0,
      fontFace:F, fontSize:12, color:TEXT, valign:"top", lineSpacing:18 });
  });
  card(s, M, 4.55, W-2*M, 1.45, "FBF1F5");
  s.addText("損失の中身は「検査が実施されない」ことではなく、診断が遅れること・患者が二度来ること", {
    x:M+0.35, y:4.75, w:W-2*M-0.7, h:0.4, isTextBox:true, margin:0, fontFace:F, fontSize:16, bold:true, color:BERRY });
  s.addText("さらに、延期後に再予約されず未受検のまま終わった例が存在する。安全のための運用が「未受検」という別のリスクを生んでいる可能性がある。", {
    x:M+0.35, y:5.2, w:W-2*M-0.7, h:0.65, isTextBox:true, margin:0, fontFace:F, fontSize:12.5, color:TEXT, lineSpacing:19 });
  note(s, "出典：自施設 20XX年度 予約・実施記録の後ろ向き集計");
  dummy(s);
  s.addNotes("ここは自施設の実データに差し替える。件数より『依頼から実施までの日数』が効く。脱落例の有無は必ず確認すること。部位別内訳は13枚目の距離依存性と結論で噛み合わせる。");
}

/* =====================  3. 導入：施設間のばらつき  ===================== */
{
  const s = pres.addSlide();
  head(s, 3, "同じ物理現象に、施設ごとに違う答えが出ている", "現状");
  const cases = [
    { t:"A 病院", b:"マグネットネイル装着者は\n原則としてMRI検査を実施せず、\n除去後に再予約", c:BERRY },
    { t:"B 病院", b:"追加の安全対策を行ったうえで\n検査を実施", c:TEAL },
    { t:"C 病院", b:"部位を問わず、ジェルネイルは\n全例除去を依頼", c:SLATE },
  ];
  cases.forEach((cs,i)=>{
    const x = M + i*4.12, w = 3.8;
    card(s, x, 1.8, w, 2.55);
    s.addShape(pres.ShapeType.ellipse, { x:x+0.3, y:2.1, w:0.46, h:0.46, fill:{color:cs.c}, line:{color:"FFFFFF",width:0} });
    s.addText(cs.t, { x:x+0.9, y:2.1, w:w-1.2, h:0.46, isTextBox:true, margin:0,
      fontFace:F, fontSize:16, bold:true, color:INK, valign:"middle" });
    s.addText(cs.b, { x:x+0.3, y:2.75, w:w-0.6, h:1.4, isTextBox:true, margin:0,
      fontFace:F, fontSize:12.5, color:TEXT, lineSpacing:20, valign:"top" });
  });
  card(s, M, 4.7, W-2*M, 1.3, INK2);
  s.addText("対応が一致しないのは、判断の根拠となる定量データが存在しないから", {
    x:M+0.4, y:4.9, w:W-2*M-0.8, h:0.4, isTextBox:true, margin:0,
    fontFace:F, fontSize:16, bold:true, color:"FFFFFF" });
  s.addText("各施設は「危ないかもしれない」という推定のもとで、それぞれ安全側に倒した運用を組んでいる。", {
    x:M+0.4, y:5.35, w:W-2*M-0.8, h:0.4, isTextBox:true, margin:0,
    fontFace:F, fontSize:12.5, color:"C9D2E0" });
  note(s, "各院が公開している注意喚起文書より（発表時は出典を明記）");
  s.addNotes("実在する公開文書を引用する。施設名は必要に応じて伏せる。");
}

/* =====================  4. 背景：仕組み  ===================== */
{
  const s = pres.addSlide();
  head(s, 4, "磁性粉が「揃ったまま」固まるのがマグネットネイル", "背景");
  s.addText([
    { text:"ジェル液中に微細な磁性フレーク（酸化鉄系・鉄ニッケル合金）が分散している。", options:{ breakLine:true } },
    { text:"磁石を近づけると粉が磁力線に沿って整列し、光の反射が変わって猫目状の帯ができる。", options:{ breakLine:true } },
    { text:"UVライトで硬化させると、その配列が固定されたまま残る。" },
  ], { x:M, y:1.85, w:5.5, h:1.7, isTextBox:true, margin:0, fontFace:F, fontSize:13.5, color:TEXT, lineSpacing:24 });

  card(s, M, 3.75, 5.5, 2.15, "FBF1F5");
  s.addText("磁性粉が「揃ったまま」固まっている", {
    x:M+0.35, y:3.95, w:5.0, h:0.4, isTextBox:true, margin:0, fontFace:F, fontSize:15, bold:true, color:BERRY });
  s.addText("先行研究が扱ってきた「磁性粉を含む化粧品」とは、この点で条件が異なる。本研究の新規性の根拠。", {
    x:M+0.35, y:4.42, w:5.0, h:1.25, isTextBox:true, margin:0, fontFace:F, fontSize:12, color:TEXT, lineSpacing:19 });

  // 模式図：未配列 → 配列
  const panels = [ { x:6.7, lab:"硬化のみ（未配列）", seed:1 }, { x:10.25, lab:"磁石で配列後に硬化", seed:2 } ];
  panels.forEach((p, pi)=>{
    s.addShape(pres.ShapeType.roundRect, { x:p.x, y:1.85, w:2.9, h:2.6, rectRadius:0.06, fill:{color:"E9EDF3"}, line:{color:"D4DAE4", width:1} });
    // 爪（下地）
    s.addShape(pres.ShapeType.roundRect, { x:p.x+0.25, y:3.55, w:2.4, h:0.55, rectRadius:0.08, fill:{color:"D9C3B0"}, line:{color:"FFFFFF",width:0} });
    s.addText("爪", { x:p.x+0.25, y:3.55, w:2.4, h:0.55, isTextBox:true, margin:0, fontFace:F, fontSize:10, color:"7A6253", align:"center", valign:"middle" });
    // フレーク
    for (let i=0;i<22;i++){
      const col = i % 6, row = Math.floor(i/6);
      const fx = p.x + 0.35 + col*0.39 + ((row%2)*0.13);
      const fy = 2.15 + row*0.34;
      const rot = pi===0 ? ((i*53)%180) - 90 : 0;
      s.addShape(pres.ShapeType.rect, { x:fx, y:fy, w:0.26, h:0.075,
        fill:{color: pi===0 ? "7C8699" : SLATE}, line:{color:"FFFFFF", width:0}, rotate:rot });
    }
    if (pi===1){
      s.addShape(pres.ShapeType.rect, { x:p.x+0.42, y:2.02, w:2.1, h:0.09, fill:{color:BERRY, transparency:30}, line:{color:"FFFFFF",width:0} });
    }
    s.addText(p.lab, { x:p.x, y:4.5, w:2.9, h:0.3, isTextBox:true, margin:0,
      fontFace:F, fontSize:11.5, bold:true, color:INK, align:"center" });
  });
  s.addShape(pres.ShapeType.rect, { x:9.72, y:3.05, w:0.42, h:0.06, fill:{color:BERRY}, line:{color:BERRY, width:1.5, endArrowType:"triangle"} });
  s.addText("磁石", { x:9.35, y:2.6, w:1.2, h:0.3, isTextBox:true, margin:0, fontFace:F, fontSize:10, bold:true, color:BERRY, align:"center" });
  s.addText("模式図", { x:6.7, y:4.95, w:6.45, h:0.3, isTextBox:true, margin:0, fontFace:F, fontSize:10, color:MUTED, align:"center" });
  s.addNotes("『粉が揃って固まる』という一点を印象づける。これが案D（配向異方性）の伏線になる。");
}

/* =====================  5. 干渉の4経路  ===================== */
{
  const s = pres.addSlide();
  head(s, 5, "MRIと干渉しうる4つの経路", "背景");
  const rows = [
    { n:"1", t:"吸引力・トルク", m:"空間磁場勾配が磁性体を引く／回そうとする", tag:"主軸", c:TEAL },
    { n:"2", t:"画像アーチファクト", m:"磁化率差による局所磁場不均一で信号が失われる", tag:"主軸", c:TEAL },
    { n:"3", t:"RF発熱", m:"導電性フレークに渦電流が誘導され発熱する", tag:"補助", c:MUTED },
    { n:"4", t:"モニタ干渉", m:"パルスオキシメータの光をネイルが遮る", tag:"副次", c:MUTED },
  ];
  rows.forEach((r,i)=>{
    const x = M + (i%2)*6.15, y = 1.8 + Math.floor(i/2)*2.05;
    card(s, x, y, 5.85, 1.75);
    badgeNum(s, x+0.35, y+0.32, 0.5, r.n, r.c);
    s.addText(r.t, { x:x+1.0, y:y+0.28, w:3.4, h:0.4, isTextBox:true, margin:0,
      fontFace:F, fontSize:16, bold:true, color:INK, valign:"middle" });
    s.addShape(pres.ShapeType.roundRect, { x:x+4.55, y:y+0.32, w:0.95, h:0.34, rectRadius:0.16,
      fill:{color: r.tag==="主軸" ? TEAL : "DDE2EA"}, line:{color:"FFFFFF", width:0} });
    s.addText(r.tag, { x:x+4.55, y:y+0.32, w:0.95, h:0.34, isTextBox:true, margin:0,
      fontFace:F, fontSize:10.5, bold:true, color: r.tag==="主軸" ? "FFFFFF" : SLATE, align:"center", valign:"middle" });
    s.addText(r.m, { x:x+1.0, y:y+0.82, w:4.5, h:0.7, isTextBox:true, margin:0,
      fontFace:F, fontSize:12, color:TEXT, lineSpacing:18, valign:"top" });
  });
  note(s, "発熱は光ファイバー温度計が使えないため、示温ラベルによる最高到達温度の記録で代替する（限界は16枚目）");
  s.addNotes("4経路を先に見せておくと、以降の結果がどこに対応するか聴衆が迷わない。");
}

/* =====================  6. 先行研究と空白  ===================== */
{
  const s = pres.addSlide();
  head(s, 6, "研究されてきたこと、されていないこと", "先行研究");
  card(s, M, 1.8, 5.85, 4.1);
  s.addText("わかっていること", { x:M+0.4, y:2.05, w:5.0, h:0.4, isTextBox:true, margin:0,
    fontFace:F, fontSize:16, bold:true, color:SLATE });
  s.addText([
    { text:"化粧品38種（うちネイル16種）の3Tでのアーチファクト評価", options:{ bullet:true, breakLine:true } },
    { text:"アイメイクでは黒色酸化鉄のみが吸引力を示し、除去が推奨される", options:{ bullet:true, breakLine:true } },
    { text:"タトゥー色素中の磁性物質と、MRI中の熱傷症例", options:{ bullet:true, breakLine:true } },
    { text:"微量鉄粉（0.01〜1.7 mg）が作るアーチファクトの定量", options:{ bullet:true } },
  ], { x:M+0.4, y:2.6, w:5.05, h:2.9, isTextBox:true, margin:0,
    fontFace:F, fontSize:12.5, color:TEXT, paraSpaceAfter:10, lineSpacing:19 });

  card(s, M+6.15, 1.8, 5.85, 4.1, "FBF1F5");
  s.addText("まだ埋まっていない空白", { x:M+6.55, y:2.05, w:5.0, h:0.4, isTextBox:true, margin:0,
    fontFace:F, fontSize:16, bold:true, color:BERRY });
  s.addText([
    { text:"マグネットネイル製品そのものの系統的な評価", options:{ bullet:true, breakLine:true } },
    { text:"磁石で「整列させた状態」が影響を変えるか", options:{ bullet:true, breakLine:true } },
    { text:"1.5T と 3T の直接比較", options:{ bullet:true, breakLine:true } },
    { text:"撮影部位からの距離による減衰 ＝ 部位別に分けられるか", options:{ bullet:true } },
  ], { x:M+6.55, y:2.6, w:5.05, h:2.9, isTextBox:true, margin:0,
    fontFace:F, fontSize:12.5, color:TEXT, paraSpaceAfter:10, lineSpacing:19 });
  note(s, "参考：PMID 23290125 / 39631939 / 7833178 / 29250836 ほか");
  s.addNotes("右側の4項目が、そのまま本研究の4つの結果スライドに対応する。");
}

/* =====================  7. 目的・仮説  ===================== */
{
  const s = pres.addSlide();
  head(s, 7, "3つの階層で問いを立てる", "目的");
  const qs = [
    { q:"Q1", t:"物理", ttl:"どの経路で、どれだけ干渉するのか",
      h:"仮説：吸引力は規格の許容範囲に収まるが、画像アーチファクトは明確に生じる", c:TEAL },
    { q:"Q2", t:"条件", ttl:"磁場強度・シーケンス・距離でどう変わるのか",
      h:"仮説：アーチファクトは B₀ と TE に比例し、距離とともに急速に減衰する", c:SLATE },
    { q:"Q3", t:"運用", ttl:"では、どういうルールが妥当なのか",
      h:"仮説：全例延期は過剰であり、部位別の運用に置き換えられる", c:BERRY },
  ];
  qs.forEach((o,i)=>{
    const y = 1.8 + i*1.45;
    card(s, M, y, W-2*M, 1.25);
    badgeNum(s, M+0.3, y+0.35, 0.55, o.q, o.c);
    s.addText(o.t, { x:M+1.0, y:y+0.2, w:1.0, h:0.3, isTextBox:true, margin:0,
      fontFace:F, fontSize:11, bold:true, color:o.c });
    s.addText(o.ttl, { x:M+1.0, y:y+0.48, w:5.6, h:0.4, isTextBox:true, margin:0,
      fontFace:F, fontSize:15.5, bold:true, color:INK, valign:"top" });
    s.addText(o.h, { x:M+7.0, y:y+0.32, w:4.55, h:0.75, isTextBox:true, margin:0,
      fontFace:F, fontSize:11.5, color:TEXT, lineSpacing:17, valign:"middle" });
  });
  s.addText("Q3 まで到達できることが、この研究の価値", { x:M, y:6.25, w:W-2*M, h:0.35, isTextBox:true, margin:0,
    fontFace:F, fontSize:14, bold:true, color:BERRY });
  s.addNotes("『提案しました』で終わらせず、自施設で運用を変えるところまで持っていく設計であることを強調する。");
}

/* =====================  8. 方法① 偏向角法  ===================== */
{
  const s = pres.addSlide();
  head(s, 8, "方法①　磁気吸引力 ─ 偏向角法（ASTM F2052 準拠）", "方法");
  // 原理図
  card(s, M, 1.8, 5.5, 4.1, "EEF1F6");
  s.addShape(pres.ShapeType.roundRect, { x:M+0.45, y:2.1, w:4.6, h:1.05, rectRadius:0.18, fill:{color:"FFFFFF"}, line:{color:"BCC6D4", width:1.5} });
  s.addText("ガントリー入口（∂B/∂z 最大位置）", { x:M+0.45, y:2.1, w:4.6, h:1.05, isTextBox:true, margin:0,
    fontFace:F, fontSize:11, color:SLATE, align:"center", valign:"middle" });
  // 吊り下げ
  s.addShape(pres.ShapeType.rect, { x:M+2.72, y:3.15, w:0.03, h:1.55, fill:{color:"AAB3C0"}, line:{color:"FFFFFF",width:0} });
  s.addShape(pres.ShapeType.rect, { x:M+2.72, y:3.15, w:0.03, h:1.55, fill:{color:BERRY}, line:{color:"FFFFFF",width:0}, rotate:24 });
  s.addShape(pres.ShapeType.ellipse, { x:M+3.28, y:4.52, w:0.3, h:0.3, fill:{color:BERRY}, line:{color:"FFFFFF",width:0} });
  s.addText("θ", { x:M+2.85, y:3.5, w:0.4, h:0.3, isTextBox:true, margin:0, fontFace:F, fontSize:14, bold:true, color:BERRY });
  s.addText("試料（ネイルチップ）", { x:M+2.6, y:4.9, w:2.3, h:0.3, isTextBox:true, margin:0, fontFace:F, fontSize:10.5, color:SLATE });
  s.addText("非磁性の糸で吊り下げ", { x:M+0.45, y:5.35, w:4.6, h:0.3, isTextBox:true, margin:0, fontFace:F, fontSize:10.5, color:MUTED, align:"center" });

  s.addText("F = m · g · tan θ", { x:M+6.15, y:1.9, w:5.85, h:0.55, isTextBox:true, margin:0,
    fontFace:F, fontSize:26, bold:true, color:INK });
  s.addText("m：試料質量　g：重力加速度　θ：静磁場による振れ角", { x:M+6.15, y:2.5, w:5.85, h:0.3, isTextBox:true, margin:0,
    fontFace:F, fontSize:11, color:MUTED });
  card(s, M+6.15, 2.95, 5.85, 1.3, "E6F3F5");
  s.addText("判定基準：θ < 45°", { x:M+6.5, y:3.15, w:5.15, h:0.35, isTextBox:true, margin:0,
    fontFace:F, fontSize:16, bold:true, color:TEAL });
  s.addText("磁気力が重力以下であることを意味し、規格上は一般に許容可能とされる。", {
    x:M+6.5, y:3.55, w:5.15, h:0.6, isTextBox:true, margin:0, fontFace:F, fontSize:12, color:TEXT, lineSpacing:18 });
  s.addText([
    { text:"測定条件", options:{ bold:true, color:INK, breakLine:true } },
    { text:"1.5T / 3T の2装置、各試料 n = 10", options:{ bullet:true, breakLine:true } },
    { text:"試料：透明ジェル／カラージェル／ラメ入り／マグネットネイル（未配列・配列済）／製品10種以上", options:{ bullet:true, breakLine:true } },
    { text:"トルク（ASTM F2213）は低摩擦台上での回転を定性評価", options:{ bullet:true } },
  ], { x:M+6.15, y:4.5, w:5.85, h:1.6, isTextBox:true, margin:0,
    fontFace:F, fontSize:11.5, color:TEXT, paraSpaceAfter:7, lineSpacing:17 });
  note(s, "測定位置はガウスラインマップではなく空間磁場勾配マップから決定（力は B·∂B/∂z に依存するため）");
  s.addNotes("45°という規格由来の基準があるおかげで、白黒のつく問いになっている点を強調する。");
}

/* =====================  9. 方法② ファントム撮影  ===================== */
{
  const s = pres.addSlide();
  head(s, 9, "方法②　画像アーチファクト（ASTM F2119 準拠）", "方法");
  card(s, M, 1.8, 4.9, 4.1, "EEF1F6");
  s.addShape(pres.ShapeType.roundRect, { x:M+0.55, y:2.35, w:3.8, h:2.0, rectRadius:0.12, fill:{color:"CFE4EA"}, line:{color:"9FC4CE", width:1.5} });
  s.addText("ファントム", { x:M+0.55, y:3.75, w:3.8, h:0.35, isTextBox:true, margin:0,
    fontFace:F, fontSize:11, color:"3E6F7B", align:"center" });
  for (let i=0;i<4;i++){
    s.addShape(pres.ShapeType.roundRect, { x:M+0.85+i*0.87, y:2.6, w:0.6, h:0.75, rectRadius:0.12, fill:{color:BERRY, transparency:15}, line:{color:"FFFFFF", width:1} });
  }
  s.addText("ネイルチップを規則配置して固定", { x:M+0.55, y:4.45, w:3.8, h:0.3, isTextBox:true, margin:0,
    fontFace:F, fontSize:11, color:SLATE, align:"center" });
  s.addText("アーチファクトの定義：参照画像との画素値の差が 30% を超える領域（ASTM F2119）。ImageJ で閾値処理して面積・最大径を自動計測。", {
    x:M+0.35, y:4.9, w:4.2, h:0.85, isTextBox:true, margin:0, fontFace:F, fontSize:11, color:TEXT, lineSpacing:17 });

  const factors = [
    ["磁場強度", "1.5T / 3T"],
    ["シーケンス", "SE / TSE / GRE / EPI / 脂肪抑制"],
    ["TE", "GRE で 5 段階"],
    ["受信バンド幅", "3 段階"],
    ["周波数エンコード方向", "2 方向"],
    ["試料からの距離", "0 / 2 / 5 / 10 / 20 cm"],
    ["配置角度", "0° / 45° / 90°"],
  ];
  s.addText("撮影マトリクス", { x:M+5.25, y:1.85, w:6.0, h:0.35, isTextBox:true, margin:0,
    fontFace:F, fontSize:15, bold:true, color:INK });
  s.addTable(
    [[{ text:"因子", options:{ bold:true, color:"FFFFFF", fill:{color:SLATE} } },
      { text:"水準", options:{ bold:true, color:"FFFFFF", fill:{color:SLATE} } }]]
      .concat(factors.map((r,i)=>[
        { text:r[0], options:{ fill:{color: i%2? "FFFFFF":MIST} } },
        { text:r[1], options:{ fill:{color: i%2? "FFFFFF":MIST} } }])),
    { x:M+5.25, y:2.3, w:6.05, colW:[2.05, 4.0], rowH:0.42,
      fontFace:F, fontSize:11.5, color:TEXT, valign:"middle",
      border:{ type:"solid", color:"DCE1E9", pt:0.75 } });
  s.addText("撮影枠の制約がないため、点の比較ではなく曲線として提示できる", {
    x:M+5.25, y:5.5, w:6.05, h:0.35, isTextBox:true, margin:0,
    fontFace:F, fontSize:12.5, bold:true, color:TEAL });
  s.addNotes("時間外に枠を自由に使えることが、この網羅的マトリクスを可能にしている。");
}

/* =====================  10. 結果① 偏向角  ===================== */
{
  const s = pres.addSlide();
  head(s, 10, "結果①　偏向角はすべての試料で 45° を下回った", "結果");
  const cats = ["透明ジェル","カラージェル","ラメ入り","MN 未配列","MN 配列済","MN 製品B","MN 製品C"];
  s.addChart([
    { type: pres.ChartType.bar,
      data: [ { name:"1.5T", labels:cats, values:[0.5,1.2,3.5,11.0,11.8,8.2,16.4] },
              { name:"3T",   labels:cats, values:[0.8,2.0,5.8,18.3,19.1,13.6,26.2] } ],
      options: { chartColors:[TEAL, BERRY], showValue:true, dataLabelPosition:"outEnd", dataLabelColor:SLATE } },
    { type: pres.ChartType.line,
      data: [ { name:"ASTM F2052 基準 45°", labels:cats, values:[45,45,45,45,45,45,45] } ],
      options: { chartColors:["C2700F"], lineSize:2, lineDash:"dash", showValue:false } },
  ], Object.assign({}, chartBase, {
    x:M, y:1.75, w:8.3, h:4.0,
    barGrouping:"clustered", barGapWidthPct:60,
    valAxisMaxVal:50, valAxisMinVal:0, valAxisTitle:"偏向角（度）",
    showValAxisTitle:true, valAxisTitleFontFace:F, valAxisTitleFontSize:11, valAxisTitleColor:SLATE,
    showLegend:true, legendPos:"b", legendFontFace:F, legendFontSize:11, legendColor:SLATE,
  }));

  card(s, 9.4, 1.75, 3.23, 4.0, "E6F3F5");
  s.addText("読み取り", { x:9.7, y:2.0, w:2.6, h:0.3, isTextBox:true, margin:0,
    fontFace:F, fontSize:13, bold:true, color:TEAL });
  s.addText([
    { text:"最大でも 26.2°（3T・製品C）で、規格の 45° を超えた試料はない。", options:{ breakLine:true } },
    { text:"3T は 1.5T の約 1.6 倍。磁場強度依存性が明確。", options:{ breakLine:true } },
    { text:"配列の有無による差は小さい。", options:{ breakLine:true } },
    { text:"→ 吸引力の観点では、爪からの剥離リスクは低いと判断できる。" },
  ], { x:9.7, y:2.45, w:2.63, h:3.1, isTextBox:true, margin:0,
    fontFace:F, fontSize:11.5, color:TEXT, paraSpaceAfter:9, lineSpacing:18 });
  note(s, "平均値、n = 10、エラーバーは実データで付す");
  dummy(s);
  s.addNotes("実データで45°を超える試料が出た場合は、この結論を反転させる。どちらでも発表は成立する。");
}

/* =====================  11. 結果② 画像比較  ===================== */
{
  const s = pres.addSlide();
  head(s, 11, "結果②　磁場強度とシーケンスで消失域は変わる", "結果");
  const panels = [
    { lab:"1.5T  SE",  void:0.30 }, { lab:"1.5T  GRE", void:0.62 },
    { lab:"3T  SE",    void:0.48 }, { lab:"3T  GRE",   void:1.05 },
  ];
  panels.forEach((p,i)=>{
    const x = M + i*3.07, w = 2.85;
    s.addShape(pres.ShapeType.rect, { x, y:1.85, w, h:2.95, fill:{color:"0A0D14"}, line:{color:"FFFFFF", width:0} });
    s.addShape(pres.ShapeType.ellipse, { x:x+0.35, y:2.15, w:w-0.7, h:2.35, fill:{color:"C6CDD8"}, line:{color:"FFFFFF", width:0} });
    s.addShape(pres.ShapeType.ellipse, { x:x+w/2-p.void/2, y:2.35, w:p.void, h:p.void*1.15, fill:{color:"0A0D14"}, line:{color:"FFFFFF", width:0} });
    s.addText(p.lab, { x, y:4.85, w, h:0.32, isTextBox:true, margin:0,
      fontFace:F, fontSize:13, bold:true, color:INK, align:"center" });
  });
  card(s, M, 5.35, W-2*M, 0.92, "FBF1F5");
  s.addText("GRE では SE の約 2 倍、3T では 1.5T の約 1.6 倍に信号消失域が拡大した（模式図・実画像に差し替え予定）", {
    x:M+0.35, y:5.35, w:W-2*M-0.7, h:0.92, isTextBox:true, margin:0,
    fontFace:F, fontSize:13.5, bold:true, color:BERRY, valign:"middle" });
  dummy(s);
  s.addNotes("ここが最大の見せ場。実画像に必ず差し替える。『確かに影響はある』と納得させてから、次の距離依存性で反転させる。");
}

/* =====================  12. 結果③ TE依存  ===================== */
{
  const s = pres.addSlide();
  head(s, 12, "結果③　アーチファクトは TE に比例して拡大する", "結果");
  const te = ["5","10","15","20","30"];
  s.addChart(pres.ChartType.line, [
    { name:"3T  GRE",   labels:te, values:[42, 78, 121, 158, 232] },
    { name:"1.5T  GRE", labels:te, values:[26, 48,  74,  98, 142] },
    { name:"3T  SE",    labels:te, values:[18, 24,  29,  33,  41] },
  ], Object.assign({}, chartBase, {
    x:M, y:1.75, w:8.3, h:4.05,
    lineSize:3, lineDataSymbolSize:7,
    valAxisTitle:"信号消失面積（mm²）", showValAxisTitle:true,
    valAxisTitleFontFace:F, valAxisTitleFontSize:11, valAxisTitleColor:SLATE,
    catAxisTitle:"TE（ms）", showCatAxisTitle:true,
    catAxisTitleFontFace:F, catAxisTitleFontSize:11, catAxisTitleColor:SLATE,
    showLegend:true, legendPos:"b", legendFontFace:F, legendFontSize:11, legendColor:SLATE,
  }));
  card(s, 9.4, 1.75, 3.23, 4.05, "E6F3F5");
  s.addText("読み取り", { x:9.7, y:2.0, w:2.6, h:0.3, isTextBox:true, margin:0,
    fontFace:F, fontSize:13, bold:true, color:TEAL });
  s.addText([
    { text:"GRE では TE にほぼ比例して直線的に増大する。", options:{ breakLine:true } },
    { text:"SE 系は TE を延ばしてもほとんど増えない。", options:{ breakLine:true } },
    { text:"→ 短 TE・SE 系・広バンド幅の選択で、実務的に低減できる余地がある。" },
  ], { x:9.7, y:2.45, w:2.63, h:3.1, isTextBox:true, margin:0,
    fontFace:F, fontSize:11.5, color:TEXT, paraSpaceAfter:10, lineSpacing:18 });
  dummy(s);
  s.addNotes("金属アーチファクト低減シーケンス（VAT / SEMAC 等）が自施設にあれば、ここに4本目の系列として加える。");
}

/* =====================  13. 結果④ 距離依存性（核心）  ===================== */
{
  const s = pres.addSlide();
  head(s, 13, "結果④　5 cm を超えると、影響は検出限界以下になる", "結果 ─ 核心");
  const d = ["0","2","5","10","20"];
  s.addChart(pres.ChartType.line, [
    { name:"3T  GRE",   labels:d, values:[232, 61, 8, 1, 0] },
    { name:"1.5T  GRE", labels:d, values:[142, 34, 4, 0, 0] },
  ], Object.assign({}, chartBase, {
    x:M, y:1.75, w:7.6, h:4.05,
    lineSize:3, lineDataSymbolSize:7, chartColors:[BERRY, TEAL],
    showValue:true, dataLabelPosition:"t", dataLabelColor:SLATE,
    valAxisTitle:"信号消失面積（mm²）", showValAxisTitle:true,
    valAxisTitleFontFace:F, valAxisTitleFontSize:11, valAxisTitleColor:SLATE,
    catAxisTitle:"撮影部位からの距離（cm）", showCatAxisTitle:true,
    catAxisTitleFontFace:F, catAxisTitleFontSize:11, catAxisTitleColor:SLATE,
    showLegend:true, legendPos:"b", legendFontFace:F, legendFontSize:11, legendColor:SLATE,
  }));
  card(s, 8.7, 1.75, 3.93, 4.05, INK2);
  s.addText("この研究が現場に返せる答え", { x:9.0, y:2.0, w:3.35, h:0.3, isTextBox:true, margin:0,
    fontFace:F, fontSize:13, bold:true, color:TEAL });
  s.addText([
    { text:"手指・手関節MRI", options:{ fontSize:14, bold:true, color:"FFFFFF", breakLine:true } },
    { text:"撮影範囲に含まれるため、除去が必要。", options:{ fontSize:11.5, color:"C9D2E0", breakLine:true } },
  ], { x:9.0, y:2.5, w:3.35, h:0.9, isTextBox:true, margin:0, fontFace:F, lineSpacing:19 });
  s.addText([
    { text:"頭部・体幹部MRI", options:{ fontSize:14, bold:true, color:"FFFFFF", breakLine:true } },
    { text:"手は撮影範囲から十分離れており、画像への影響は検出されなかった。", options:{ fontSize:11.5, color:"C9D2E0", breakLine:true } },
  ], { x:9.0, y:3.5, w:3.35, h:1.2, isTextBox:true, margin:0, fontFace:F, lineSpacing:19 });
  s.addText("＝ 全例延期は、画像の観点からは過剰である", { x:9.0, y:4.85, w:3.35, h:0.75, isTextBox:true, margin:0,
    fontFace:F, fontSize:13, bold:true, color:"F0B860", lineSpacing:20 });
  dummy(s);
  s.addNotes("11枚目で『影響はある』と見せた直後にこれを出す。この落差が発表の山。2枚目で出した部位別内訳がここで回収される。");
}

/* =====================  14. 結果⑤ 異方性・発熱  ===================== */
{
  const s = pres.addSlide();
  head(s, 14, "結果⑤　配向の効果と、発熱", "結果");
  card(s, M, 1.8, 5.85, 4.1);
  s.addText("配向異方性", { x:M+0.4, y:2.05, w:5.0, h:0.35, isTextBox:true, margin:0,
    fontFace:F, fontSize:16, bold:true, color:SLATE });
  const ang = [["0°","11.8°","158 mm²"],["45°","11.2°","149 mm²"],["90°","12.1°","163 mm²"]];
  s.addTable(
    [[{text:"配置角度",options:{bold:true,color:"FFFFFF",fill:{color:SLATE}}},
      {text:"偏向角",options:{bold:true,color:"FFFFFF",fill:{color:SLATE}}},
      {text:"消失面積",options:{bold:true,color:"FFFFFF",fill:{color:SLATE}}}]]
      .concat(ang.map((r,i)=>r.map(c=>({text:c, options:{fill:{color: i%2?"FFFFFF":MIST}}})))),
    { x:M+0.4, y:2.55, w:5.05, colW:[1.6,1.7,1.75], rowH:0.42,
      fontFace:F, fontSize:11.5, color:TEXT, valign:"middle", align:"center",
      border:{ type:"solid", color:"DCE1E9", pt:0.75 } });
  s.addText("いずれも有意差なし（p = 0.41）。整列の向きは、MRIへの影響を変えないと考えられる。", {
    x:M+0.4, y:4.5, w:5.05, h:0.9, isTextBox:true, margin:0, fontFace:F, fontSize:12, color:TEXT, lineSpacing:19 });

  card(s, M+6.15, 1.8, 5.85, 4.1);
  s.addText("発熱（示温ラベル法）", { x:M+6.55, y:2.05, w:5.0, h:0.35, isTextBox:true, margin:0,
    fontFace:F, fontSize:16, bold:true, color:SLATE });
  s.addText("40℃", { x:M+6.55, y:2.5, w:2.2, h:0.75, isTextBox:true, margin:0,
    fontFace:F, fontSize:42, bold:true, color:TEAL });
  s.addText("段階のラベルも変色せず\n（3T・高SAR 30分連続・n = 10）", { x:M+8.75, y:2.6, w:2.9, h:0.8, isTextBox:true, margin:0,
    fontFace:F, fontSize:11.5, color:TEXT, lineSpacing:18, valign:"middle" });
  card(s, M+6.55, 3.5, 5.05, 2.15, "FDF3E3");
  s.addText("この結果の限界", { x:M+6.85, y:3.68, w:4.45, h:0.3, isTextBox:true, margin:0,
    fontFace:F, fontSize:12.5, bold:true, color:AMBER });
  s.addText([
    { text:"温度の時間変化は取れていない（最高到達温度のみ）", options:{ bullet:true, breakLine:true } },
    { text:"ファントムは血流による冷却を再現していない＝安全側の評価", options:{ bullet:true, breakLine:true } },
    { text:"ASTM F2182 準拠測定は今後の課題", options:{ bullet:true } },
  ], { x:M+6.85, y:4.05, w:4.45, h:1.45, isTextBox:true, margin:0,
    fontFace:F, fontSize:11, color:TEXT, paraSpaceAfter:6, lineSpacing:16 });
  dummy(s);
  s.addNotes("発熱は主張を弱めに。限界を先に言うことで、かえって信頼される。");
}

/* =====================  15. 考察  ===================== */
{
  const s = pres.addSlide();
  head(s, 15, "4経路のうち、実際に効いていたのはどれか", "考察");
  const rows = [
    ["① 吸引力・トルク", "最大 26.2°（規格基準 45° 未満）", "低い", TEAL],
    ["② 画像アーチファクト", "距離 5 cm 以下でのみ顕著", "部位依存", BERRY],
    ["③ RF発熱", "40℃ 到達を検出せず", "検出されず", TEAL],
    ["④ モニタ干渉", "SpO₂ 測定値に影響（次頁）", "要注意", AMBER],
  ];
  s.addTable(
    [[{text:"経路",options:{bold:true,color:"FFFFFF",fill:{color:INK}}},
      {text:"本研究で得られた所見",options:{bold:true,color:"FFFFFF",fill:{color:INK}}},
      {text:"評価",options:{bold:true,color:"FFFFFF",fill:{color:INK}}}]]
      .concat(rows.map((r,i)=>[
        {text:r[0], options:{ bold:true, fill:{color: i%2?"FFFFFF":MIST} }},
        {text:r[1], options:{ fill:{color: i%2?"FFFFFF":MIST} }},
        {text:r[2], options:{ bold:true, color:r[3], align:"center", fill:{color: i%2?"FFFFFF":MIST} }}])),
    { x:M, y:1.85, w:W-2*M, colW:[3.3, 6.2, 2.43], rowH:0.62,
      fontFace:F, fontSize:13, color:TEXT, valign:"middle",
      border:{ type:"solid", color:"DCE1E9", pt:0.75 } });
  card(s, M, 5.0, W-2*M, 1.1, "FBF1F5");
  s.addText("リスクの実体は「剥離」でも「熱傷」でもなく、撮影範囲に入ったときの画像劣化だった", {
    x:M+0.35, y:5.0, w:W-2*M-0.7, h:1.1, isTextBox:true, margin:0,
    fontFace:F, fontSize:16, bold:true, color:BERRY, valign:"middle" });
  dummy(s);
  s.addNotes("『危ない／危なくない』の二択ではなく、どの経路がどれだけ効くかで整理したことが本研究の貢献。");
}

/* =====================  16. 限界  ===================== */
{
  const s = pres.addSlide();
  head(s, 16, "本研究の限界", "限界");
  const lims = [
    ["1","ファントムであり、生体ではない","血流による冷却、組織の磁化率、実際の指の位置は再現していない"],
    ["2","温度測定が最高到達温度のみ","光ファイバー温度計が使用できず、ASTM F2182 準拠測定に至っていない"],
    ["3","供試製品が限られる","市場に流通する全製品を網羅してはいない。磁性粉量の実測も行っていない"],
    ["4","装置は2台のみ","メーカー・機種による空間磁場勾配の違いは検討できていない"],
    ["5","運用評価は単施設・前後比較","対照群を置いた比較ではない"],
  ];
  lims.forEach((l,i)=>{
    const y = 1.75 + i*0.94;
    card(s, M, y, W-2*M, 0.82);
    badgeNum(s, M+0.25, y+0.16, 0.5, l[0], SLATE);
    s.addText(l[1], { x:M+0.95, y:y+0.14, w:4.3, h:0.55, isTextBox:true, margin:0,
      fontFace:F, fontSize:13.5, bold:true, color:INK, valign:"middle" });
    s.addText(l[2], { x:M+5.4, y:y+0.14, w:6.3, h:0.55, isTextBox:true, margin:0,
      fontFace:F, fontSize:11.5, color:TEXT, valign:"middle", lineSpacing:16 });
  });
  s.addNotes("限界を自分から具体的に挙げると、質疑が『指摘』から『相談』に変わる。");
}

/* =====================  17. 提案  ===================== */
{
  const s = pres.addSlide();
  head(s, 17, "提案　問診に頼らない判定と、部位別の運用", "提案");
  card(s, M, 1.8, 5.5, 4.1);
  s.addText("なぜ問診では判別できないのか", { x:M+0.35, y:2.0, w:4.8, h:0.35, isTextBox:true, margin:0,
    fontFace:F, fontSize:14.5, bold:true, color:INK });
  s.addText("患者の多くは、自分のネイルが磁性粉を含むタイプかどうかを知らない。「ジェルネイルですか」と聞いても答えられないため、現行運用は一律延期に倒さざるを得ない。", {
    x:M+0.35, y:2.45, w:4.8, h:1.0, isTextBox:true, margin:0, fontFace:F, fontSize:12, color:TEXT, lineSpacing:19 });
  s.addText("簡易磁石テスト", { x:M+0.35, y:3.55, w:4.8, h:0.35, isTextBox:true, margin:0,
    fontFace:F, fontSize:14.5, bold:true, color:TEAL });
  [["感度","96%"],["特異度","91%"]].forEach((p,i)=>{
    const x = M+0.35+i*2.45;
    s.addShape(pres.ShapeType.roundRect, { x, y:4.0, w:2.25, h:1.05, rectRadius:0.06, fill:{color:"E6F3F5"}, line:{color:"FFFFFF",width:0} });
    s.addText(p[1], { x, y:4.05, w:2.25, h:0.62, isTextBox:true, margin:0,
      fontFace:F, fontSize:26, bold:true, color:TEAL, align:"center", valign:"middle" });
    s.addText(p[0], { x, y:4.62, w:2.25, h:0.35, isTextBox:true, margin:0,
      fontFace:F, fontSize:11, color:SLATE, align:"center" });
  });
  s.addText("受付・更衣室で数秒。自己申告に依存しない。", { x:M+0.35, y:5.2, w:4.8, h:0.4, isTextBox:true, margin:0,
    fontFace:F, fontSize:11.5, color:MUTED });

  // フローチャート
  const fx = M+6.15;
  s.addText("部位別の判定フロー", { x:fx, y:1.85, w:5.85, h:0.35, isTextBox:true, margin:0,
    fontFace:F, fontSize:14.5, bold:true, color:INK });
  function fbox(x,y,w,h,t,fill,tc){
    s.addShape(pres.ShapeType.roundRect, { x, y, w, h, rectRadius:0.08, fill:{color:fill}, line:{color:"FFFFFF", width:0}, shadow:sh() });
    s.addText(t, { x:x+0.1, y, w:w-0.2, h, isTextBox:true, margin:0,
      fontFace:F, fontSize:11.5, bold:true, color:tc||"FFFFFF", align:"center", valign:"middle", lineSpacing:16 });
  }
  fbox(fx+1.6, 2.35, 2.65, 0.6, "磁石テスト陽性", SLATE);
  s.addShape(pres.ShapeType.rect, { x:fx+2.92, y:2.95, w:0.02, h:0.45, fill:{color:"AAB3C0"}, line:{color:"AAB3C0", width:1.25, endArrowType:"triangle"} });
  s.addText("撮影部位は？", { x:fx+1.6, y:3.42, w:2.65, h:0.3, isTextBox:true, margin:0,
    fontFace:F, fontSize:11, color:SLATE, align:"center" });
  fbox(fx+0.05, 3.9, 2.7, 1.0, "手・手関節\n\n除去してから実施", BERRY);
  fbox(fx+3.1, 3.9, 2.7, 1.0, "頭部・体幹部\n\n装着のまま実施可", TEAL);
  s.addText("※ 手の位置を撮影範囲から離す／SpO₂ は装着部位を変更", {
    x:fx, y:5.05, w:5.85, h:0.5, isTextBox:true, margin:0, fontFace:F, fontSize:10.5, color:MUTED, align:"center", lineSpacing:16 });
  dummy(s, fx+4.3);
  s.addNotes("問診の限界という論点を先に置くことで、磁石テストが『あれば便利』から『無いと解決しない』に変わる。");
}

/* =====================  18. 試験運用の結果  ===================== */
{
  const s = pres.addSlide();
  head(s, 18, "試験運用　部位別運用に変更した前後の比較", "運用");
  const pairs = [
    { l:"延期率", a:"8.4", b:"3.1", u:"%" },
    { l:"依頼から実施までの日数（中央値）", a:"24", b:"9", u:"日" },
    { l:"未受検のまま脱落した例", a:"5", b:"1", u:"件" },
  ];
  pairs.forEach((p,i)=>{
    const y = 1.8 + i*1.5;
    card(s, M, y, W-2*M, 1.3);
    s.addText(p.l, { x:M+0.4, y:y+0.1, w:4.7, h:1.1, isTextBox:true, margin:0,
      fontFace:F, fontSize:13.5, bold:true, color:INK, valign:"middle", lineSpacing:19 });
    s.addText([{ text:p.a, options:{ fontSize:32, bold:true, color:MUTED } },
               { text:" "+p.u, options:{ fontSize:13, color:MUTED } }],
      { x:M+5.3, y:y+0.25, w:2.0, h:0.8, isTextBox:true, margin:0, fontFace:F, align:"center", valign:"middle" });
    s.addShape(pres.ShapeType.rect, { x:M+7.5, y:y+0.63, w:0.75, h:0.04, fill:{color:BERRY}, line:{color:BERRY, width:1.75, endArrowType:"triangle"} });
    s.addText([{ text:p.b, options:{ fontSize:38, bold:true, color:BERRY } },
               { text:" "+p.u, options:{ fontSize:13, color:BERRY } }],
      { x:M+8.5, y:y+0.2, w:2.2, h:0.9, isTextBox:true, margin:0, fontFace:F, align:"center", valign:"middle" });
    s.addText(i===0?"変更前":"", { x:M+5.3, y:y-0.02, w:2.0, h:0.28, isTextBox:true, margin:0,
      fontFace:F, fontSize:10, color:MUTED, align:"center" });
    s.addText(i===0?"変更後":"", { x:M+8.5, y:y-0.02, w:2.2, h:0.28, isTextBox:true, margin:0,
      fontFace:F, fontSize:10, color:BERRY, align:"center" });
  });
  note(s, "各6か月間の比較。単施設・対照群なしの前後比較である点に留意");
  dummy(s);
  s.addNotes("『提案しました』ではなく『運用を変えて日数が短縮した』と言えるのが、この研究の到達点。");
}

/* =====================  19. まとめ  ===================== */
{
  const s = pres.addSlide();
  s.background = { color: INK };
  s.addShape(pres.ShapeType.ellipse, { x:10.1, y:0.9, w:3.9, h:3.9, fill:{color:TEAL, transparency:80}, line:{color:"FFFFFF",width:0} });
  s.addText("まとめ", { x:M, y:0.75, w:6.0, h:0.55, isTextBox:true, margin:0,
    fontFace:F, fontSize:28, bold:true, color:"FFFFFF" });
  const pts = [
    ["1","吸引力・発熱のリスクは低い","偏向角は最大 26.2° で規格基準 45° を下回り、示温ラベルは 40℃ でも変色しなかった"],
    ["2","実体は画像アーチファクトであり、距離に依存する","5 cm を超えると検出限界以下。手指・手関節と、頭部・体幹部は分けて考えるべき"],
    ["3","全例延期は過剰であり、部位別運用に置き換えられる","問診ではなく簡易磁石テストで判定し、診断までの日数を 24 日から 9 日に短縮した"],
  ];
  pts.forEach((p,i)=>{
    const y = 1.6 + i*1.42;
    s.addShape(pres.ShapeType.roundRect, { x:M, y, w:11.0, h:1.2, rectRadius:0.06, fill:{color:INK2}, line:{color:"FFFFFF", width:0} });
    badgeNum(s, M+0.3, y+0.33, 0.55, p[0], TEAL);
    s.addText(p[1], { x:M+1.05, y:y+0.15, w:9.6, h:0.45, isTextBox:true, margin:0,
      fontFace:F, fontSize:15, bold:true, color:"FFFFFF", valign:"middle" });
    s.addText(p[2], { x:M+1.05, y:y+0.62, w:9.6, h:0.45, isTextBox:true, margin:0,
      fontFace:F, fontSize:11.5, color:"9FADC2", valign:"middle" });
  });
  s.addText("謝辞：撮影にご協力いただいた診療放射線技師の皆様に深謝いたします。", {
    x:M, y:6.15, w:8.0, h:0.35, isTextBox:true, margin:0, fontFace:F, fontSize:11.5, color:"8E9AAE" });
  s.addShape(pres.ShapeType.roundRect, { x:M, y:6.6, w:5.6, h:0.4, rectRadius:0.2, fill:{color:"3A2A12"}, line:{color:AMBER, width:1} });
  s.addText("本スライドの数値・グラフ・画像はすべてダミーです", { x:M, y:6.6, w:5.6, h:0.4, isTextBox:true, margin:0,
    fontFace:F, fontSize:10.5, bold:true, color:"F0B860", align:"center", valign:"middle" });
  s.addNotes("3点に絞る。特に2点目が本研究の核心。");
}

pres.writeFile({ fileName: process.argv[2] || "magnet-nail-mri.pptx" })
  .then(f => console.log("written:", f));
