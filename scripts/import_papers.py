#!/usr/bin/env python3
# 真題套题导入器：扫描 db/imports/papers_inbox/*.json → 校验 → 按 name 去重
#   → 三段写入(papers → paper_passages → paper_questions) → 归档到 papers_done/
# 用法: python scripts/import_papers.py [--dry-run]
# JSON 结构(一文件=一套真题，对象)：
#   { "paper": {...}, "passages": [{ref, sub_category, body, ...}], "sections": [{section, category, sub_category, questions:[...]}] }
import json, os, sys, glob, re, urllib.request, urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INBOX = os.path.join(ROOT, "db/imports/papers_inbox")
DONE = os.path.join(ROOT, "db/imports/papers_done")
ENV = os.path.join(ROOT, "frontend/.env")

CAT = {"文字・語彙", "文法", "読解"}
SUB = {"漢字読み", "文脈規定", "言い換え類義", "用法",
       "文の文法1（文法形式の判断）", "文の文法2（文の組み立て）", "文章の文法",
       "内容理解（短文）", "内容理解（中文）", "内容理解（長文）",
       "統合理解", "主張理解（長文）", "情報検索"}
NEED_UNDERLINE = {"漢字読み", "言い換え類義", "用法"}

# 大問番号 → (category, sub_category)。真題の標準構成（N1 言語知識・読解）。
SECTION_SUB = {
    1:  ("文字・語彙", "漢字読み"),
    2:  ("文字・語彙", "文脈規定"),
    3:  ("文字・語彙", "言い換え類義"),
    4:  ("文字・語彙", "用法"),
    5:  ("文法", "文の文法1（文法形式の判断）"),
    6:  ("文法", "文の文法2（文の組み立て）"),
    7:  ("文法", "文章の文法"),
    8:  ("読解", "内容理解（短文）"),
    9:  ("読解", "内容理解（中文）"),
    10: ("読解", "内容理解（長文）"),
    11: ("読解", "統合理解"),
    12: ("読解", "主張理解（長文）"),
    13: ("読解", "情報検索"),
}
CLOZE_RE = re.compile(r'[（(](\d+)[）)]')   # README と同一：括弧が数字に密着、空白厳禁


def load_env():
    url = key = None
    for line in open(ENV, encoding="utf-8"):
        if line.startswith("VITE_SUPABASE_URL="): url = line.split("=", 1)[1].strip()
        if line.startswith("VITE_SUPABASE_ANON_KEY="): key = line.split("=", 1)[1].strip()
    return url, key


