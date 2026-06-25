# 真題套题录入规范

整套 N1 真题(文字・語彙 + 文法 + 読解)的录入。和错题录入(`README.md`)平行,走独立脚本与独立工作目录。

## 流程
1. 在 `papers_inbox/` 放 JSON（**一文件 = 一套真题**，是对象不是数组），文件名建议 `paper_<年月>.json`。
2. `python scripts/import_papers.py --dry-run` 校验（看 ✗ 非法 / ⚠ 告警）。
3. 确认后去掉 `--dry-run` 写入 Supabase，文件自动归档到 `papers_done/`。
4. 写入分三段：`papers`（套题元信息）→ `paper_passages`（读解共享文章）→ `paper_questions`（有序题目）。
5. 去重按 `paper.name`（UNIQUE）；已存在的整套跳过。

## 数据表（见 `supabase/migrations/0003_papers.sql` / `db/init.sql`）
- `papers`：一套真题一行。`paper_questions` 列与 `mistakes` 同构，模拟交卷后做错的题可直拷投影进 `mistakes`。
- `paper_passages`：读解一篇文章挂多道独立小问（1:N），非读解题不用。
- `paper_questions`：有序题目，`seq` 全卷顺序、`section` 大問号、`passage_ref → passage_id`。

## JSON 结构
```jsonc
{
  "paper": {
    "name": "JLPT N1 2010年7月 真題",   // ← 去重键，必填且唯一
    "level": "N1",
    "exam_year": 2010,
    "exam_session": "7月",
    "source_book": "...",               // 做错入库时写回 mistakes.source_book
    "total_minutes": 110
  },
  "passages": [                          // 读解共享文章；ref 是本文件内的本地引用键
    { "ref": "p8a", "sub_category": "内容理解（短文）", "title": "...", "body": "本文..." }
    // 統合理解 A/B 用 body + body_b
  ],
  "sections": [                          // 按大問分节
    {
      "section": 1, "category": "文字・語彙", "sub_category": "漢字読み",
      "questions": [
        { "question": "...", "underline_text": "拍車",
          "options": ["...","...","...","..."], "correct": 1, "explanation": "..." }
      ]
    },
    {
      "section": 7, "category": "文法", "sub_category": "文章の文法",
      "questions": [
        { "question": "...(41)...(42)...",   // cloze：标记规则同错题录入(括号紧贴数字、禁空格)
          "blanks": [
            { "n": 41, "options": ["...","...","...","..."], "correct": 1, "explanation": "..." }
          ],
          "explanation": "テーマ：..." }
      ]
    },
    {
      "section": 8, "category": "読解", "sub_category": "内容理解（短文）",
      "questions": [
        { "passage_ref": "p8a",          // ← 读解题必填，指向 passages[].ref
          "question": "筆者が最も言いたいことは何か。",
          "options": ["...","...","...","..."], "correct": 2, "explanation": "..." }
      ]
    }
  ]
}
```

## 字段约定
- 题目用 `options:[4]` + `correct:1〜4`（脚本展开成 `option1-4 + correct_option`），比错题录入的扁平字段更紧凑。
- `seq` **不写**，由脚本按 sections→questions 出现顺序自动 1..N 编号。
- 読解题 `passage_ref` 必填且必须命中 `passages[].ref`；非读解题不得有 `passage_ref`。
- cloze 题 `(41)` 标记严格遵守 [README.md](README.md) 的「cloze 标记规则」（括号紧贴数字、禁空格），脚本会正则校验标记集合 == `blanks[].n` 集合。
- `underline_text` 规则同错题录入；漢字読み/言い換え類義/用法 缺失会 ⚠ 告警。

## 大問 → category / sub_category 映射（脚本强校验）
| 問題 | category | sub_category |
|---|---|---|
| 1 | 文字・語彙 | 漢字読み |
| 2 | 文字・語彙 | 文脈規定 |
| 3 | 文字・語彙 | 言い換え類義 |
| 4 | 文字・語彙 | 用法 |
| 5 | 文法 | 文の文法1（文法形式の判断） |
| 6 | 文法 | 文の文法2（文の組み立て） |
| 7 | 文法 | 文章の文法 |
| 8 | 読解 | 内容理解（短文） |
| 9 | 読解 | 内容理解（中文） |
| 10 | 読解 | 内容理解（長文） |
| 11 | 読解 | 統合理解 |
| 12 | 読解 | 主張理解（長文） |
| 13 | 読解 | 情報検索 |

> `section` 与 `category/sub_category` 必须与上表一致，否则 ✗ 报错。枚举与 `frontend/src/api.js` 的 `SUB_CATEGORIES` 完全对齐。

## 模拟交卷 → 错题入库
模拟做完，做错的题按**题干去重**并入 `mistakes`：已存在则调 `increment_error` RPC（次数+1），不存在则 INSERT，`source_page` 标 `問題{section}-{seq}` 指回真题来源。读解错题投影时把所属文章正文拼进题干，使其在练习模式可独立成立。
