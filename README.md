# N1 錯題記録 (japanese-mistakes)

JLPT N1 備考用の錯題管理アプリ。db / api は Docker、フロントは宿主で起動（macOS bind mount + Vite 監視の不安定問題を回避）。

---

## 1. 機能要求

### 背景
- 利用者：N1 備考中
- 目的：練習中に間違えた問題を記録し、題型別に再演習できる

### コア機能（MVP）

| # | 機能 | 説明 |
|---|------|------|
| 1 | 錯題録入 | 題型・題目・選択肢4つ・正解・解説を入力して保存 |
| 2 | 錯題一覧 | 全件表示。題型でフィルタ可能。間違い回数で降順 |
| 3 | 練習モード | 題型を選んで開始 → ランダム出題 → 自動採点 → 不正解なら DB の `error_count +1` |
| 4 | 削除 | 一覧から個別に削除 |

### 非機能要求

- ローカル個人利用、認証なし
- 全コンポーネント Docker 上で動作
- 「掌握済み」概念なし、すべての錯題は永続的に題庫に残る
- 聴解は本バージョンでは扱わない

### 題型（大分類 / 小分類）

JLPT 公式ガイドブック（p.20「N1 大問のねらい」）に準拠。

| 大分類 | 小分類（小問数の目安） |
|--------|----------------------|
| 文字・語彙 | 漢字読み(6) / 文脈規定(7) / 言い換え類義(6) / 用法(6) |
| 文法 | 文の文法1（文法形式の判断）(10) / 文の文法2（文の組み立て）(5) / 文章の文法(5) |
| 読解 | 内容理解（短文）(4) / 内容理解（中文）(9) / 内容理解（長文）(4) / 統合理解(3) / 主張理解（長文）(4) / 情報検索(2) |

子類別はフロント側で固定。後で追加・変更する場合は `frontend/src/api.js` の `SUB_CATEGORIES` を更新。

### 採点ルール

選択肢は 1〜4 の整数。`selected === correct_option` で自動判定。
不正解時のみ `error_count` をインクリメントし `last_wrong_at` を更新。

---

## 2. 技術構成

```
┌────────────┐    /api    ┌──────────────┐   SQL    ┌──────────────┐
│  Vue 3 SPA │ ─────────▶ │  PostgREST   │ ───────▶ │  PostgreSQL  │
│  (Vite)    │            │  (zero-code) │          │      16      │
└────────────┘            └──────────────┘          └──────────────┘
   :5173                       :3000                     :55432
   ↑ ホストで実行             ↑ Docker                  ↑ Docker
```

Vite を Docker bind mount で動かすと macOS では監視イベントが落ちて固まることが多発。db / api は監視不要なので Docker のまま、Vite は宿主に出した。

| 層 | 採用 | 理由 |
|----|------|------|
| DB | PostgreSQL 16 | 要件通り |
| API | PostgREST | テーブル定義から自動的に REST API を生成。後端コード 0 行 |
| Frontend | Vue 3 + Vite + Element Plus | UI 早期立ち上げ |
| HTTP | axios | Vite dev server の `/api` プロキシ経由で PostgREST へ |

### なぜ「フロント直結 DB」にしなかったか

- ブラウザは PostgreSQL の TCP プロトコルに直接接続できない
- DB 認証情報のフロント露出はセキュリティリスク
- PostgREST は HTTP 化のみを担う薄い層で、自前 API コードは不要

---

## 3. データモデル

```sql
CREATE TABLE mistakes (
  id              SERIAL PRIMARY KEY,
  category        TEXT NOT NULL CHECK (category IN ('文字・語彙', '文法', '読解')),
  sub_category    TEXT,                  -- N1 真題の小分類（フロント側で値を制限）
  question        TEXT NOT NULL,
  option1         TEXT NOT NULL,
  option2         TEXT NOT NULL,
  option3         TEXT NOT NULL,
  option4         TEXT NOT NULL,
  correct_option  SMALLINT NOT NULL CHECK (correct_option BETWEEN 1 AND 4),
  underline_text  TEXT,                  -- 題目内で下線を引く語句（言い換え類義などで使用）
  explanation     TEXT,
  error_count     INTEGER NOT NULL DEFAULT 1,
  last_wrong_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

`error_count` の原子的インクリメントには PL/pgSQL 関数 `increment_error(mistake_id)` を使用（PostgREST から `POST /rpc/increment_error` で呼び出せる）。

---

## 4. 起動方法

### ワンショット起動

```bash
cd /Users/kozen/work/project/japanese-mistakes
./start.sh
```

`start.sh` は Docker (db + api) を起動し、続けて宿主で Vite を立ち上げる。Ctrl+C で Vite が止まる（Docker は動いたまま）。

### 個別操作

```bash
./start.sh           # 冪等起動 (健全なサービスはそのまま)
./stop.sh            # Vite だけ停止 (db/api は常駐)
./restart.sh         # 個別修復 (壊れているものだけ直す)