def req(method, path, body=None, headers=None):
    h = {"apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}
    if headers: h.update(headers)
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(URL + "/rest/v1" + path, data=data, headers=h, method=method)
    with urllib.request.urlopen(r) as resp:
        return resp.status, json.loads(resp.read() or "null")


def validate(doc):
    errs, warns = [], []
    paper = doc.get("paper") or {}
    if not paper.get("name"):
        errs.append("paper.name 缺失")

    refs = {p.get("ref") for p in doc.get("passages", [])}
    for p in doc.get("passages", []):
        tag = f"passage[{p.get('ref')}]"
        if not p.get("ref"): errs.append("passage.ref 缺失")
        if p.get("sub_category") not in SUB: errs.append(f"{tag} sub_category 非法: {p.get('sub_category')}")
        if not p.get("body"): errs.append(f"{tag} body 空")

    seq = 0
    for sec in doc.get("sections", []):
        sno, cat, sub = sec.get("section"), sec.get("category"), sec.get("sub_category")
        if cat not in CAT: errs.append(f"問題{sno}: category 非法 {cat}")
        if sub not in SUB: errs.append(f"問題{sno}: sub_category 非法 {sub}")
        # 大問番号 ↔ category/sub_category 整合性（SECTION_SUB に登録があれば照合）
        if sno in SECTION_SUB and SECTION_SUB[sno] != (cat, sub):
            errs.append(f"問題{sno}: 与标准映射不符，应为 {SECTION_SUB[sno]}，实为 ({cat},{sub})")

        for q in sec.get("questions", []):
            seq += 1
            tag = f"seq{seq}(問題{sno})"
            if not q.get("question"): errs.append(f"{tag} question 空")

            if q.get("blanks"):
                ns = set()
                for b in q["blanks"]:
                    ns.add(b.get("n"))
                    if not (isinstance(b.get("correct"), int) and 1 <= b["correct"] <= 4):
                        errs.append(f"{tag} blank n={b.get('n')} correct 非法")
                    if len(b.get("options", [])) != 4:
                        errs.append(f"{tag} blank n={b.get('n')} options≠4")
                marks = {int(m) for m in CLOZE_RE.findall(q.get("question", ""))}
                if marks != ns:
                    errs.append(f"{tag} cloze 标记{sorted(marks)} ≠ blanks{sorted(ns)}")
            else:
                opts = q.get("options", [])
                if len(opts) != 4 or not all(opts):
                    errs.append(f"{tag} options 必须4个非空")
                if not (isinstance(q.get("correct"), int) and 1 <= q["correct"] <= 4):
                    errs.append(f"{tag} correct 非法")

            # 読解の passage 参照完整性
            if cat == "読解":
                if q.get("passage_ref") not in refs:
                    errs.append(f"{tag} passage_ref『{q.get('passage_ref')}』未在 passages 中定义")
            elif q.get("passage_ref"):
                errs.append(f"{tag} 非读解题不应有 passage_ref")

            # underline 告警（非阻断）
            if sub in NEED_UNDERLINE:
                u = q.get("underline_text")
                if not u:
                    warns.append(f"{tag} underline_text 缺失（前端无法划线）")
                elif u not in (q.get("question") or ""):
                    warns.append(f"{tag} underline_text「{u}」不在题干中")
    return errs, warns


def flatten_question(q, paper_id, passage_id, seq, section, cat, sub):
    # 全字段统一输出（不适用填 None）：PostgREST 批量插入要求数组内所有对象 key 集合一致。
    o = q.get("options") or [None, None, None, None]
    return {
        "paper_id": paper_id, "passage_id": passage_id, "seq": seq,
        "section": section, "category": cat, "sub_category": sub,
        "question": q["question"], "explanation": q.get("explanation"),
        "underline_text": q.get("underline_text"),
        "option_underlines": q.get("option_underlines"),
        "points": q.get("points"),
        "option1": o[0], "option2": o[1], "option3": o[2], "option4": o[3],
        "correct_option": q.get("correct") if not q.get("blanks") else None,
        "blanks": q.get("blanks"),
    }


def paper_exists(name):
    _, rows = req("GET", f"/papers?name=eq.{urllib.parse.quote(name)}&select=id")
    return rows[0]["id"] if rows else None


def write_paper(doc):
    paper = doc["paper"]
    _, res = req("POST", "/papers", [paper], {"Prefer": "return=representation"})
    pid = res[0]["id"]
    try:
        # paper_passages：保留 ref（NOT NULL 存储列，带 UNIQUE(paper_id,ref)）
        ref2id = {}
        for p in doc.get("passages", []):
            body = dict(p)
            body["paper_id"] = pid
            _, res = req("POST", "/paper_passages", [body], {"Prefer": "return=representation"})
            ref2id[p["ref"]] = res[0]["id"]

        rows, seq = [], 0
        for sec in doc["sections"]:
            for q in sec["questions"]:
                seq += 1
                rows.append(flatten_question(
                    q, pid, ref2id.get(q.get("passage_ref")), seq,
                    sec["section"], sec["category"], sec["sub_category"]))
        _, res = req("POST", "/paper_questions", rows, {"Prefer": "return=representation"})
        return pid, len(ref2id), len(res)
    except Exception:
        # 非事务写入：任一段失败则级联删除已建的 paper（passages/questions 随 FK CASCADE 清除），保证重跑干净
        try:
            req("DELETE", f"/papers?id=eq.{pid}")
            print(f"   ↺ 写入失败，已回滚 paper id {pid}")
        except Exception as ce:
            print(f"   ! 回滚失败，请手动删除 paper id {pid}: {ce}")
        raise


def main():
    dry = "--dry-run" in sys.argv
    files = sorted(glob.glob(os.path.join(INBOX, "*.json")))
    if not files:
        print("papers_inbox 为空，无待导入文件。"); return
    for f in files:
        name = os.path.basename(f)
        doc = json.load(open(f, encoding="utf-8"))
        nq = sum(len(s.get("questions", [])) for s in doc.get("sections", []))
        np = len(doc.get("passages", []))
        errs, warns = validate(doc)
        pname = (doc.get("paper") or {}).get("name", "?")
        print(f"\n[{name}] 套题「{pname}」 文章{np} 题目{nq} 非法{len(errs)} 告警{len(warns)}")
        for e in errs: print(f"   ✗ {e}")
        for w in warns: print(f"   ⚠ {w}")
        if errs:
            print(f"   ! {name} 含非法项，整文件跳过，请修正后重跑。"); continue

        dup = paper_exists(pname)
        if dup:
            print(f"   ↷ papers 已存在「{pname}」(id {dup})，整套跳过。")
            if not dry: os.replace(f, os.path.join(DONE, name))
            continue

        if dry:
            print(f"   (dry-run) 将写入 1 套 / 文章{np} / 题目{nq}")
        else:
            pid, npw, nqw = write_paper(doc)
            print(f"   写入 paper id {pid}：文章 {npw} 篇、题目 {nqw} 题")
            os.replace(f, os.path.join(DONE, name))


URL, KEY = load_env()
if __name__ == "__main__":
    main()
