# 错题录入规范

## 流程
1. 在 `inbox/` 放 JSON（记录数组），文件名建议 `batch_YYYY-MM-DD.json`。
2. `python3 scripts/import_errors.py --dry-run` 校验（看 ✗ 非法 / ⚠ 告警）。
3. 确认后去掉 `--dry-run` 写入 Supabase，文件自动归档到 `done/`。
4. 校验自动按题干去重，并检查 category / sub_category 枚举与选项。

## 字段
| 字段 | 必填 | 说明 |
|---|---|---|
| category | ✓ | 文字・語彙 / 文法 / 読解 |
| sub_category | ✓ | 见脚本 SUB 枚举 |
| question | ✓ | 题干 |
| option1〜4 | ✓（非 blanks 题） | 四个选项 |
| correct_option | ✓（非 blanks 题） | 1〜4 |
| explanation | 建议 | 解析 |
| **underline_text** | **见下** | 题干中需划线的语句，前端按此匹配加下线 |
| source_book / source_page | 可选 | 来源；缺口统计用 |
| blanks | 仅多空格 cloze 题 | `[{n, options:[...], correct, explanation}]` |

## cloze 题（blanks）题干标记规则（易漏，必须遵守）
前端 `Practice.vue renderQuestion()` 用正则 `/[（(](\d+)[）)]/g` 把题干里的空格标记替换成可点击的高亮 `blank-marker`。

- 每个空在 `question` 里必须写成 **`(16)`**（括号紧贴数字，**括号与数字之间不能有空格**）；半角 `()` 或全角 `（）` 均可，但**不要加空格**，否则正则不匹配 → 退化成普通文字，不高亮、不可点。
- ✗ 反例：`（　16　）`（全角空格）、`( 16 )`（半角空格）都无效。
- 标记里的数字必须与 `blanks[].n` 一一对应。
- 非数字的括号（如 `（注）`）不受影响，正常保留。

## underline_text 规则（易漏，必须遵守）
前端 `Practice.vue renderQuestion()` 靠 `underline_text` 在题干中划线；缺失则不划线，读音/言い換え题会无法成立。

- **漢字読み**：标注被考的汉字词本身。例：「余暇を…」→ `余暇`；「…管轄です」→ `管轄`。
- **言い換え類義**：标注**与选项对应的完整短语**，不能只标核心词。
  例：「材料を**ロスしない**よう…」选项都是「～しない」形式 → `ロスしない`（不是 `ロス`）。
- **用法**：标注被考词；如各选项下线位置不同，用 `option_underlines` 数组分别指定。
- 文脈規定 / 文の文法1・2 等填空・排序题：题干已有（　）或 ＿＿，**不需要** underline_text。

校验脚本对 `漢字読み / 言い換え類義 / 用法` 缺 underline_text 或词不在题干中会输出 `⚠` 告警（非阻断）。dry-run 出现 ⚠ 必须先补齐再写入。