# 後端を完全停止したい場合
docker compose stop              # 停止（データ保持）
docker compose down              # 削除（ボリューム保持）
docker compose down -v           # ボリュームごと削除（DB 全消し）
```

通常は db / api を Docker で常駐させ、Vite だけを `start.sh` / `stop.sh` で出し入れする運用が軽い。

| サービス | URL | 場所 | 用途 |
|---------|-----|------|------|
| Web   | http://localhost:5173 | 宿主 | アプリ画面 |
| API   | http://localhost:3000 | Docker | PostgREST（直叩き可） |
| DB    | localhost:55432       | Docker | psql 等（user: app / pass: app_pass / db: jp_mistakes）。5432 競合回避のため 55432 にマップ |

### よくある不具合

- **Docker daemon が応答しない / `docker compose` が固まる** → `./restart.sh` を実行。Vite + 滞留 CLI を kill → Docker Desktop 再起動 → db + api 起動 → start.sh に exec して前端まで一気に立て直す。
- **port 競合エラー** → `./start.sh` の事前チェックで該当 PID を表示する。前回の Vite / docker container が残っている場合があるので kill するか `docker compose down`。
- **Vite 起動時に `Cannot find module` 系エラー** → 宿主 `frontend/node_modules` がコンテナ環境（linux-arm64）時代の遺物を含んでいる。`rm -rf frontend/node_modules && npm install` で解消。
- **CLI と Docker Desktop のバージョン不一致 (500 Internal Server Error)** → `brew upgrade docker` で揃える。

---

## 5. API リファレンス（PostgREST 自動生成）

| 操作 | メソッド + パス |
|------|---------------|
| 一覧（題型フィルタ） | `GET /mistakes?category=eq.文法&order=error_count.desc` |
| 一覧（小分類フィルタ） | `GET /mistakes?category=eq.文字・語彙&sub_category=eq.言い換え類義` |
| 1 件登録 | `POST /mistakes` （Body: 全フィールド） |
| 部分更新 | `PATCH /mistakes?id=eq.<id>` |
| 削除 | `DELETE /mistakes?id=eq.<id>` |
| 間違い回数 +1 | `POST /rpc/increment_error` Body: `{"mistake_id": <id>}` |

---

## 6. ディレクトリ構成

```
japanese-mistakes/
├── docker-compose.yml
├── README.md
├── start.sh                    # 冪等起動 (db+api を Docker で / Vite を宿主で)
├── stop.sh                     # Vite のみ停止 (db/api は残す)
├── restart.sh                  # 個別修復 (壊れているものだけ直す)
├── scripts/
│   └── lib.sh                  # 共通ヘルスチェック関数
├── db/
│   └── init.sql                # スキーマ・関数・権限
└── frontend/
    ├── package.json
    ├── vite.config.js          # /api → http://localhost:3000 にプロキシ
    ├── index.html
    └── src/
        ├── main.js             # ルーター設定
        ├── App.vue             # レイアウト・ナビ
        ├── api.js              # PostgREST 呼び出しラッパ
        └── views/
            ├── AddMistake.vue
            ├── MistakeList.vue
            └── Practice.vue
