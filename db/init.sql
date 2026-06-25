-- N1 错题记录数据库初始化脚本
-- PostgREST 通过 app 角色访问，因此需要将该角色的权限授予表

-- 1 題 = 4 択 1 答（option1-4 + correct_option）が基本形。
-- 文章の文法など 1 篇文章に複数空欄があるクローズ題は blanks JSONB で表現する。
-- blanks が NOT NULL のときは option1-4 / correct_option を NULL にできる。
CREATE TABLE IF NOT EXISTS mistakes (
  id              SERIAL PRIMARY KEY,
  category        TEXT NOT NULL CHECK (category IN ('文字・語彙', '文法', '読解')),
  sub_category    TEXT,
  question        TEXT NOT NULL,
  option1         TEXT,
  option2         TEXT,
  option3         TEXT,
  option4         TEXT,
  correct_option  SMALLINT CHECK (correct_option IS NULL OR correct_option BETWEEN 1 AND 4),
  blanks          JSONB,                 -- クローズ題用：[{n, options[4], correct, explanation?}, ...]
  option_underlines JSONB,                -- 用法など、各選択肢で下線を引く語の配列：[ul1, ul2, ul3, ul4]
  underline_text  TEXT,
  explanation     TEXT,
  source_book     TEXT,                  -- 教材名（例: "JLPT N1 この一冊で合格"）
  source_page     TEXT,                  -- ページ・問題番号（例: "78" / "問題7-41〜45"）
  error_count     INTEGER NOT NULL DEFAULT 1,
  last_wrong_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_practiced_at TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT mistakes_format_check CHECK (
    blanks IS NOT NULL
    OR (option1 IS NOT NULL AND option2 IS NOT NULL
        AND option3 IS NOT NULL AND option4 IS NOT NULL
        AND correct_option IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_mistakes_category ON mistakes(category);
CREATE INDEX IF NOT EXISTS idx_mistakes_sub_category ON mistakes(sub_category);
CREATE INDEX IF NOT EXISTS idx_mistakes_error_count ON mistakes(error_count DESC);
CREATE INDEX IF NOT EXISTS idx_mistakes_last_practiced ON mistakes(last_practiced_at NULLS FIRST);

-- PostgREST 需要一个 RPC 方便地原子性地 +1 错误次数
CREATE OR REPLACE FUNCTION increment_error(mistake_id INTEGER)
RETURNS mistakes
LANGUAGE sql
AS $$
  UPDATE mistakes
     SET error_count = error_count + 1,
         last_wrong_at = NOW()
   WHERE id = mistake_id
  RETURNING *;
$$;

-- 授权（app 角色已由 docker-compose 的 POSTGRES_USER 创建并自动登录）
GRANT USAGE ON SCHEMA public TO app;
GRANT SELECT, INSERT, UPDATE, DELETE ON mistakes TO app;
GRANT USAGE, SELECT ON SEQUENCE mistakes_id_seq TO app;
GRANT EXECUTE ON FUNCTION increment_error(INTEGER) TO app;

-- ============================================================
-- 真題模試：套题 / 读解共享文章 / 有序题目（云端权威版见 supabase/migrations/0003_papers.sql）
-- paper_questions 列与 mistakes 同构，交卷后做错的题可直拷投影进 mistakes。
-- ============================================================
CREATE TABLE IF NOT EXISTS papers (
  id            SERIAL PRIMARY KEY,
  name          TEXT NOT NULL UNIQUE,          -- 去重键，例: "JLPT N1 2010年7月 真題"
  level         TEXT NOT NULL DEFAULT 'N1' CHECK (level IN ('N1','N2','N3','N4','N5')),
  exam_year     SMALLINT,
  exam_session  TEXT,
  source_book   TEXT,
  total_minutes SMALLINT,
  note          TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_papers_level ON papers(level);

CREATE TABLE IF NOT EXISTS paper_passages (
  id            SERIAL PRIMARY KEY,
  paper_id      INTEGER NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
  ref           TEXT NOT NULL,                 -- 套题内本地引用键，questions 用 passage_ref 指向
  sub_category  TEXT NOT NULL,
  title         TEXT,
  body          TEXT NOT NULL,
  body_b        TEXT,                          -- 統合理解 A/B 的 B 文
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT paper_passages_ref_uniq UNIQUE (paper_id, ref)
);
CREATE INDEX IF NOT EXISTS idx_passages_paper ON paper_passages(paper_id);

CREATE TABLE IF NOT EXISTS paper_questions (
  id                SERIAL PRIMARY KEY,
  paper_id          INTEGER NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
  passage_id        INTEGER REFERENCES paper_passages(id) ON DELETE CASCADE,
  seq               INTEGER NOT NULL,
  section           SMALLINT NOT NULL,         -- 大問番号 問題1〜13
  category          TEXT NOT NULL CHECK (category IN ('文字・語彙', '文法', '読解')),
  sub_category      TEXT NOT NULL,
  question          TEXT NOT NULL,
  option1           TEXT,
  option2           TEXT,
  option3           TEXT,
  option4           TEXT,
  correct_option    SMALLINT CHECK (correct_option IS NULL OR correct_option BETWEEN 1 AND 4),
  blanks            JSONB,
  option_underlines JSONB,
  underline_text    TEXT,
  explanation       TEXT,
  points            SMALLINT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT paper_questions_seq_uniq UNIQUE (paper_id, seq),
  CONSTRAINT paper_questions_format_check CHECK (
    blanks IS NOT NULL
    OR (option1 IS NOT NULL AND option2 IS NOT NULL
        AND option3 IS NOT NULL AND option4 IS NOT NULL
        AND correct_option IS NOT NULL)
  ),
  CONSTRAINT paper_questions_passage_check CHECK (
    (category = '読解' AND passage_id IS NOT NULL)
    OR (category <> '読解' AND passage_id IS NULL)
  )
);
CREATE INDEX IF NOT EXISTS idx_pq_paper_seq ON paper_questions(paper_id, seq);
CREATE INDEX IF NOT EXISTS idx_pq_passage   ON paper_questions(passage_id);
CREATE INDEX IF NOT EXISTS idx_pq_section   ON paper_questions(paper_id, section);

GRANT SELECT, INSERT, UPDATE, DELETE ON papers          TO app;
GRANT SELECT, INSERT, UPDATE, DELETE ON paper_passages  TO app;
GRANT SELECT, INSERT, UPDATE, DELETE ON paper_questions TO app;
GRANT USAGE, SELECT ON SEQUENCE papers_id_seq          TO app;
GRANT USAGE, SELECT ON SEQUENCE paper_passages_id_seq  TO app;
GRANT USAGE, SELECT ON SEQUENCE paper_questions_id_seq TO app;
