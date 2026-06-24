#!/usr/bin/env python3
# 错题导入器：扫描 db/imports/inbox/*.json → 校验 → 去重 → POST Supabase → 归档到 done/
# 用法: python3 scripts/import_errors.py [--dry-run]
import json, os, sys, glob, urllib.request, urllib.parse, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INBOX = os.path.join(ROOT, "db/imports/inbox")
DONE = os.path.join(ROOT, "db/imports/done")
ENV = os.path.join(ROOT, "frontend/.env")

CAT = {"文字・語彙", "文法", "読解"}
# 下線必須の小分類：前端は underline_text で題干に下線を引く。
# 漢字読み/言い換え類義/用法 は対象語を明示しないと出題が成立しない。
NEED_UNDERLINE = {"漢字読み", "言い換え類義", "用法"}
SUB = {"漢字読み", "文脈規定", "言い換え類義", "用法",
       "文の文法1（文法形式の判断）", "文の文法2（文の組み立て）", "文章の文法",
       "内容理解（短文）", "内容理解（中文）", "内容理解（長文）",
       "統合理解", "主張理解（長文）", "情報検索"}

def load_env():
    url = key = None
    for line in open(ENV):
        if line.startswith("VITE_SUPABASE_URL="): url = line.split("=", 1)[1].strip()
        if line.startswith("VITE_SUPABASE_ANON_KEY="): key = line.split("=", 1)[1].strip()
    return url, key

def req(method, path, key, body=None, headers=None):
    h = {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    if headers: h.update(headers)
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(URL + "/rest/v1" + path, data=data, headers=h, method=method)
    with urllib.request.urlopen(r) as resp:
        return resp.status, json.loads(resp.read() or "null")

def existing_questions(key):
    # 拉取现有题干用于去重
    q = "/mistakes?select=question&limit=5000"
    _, rows = req("GET", q, key)
    return {x["question"] for x in rows}

def validate(rec):
    errs = []
    if rec.get("category") not in CAT: errs.append("category")
    if rec.get("sub_category") not in SUB: errs.append("sub_category")
    if rec.get("blanks") is None:
        if not (isinstance(rec.get("correct_option"), int) and 1 <= rec["correct_option"] <= 4):
            errs.append("correct_option")
        for k in ("option1", "option2", "option3", "option4"):
            if not rec.get(k): errs.append(k)
    if not rec.get("question"): errs.append("question")
    return errs

def warn(rec):
    # 非阻断の注意喚起（前端の表示品質に関わる）
    ws = []
    if rec.get("sub_category") in NEED_UNDERLINE:
        u = rec.get("underline_text")
        if not u:
            ws.append("underline_text 缺失（前端无法划线）")
        elif u not in (rec.get("question") or ""):
            ws.append(f"underline_text「{u}」不在题干中（无法匹配划线）")
    return ws

def main():
    dry = "--dry-run" in sys.argv
    files = sorted(glob.glob(os.path.join(INBOX, "*.json")))
    if not files:
        print("inbox 为空，无待导入文件。"); return
    seen = existing_questions(KEY)
    grand = 0
    for f in files:
        name = os.path.basename(f)
        recs = json.load(open(f))
        if not isinstance(recs, list): recs = [recs]
        payload, skipped, bad, warns = [], [], [], []
        for i, r in enumerate(recs):
            e = validate(r)
            if e: bad.append((i, e)); continue
            for w in warn(r): warns.append((i, w))
            if r["question"] in seen: skipped.append(r["question"][:20]); continue
            payload.append(r); seen.add(r["question"])
        print(f"\n[{name}] 共{len(recs)}条 → 新增{len(payload)} 跳过(重复){len(skipped)} 非法{len(bad)}")
        for i, e in bad: print(f"   ✗ 第{i+1}条字段问题: {e}")
        for i, w in warns: print(f"   ⚠ 第{i+1}条: {w}")
        for s in skipped: print(f"   ↷ 已存在: {s}…")
        if bad:
            print(f"   ! {name} 含非法记录，整文件跳过，请修正后重跑。"); continue
        if not payload:
            print(f"   - 无新增，归档。")
        elif dry:
            print(f"   (dry-run) 将写入 {len(payload)} 条")
        else:
            st, res = req("POST", "/mistakes", KEY, payload, {"Prefer": "return=representation"})
            print(f"   HTTP {st} 写入 {len(res)} 条: id {res[0]['id']}–{res[-1]['id']}")
            grand += len(res)
        if not dry:
            os.replace(f, os.path.join(DONE, name))
    if not dry:
        print(f"\n合计写入 {grand} 条。")
        st, _ = req("GET", "/mistakes?select=count", KEY, headers={"Prefer": "count=exact"})

URL, KEY = load_env()
if __name__ == "__main__":
    main()