```

---

## 7. 題型別データ入力規約

題型ごとに `question` / `option1-4` / `underline_text` の埋め方が異なる。AI / スクリプトで一括登録する場合は下記に従う。

### 文脈規定 / 言い換え類義 / 漢字読み

- `question`: 出題文の全体（句点まで）
- `underline_text`: 出題文中で下線を引く語句（１個）
- `option1-4`: 短い選択肢（語・短句）
- `correct_option`: 1〜4

例（言い換え類義）:
```json
{
  "category": "文字・語彙", "sub_category": "言い換え類義",
  "question": "メディアはいつも人々の不安をあおるニュースを流す。",
  "underline_text": "あおる",
  "option1": "否定する", "option2": "刺激する",
  "option3": "同感する", "option4": "主張する",
  "correct_option": 2
}
```

### 用法

- `question`: 出題対象の単語そのもの（例: `由来`）
- `underline_text`: **空（null）**
- `option1-4`: それぞれが完整な例文（その単語を含む）
- `correct_option`: 1〜4
- フロントの `Practice.vue` は `sub_category === '用法'` のとき、選択肢中の `question` 文字列を自動的に下線表示する

例:
```json
{
  "category": "文字・語彙", "sub_category": "用法",
  "question": "由来",
  "option1": "「サボる」という言葉は、フランス語に由来している。",
  "option2": "人類の由来は、三十万年前にまでさかのぼる。",
  "option3": "日本では、年の初めに見る夢に富士山が出てくると由来が良いとされている。",
  "option4": "この人物が今回の事件に由来している可能性は低そうだ。",
  "correct_option": 1
}
```

### 文の文法1（文法形式の判断）

- `question`: 出題文の全体。空欄は全角括弧と全角空白で `（　）` と表記
- `underline_text`: **空（null）**
- `option1-4`: 文法形式（語・句）
- `correct_option`: 1〜4
- 会話文の場合は話者名と「」を含めてそのまま記載（改行不要、連結する）

例:
```json
{
  "category": "文法", "sub_category": "文の文法1（文法形式の判断）",
  "question": "まだ新人（　）、仕事に対して無責任な言動を取ることは許されない。",
  "option1": "かと思いきや", "option2": "だとはいえ",
  "option3": "というもの", "option4": "ではあるまいし",
  "correct_option": 2
}
```

### 文の文法2（文の組み立て）

- `question`: 出題文。4 つの空欄は `＿＿`（全角アンダースコア 2 つ）で表し、★ 位置はその中の 1 箇所を `★` で記す
- `underline_text`: **空（null）**
- `option1-4`: 並び替えの 4 つの断片（元の問題の番号順に保つ）
- `correct_option`: **★ 位置に入る選択肢の番号**（並びの 2 番目とは限らず、出題側が指定する位置）
- `explanation` 冒頭で「正しい並び: A→B→C→D」と完成文を必ず示す（運用上の必須項目）

例:
```json
{
  "category": "文法", "sub_category": "文の文法2（文の組み立て）",
  "question": "相手は負けを知らない強豪チーム ＿＿ ★ ＿＿ ＿＿ だろう。",
  "option1": "とはいえ", "option2": "ではない",
  "option3": "勝てない相手", "option4": "今の私達なら",
  "correct_option": 4,
  "explanation": "正しい並び: 1→4→3→2（とはいえ→今の私達なら→勝てない相手→ではない）\n完成文: 相手は負けを知らない強豪チームとはいえ、今の私達なら勝てない相手ではないだろう。\n【ポイント】..."
}
```

### `explanation`（任意・全題型共通）

複数行を改行 `\n` で書く。フロント側で `white-space: pre-wrap` 描画される。推奨フォーマット:

```
【意味】<単語>：<辞書的意味>
1. ✓ <正解選択肢の解説>
2. ✗ <誤答>: 正しくは「<置換語>」
3. ✗ ...
4. ✗ ...
```

### 登録方法（curl で一括）

PostgREST に直接 POST。配列で一括投入可能。

```bash
curl -X POST 'http://localhost:3000/mistakes' \
  -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  --data-binary @batch.json
```

`explanation` を後付けする場合は PATCH:

```bash
curl -X PATCH 'http://localhost:3000/mistakes?id=eq.142' \
  -H 'Content-Type: application/json' \
  -d '{"explanation": "..."}'
```

---

## 8. 既知の制約・拡張余地

- 認証なし。ローカル個人利用前提
- 聴解未対応（音声アップロード機能なし）
- バックアップは `docker compose exec db pg_dump -U app jp_mistakes > backup.sql` で手動
- 将来：間隔反復（SRS）、画像添付、CSV インポート/エクスポート、統計ダッシュボード等
