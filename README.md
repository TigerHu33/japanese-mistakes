# N1 錯題記録 (japanese-mistakes)

JLPT N1 備考用の錯題管理アプリ。Docker Compose 一発で起動。

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

| 大分類 | 小分類 |
|--------|--------|
| 文字・語彙 | 漢字読み / 文脈規定 / 言い換え類義 / 用法 |
| 文法 | 文法形式 / 文の組み立て / 文章の文法 |
| 読解 | 内容理解(短文) / 内容理解(中文) / 内容理解(長文) / 統合理解 / 主張理解 / 情報検索 |

子類別はフロント側で固定。後で追加する場合は `frontend/src/api.js` の `SUB_CATEGORIES` を更新。

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
   :5173                       :3000                     :5432
```

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

### 初回起動

```bash
cd /Users/kozen/work/project/japanese-mistakes
docker compose up -d
```

| サービス | URL | 用途 |
|---------|-----|------|
| Web   | http://localhost:5173 | アプリ画面 |
| API   | http://localhost:3000 | PostgREST（直叩き可） |
| DB    | localhost:55432       | psql 等で直接接続可（user: app / pass: app_pass / db: jp_mistakes）。ホスト側 5432 競合回避のため 55432 にマップ |

初回は `npm install` が走るため Web 立ち上がりに 1〜2 分かかる。ログ確認:

```bash
docker compose logs -f web
```

### 停止 / 再起動

```bash
docker compose stop          # 停止（データは残る）
docker compose start         # 再開
docker compose down          # コンテナ削除（DB ボリューム残る）
docker compose down -v       # ボリュームごと削除（DB 全消し）
```

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
├── db/
│   └── init.sql                # スキーマ・関数・権限
└── frontend/
    ├── package.json
    ├── vite.config.js          # /api → http://api:3000 にプロキシ
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

## 7. 既知の制約・拡張余地

- 認証なし。ローカル個人利用前提
- 聴解未対応（音声アップロード機能なし）
- バックアップは `docker compose exec db pg_dump -U app jp_mistakes > backup.sql` で手動
- 将来：間隔反復（SRS）、画像添付、CSV インポート/エクスポート、統計ダッシュボード等
