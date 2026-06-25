-- ============================================================
-- 0003_papers.sql  —— 真題模試:套题 / 读解共享文章 / 有序题目
-- 设计:与 mistakes 解耦的「真题题库 + 试卷结构」。
--   paper_questions 的列刻意与 mistakes 同名同义，交卷后做错的题
--   可几乎直拷投影进 mistakes（见前端 archiveWrong）。
-- 应用顺序：在 0001/0002 之后。应用后执行末尾的 notify pgrst。
-- ============================================================

-- 1) papers：一套真题的元信息（一次考试 = 一行）
create table if not exists public.papers (
    id            integer     not null,
    name          text        not null,        -- 去重键，例: "JLPT N1 2010年7月 真題"
    level         text        not null default 'N1',
    exam_year     smallint,                     -- 2010
    exam_session  text,                         -- "7月" / "12月"
    source_book   text,                         -- 来源标注，写回 mistakes.source_book 用
    total_minutes smallint,                     -- 言語知識・読解の制限時間（分）
    note          text,
    created_at    timestamptz not null default now(),
    constraint papers_level_check check (level in ('N1','N2','N3','N4','N5')),
    constraint papers_name_uniq   unique (name)
);

create sequence if not exists public.papers_id_seq
    as integer start with 1 increment by 1 no minvalue no maxvalue cache 1;
alter sequence public.papers_id_seq owned by public.papers.id;
alter table public.papers
    alter column id set default nextval('public.papers_id_seq'::regclass);

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'papers_pkey') then
        alter table public.papers add constraint papers_pkey primary key (id);
    end if;
end $$;

create index if not exists idx_papers_level on public.papers (level);

-- 2) paper_passages：読解の共有文章（1篇 : N小問）。非読解の大問は持たない。
create table if not exists public.paper_passages (
    id           integer     not null,
    paper_id     integer     not null,
    ref          text        not null,          -- パッケージ内ローカル参照キー（JSON内で問題が指す）例: "p10a"
    sub_category text        not null,          -- 読解の小分類（内容理解（長文）等）
    title        text,                          -- 文章タイトル（任意）
    body         text        not null,          -- 本文（情報検索なら表組みテキスト）
    body_b       text,                          -- 統合理解 A/B 比較の B 文（任意）
    created_at   timestamptz not null default now(),
    constraint paper_passages_paper_fk
        foreign key (paper_id) references public.papers(id) on delete cascade,
    constraint paper_passages_ref_uniq unique (paper_id, ref)
);

create sequence if not exists public.paper_passages_id_seq
    as integer start with 1 increment by 1 no minvalue no maxvalue cache 1;
alter sequence public.paper_passages_id_seq owned by public.paper_passages.id;
alter table public.paper_passages
    alter column id set default nextval('public.paper_passages_id_seq'::regclass);

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'paper_passages_pkey') then
        alter table public.paper_passages add constraint paper_passages_pkey primary key (id);
    end if;
end $$;

create index if not exists idx_passages_paper on public.paper_passages (paper_id);

-- 3) paper_questions：有序の題目（単選 / cloze / 読解小問を統一格納）
--    構造は mistakes と意図的に揃える（option1-4 / correct_option / blanks / underline 系）。
create table if not exists public.paper_questions (
    id                integer     not null,
    paper_id          integer     not null,
    passage_id        integer,                  -- 読解のみ非NULL
    seq               integer     not null,     -- 套題内の通し出題順（1始まり）
    section           smallint    not null,     -- 大問番号 問題1〜13
    category          text        not null,
    sub_category      text        not null,
    question          text        not null,
    option1           text,
    option2           text,
    option3           text,
    option4           text,
    correct_option    smallint,
    blanks            jsonb,                    -- cloze 題（文章の文法）用、mistakes と同一形式
    option_underlines jsonb,
    underline_text    text,
    explanation       text,
    points            smallint,                 -- 配点（任意、採点用）
    created_at        timestamptz not null default now(),
    constraint paper_questions_paper_fk
        foreign key (paper_id) references public.papers(id) on delete cascade,
    constraint paper_questions_passage_fk
        foreign key (passage_id) references public.paper_passages(id) on delete cascade,
    constraint paper_questions_seq_uniq unique (paper_id, seq),
    constraint paper_questions_category_check
        check (category in ('文字・語彙', '文法', '読解')),
    constraint paper_questions_correct_option_check
        check (correct_option is null or (correct_option between 1 and 4)),
    -- mistakes と同じ「4択 or blanks」整合性
    constraint paper_questions_format_check
        check (
            blanks is not null
            or (option1 is not null and option2 is not null
                and option3 is not null and option4 is not null
                and correct_option is not null)
        ),
    -- 読解は passage 必須、それ以外は passage を持たない
    constraint paper_questions_passage_check
        check (
            (category = '読解' and passage_id is not null)
            or (category <> '読解' and passage_id is null)
        )
);

create sequence if not exists public.paper_questions_id_seq
    as integer start with 1 increment by 1 no minvalue no maxvalue cache 1;
alter sequence public.paper_questions_id_seq owned by public.paper_questions.id;
alter table public.paper_questions
    alter column id set default nextval('public.paper_questions_id_seq'::regclass);

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'paper_questions_pkey') then
        alter table public.paper_questions add constraint paper_questions_pkey primary key (id);
    end if;
end $$;

create index if not exists idx_pq_paper_seq on public.paper_questions (paper_id, seq);
create index if not exists idx_pq_passage   on public.paper_questions (passage_id);
create index if not exists idx_pq_section   on public.paper_questions (paper_id, section);

-- ============================================================
-- RLS + GRANT（与 0002 同模式：全开放，anon 可读写）
-- ⚠ 安全级别：低。与现有 mistakes 一致，仅适合自用。
-- ============================================================
alter table public.papers          enable row level security;
alter table public.paper_passages  enable row level security;
alter table public.paper_questions enable row level security;

drop policy if exists "public full access" on public.papers;
create policy "public full access" on public.papers
    for all to anon, authenticated using (true) with check (true);

drop policy if exists "public full access" on public.paper_passages;
create policy "public full access" on public.paper_passages
    for all to anon, authenticated using (true) with check (true);

drop policy if exists "public full access" on public.paper_questions;
create policy "public full access" on public.paper_questions
    for all to anon, authenticated using (true) with check (true);

grant select, insert, update, delete on public.papers          to anon, authenticated;
grant select, insert, update, delete on public.paper_passages  to anon, authenticated;
grant select, insert, update, delete on public.paper_questions to anon, authenticated;
grant usage, select on sequence public.papers_id_seq          to anon, authenticated;
grant usage, select on sequence public.paper_passages_id_seq  to anon, authenticated;
grant usage, select on sequence public.paper_questions_id_seq to anon, authenticated;

-- PostgREST schema 缓存刷新（新表/列不刷新会 404）
notify pgrst, 'reload schema';
