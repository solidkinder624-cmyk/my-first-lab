# -*- coding: utf-8 -*-
import formulas, math, re, sys
xl = formulas.ExcelModel().loads("verify.xlsx").finish()
sol = xl.calculate()

def get(sheet, cell):
    key = f"'[VERIFY.XLSX]{sheet.upper()}'!{cell}"
    for k, v in sol.items():
        if k.upper().endswith(f"]{sheet.upper()}'!{cell}"):
            try:
                val = v.value[0, 0]
            except Exception:
                val = v
            return val
    return "<not found>"

def norm(v):
    if hasattr(v, "item"):
        try: v = v.item()
        except Exception: pass
    if isinstance(v, str): return v.strip()
    return v

checks = []
def chk(label, sheet, cell, expect, tol=0.02):
    got = norm(get(sheet, cell))
    if isinstance(expect, (int, float)) and not isinstance(expect, bool):
        try:
            ok = abs(float(got) - float(expect)) <= tol
        except Exception:
            ok = False
    else:
        ok = (str(got) == str(expect))
    checks.append((ok, f"{sheet}!{cell}", label, got, expect))

# --- 02 偏向角：F = m(g)*9.80665*tanθ ---
chk("磁気力 D-1 (0.085g, 18°)", "02_偏向角_記録", "H2", round(0.085*9.80665*math.tan(math.radians(18)),3), 0.002)
chk("45°判定 18° → 適合", "02_偏向角_記録", "I2", "適合")
chk("45°判定 46° → 要確認", "02_偏向角_記録", "I7", "要確認")

# --- 03 集計：S-01 / 3T は 18,20,22 → n=3 mean=20 sd=2 ---
chk("S-01 参照", "03_偏向角_集計", "A5", "S-01")
chk("3T n",      "03_偏向角_集計", "J5", 3)
chk("3T 平均θ",  "03_偏向角_集計", "K5", 20.0)
chk("3T SD",     "03_偏向角_集計", "L5", 2.0)
chk("3T 95%CI半幅", "03_偏向角_集計", "M5", 4.97, 0.02)
chk("3T 最大θ",  "03_偏向角_集計", "N5", 22.0)
chk("3T 判定",   "03_偏向角_集計", "O5", "適合")
chk("1.5T n",    "03_偏向角_集計", "D5", 2)
chk("1.5T 平均", "03_偏向角_集計", "E5", 12.0)
# S-03 3T は 46° 1件 → 要確認
chk("S-03 参照", "03_偏向角_集計", "A7", "S-03")
chk("S-03 3T 判定", "03_偏向角_集計", "O7", "要確認")

# --- 05 集計（① SE=6 TSE=7 GRE=8 / ② TE5=16..TE30=20 / ③ 0cm=26..20cm=30）---
# ① GRE(距離0,角度0): 3T → 120,130,230 = 3件 平均160 / 1.5T → 70,80 = 2件 平均75
chk("① GRE 3T n",    "05_アーチファクト_集計", "E8", 3)
chk("① GRE 3T 平均",  "05_アーチファクト_集計", "F8", 160.0, 0.1)
chk("① GRE 1.5T n",   "05_アーチファクト_集計", "B8", 2)
chk("① GRE 1.5T 平均", "05_アーチファクト_集計", "C8", 75.0, 0.1)
chk("① SE 3T n",      "05_アーチファクト_集計", "E6", 1)
chk("① SE 3T 平均",    "05_アーチファクト_集計", "F6", 30.0, 0.1)
chk("① TSE 3T n（該当なし）", "05_アーチファクト_集計", "E7", 0)
# ② TE別 GRE 距離0: TE15 3T → 120,130 平均125 / TE30 3T → 230
chk("② TE15 3T 平均", "05_アーチファクト_集計", "F18", 125.0, 0.1)
chk("② TE30 3T 平均", "05_アーチファクト_集計", "F20", 230.0, 0.1)
# ③ 距離別 GRE: 3T 0cm → 120,130,230 平均160 / 2cm → 60 / 5cm → 8 ; 1.5T 5cm → 4
chk("③ 0cm 3T 平均",  "05_アーチファクト_集計", "F26", 160.0, 0.1)
chk("③ 2cm 3T 平均",  "05_アーチファクト_集計", "F27", 60.0, 0.1)
chk("③ 5cm 3T 平均",  "05_アーチファクト_集計", "F28", 8.0, 0.1)
chk("③ 5cm 1.5T 平均","05_アーチファクト_集計", "C28", 4.0, 0.1)

chk("空行の平均は空", "03_偏向角_集計", "E10", "")
chk("空行のCIは空", "03_偏向角_集計", "G10", "")
chk("空行の判定は空", "03_偏向角_集計", "I10", "")
chk("撮影ログ 所要時間", "10_撮影ログ", "E2", 2.5, 0.01)

# --- 06 発熱 ---
chk("全て未変色 → 40℃未満", "06_発熱_記録", "M2", "40℃未満")
chk("50℃まで変色 → 50〜55℃", "06_発熱_記録", "M3", "50〜55℃")

# --- 07/08 延期 ---
chk("依頼→実施 日数", "07_延期症例", "J2", 30)
chk("延期例の日数",   "07_延期症例", "K2", 30)
chk("非延期は空",     "07_延期症例", "L2", "")
chk("対象症例数", "08_延期集計", "B4", 5)
chk("延期件数",   "08_延期集計", "B5", 3)
chk("延期率",     "08_延期集計", "B6", 0.6, 0.001)
chk("未受検件数", "08_延期集計", "B7", 1)
chk("中央値(全体) 8,10,20,30,40 → 20", "08_延期集計", "B8", 20.0, 0.01)
chk("中央値(延期) 20,30,40 → 30",      "08_延期集計", "B9", 30.0, 0.01)
chk("中央値(非延期) 8,10 → 9",         "08_延期集計", "B10", 9.0, 0.01)
chk("遅れの差 30-9=21",                "08_延期集計", "B11", 21.0, 0.01)
chk("頭部の延期件数", "08_延期集計", "B15", 2)
chk("部位別合計",     "08_延期集計", "B20", 3)

# --- 09 スクリーニング TP3 FP1 FN1 TN3 ---
chk("TP", "09_スクリーニング検証", "H6", 3)
chk("FP", "09_スクリーニング検証", "I6", 1)
chk("FN", "09_スクリーニング検証", "H7", 1)
chk("TN", "09_スクリーニング検証", "I7", 3)
chk("感度 3/4",   "09_スクリーニング検証", "H10", 0.75, 0.001)
chk("特異度 3/4", "09_スクリーニング検証", "H11", 0.75, 0.001)
chk("正確度 6/8", "09_スクリーニング検証", "H14", 0.75, 0.001)

ng = [c for c in checks if not c[0]]
for ok, ref, label, got, exp in checks:
    print(("  OK " if ok else "  NG ") + f"{ref:34s} {label:32s} got={got!r} expect={exp!r}")
print(f"\n{len(checks)-len(ng)}/{len(checks)} passed")

# エラー値の全面走査
errs = {}
for k, v in sol.items():
    try: val = v.value[0, 0]
    except Exception: continue
    if isinstance(val, str) and re.match(r"^#(NAME|REF|VALUE|DIV|N/A|NUM|NULL)", val):
        errs.setdefault(val.split("?")[0], []).append(k)
if errs:
    print("\nERROR CELLS:")
    for e, ks in errs.items():
        print(f"  {e}: {len(ks)} 件  例: {ks[:3]}")
else:
    print("エラー値（#NAME? / #REF! / #VALUE! 等）: 0 件")
sys.exit(1 if ng else 0)
