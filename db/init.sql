-- N1 错题记录数据库初始化脚本
-- PostgREST 通过 app 角色访问，因此需要将该角色的权限授予表

CREATE TABLE IF NOT EXISTS mistakes (
  id              SERIAL PRIMARY KEY,
  category        TEXT NOT NULL CHECK (category IN ('文字・語彙', '文法', '読解')),
  sub_category    TEXT,
  question        TEXT NOT NULL,
  option1         TEXT NOT NULL,
  option2         TEXT NOT NULL,
  option3         TEXT NOT NULL,
  option4         TEXT NOT NULL,
  correct_option  SMALLINT NOT NULL CHECK (correct_option BETWEEN 1 AND 4),
  underline_text  TEXT,
  explanation     TEXT,
  source_book     TEXT,                  -- 教材名（例: "JLPT N1 この一冊で合格"）
  source_page     TEXT,                  -- ページ（例: "78"）
  error_count     INTEGER NOT NULL DEFAULT 1,
  last_wrong_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_practiced_at TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
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
