-- ============================================================
-- 0001_schema.sql  —— 错题库表结构(权威版)
-- 来源:从生产 docker 库 pg_dump --schema-only 导出。
-- ⚠ 列顺序严格对应 supabase/seed.sql 的位置型 INSERT,切勿调整列顺序,否则数据错位。
-- ============================================================

create table if not exists public.mistakes (
    id                integer     not null,
    category          text        not null,
    question          text        not null,
    option1           text,
    option2           text,
    option3           text,
    option4           text,
    correct_option    smallint,
    explanation       text,
    error_count       integer     not null default 1,
    last_wrong_at     timestamptz not null default now(),
    created_at        timestamptz not null default now(),
    underline_text    text,
    sub_category      text,
    last_practiced_at timestamptz,
    source_book       text,
    source_page       text,
    blanks            jsonb,
    option_underlines jsonb,
    constraint mistakes_category_check
        check (category in ('文字・語彙', '文法', '読解')),
    constraint mistakes_correct_option_check
        check (correct_option is null or (correct_option between 1 and 4)),
    constraint mistakes_format_check
        check (
            blanks is not null
            or (option1 is not null and option2 is not null
                and option3 is not null and option4 is not null
                and correct_option is not null)
        )
);

-- 主键序列(与生产库一致)
create sequence if not exists public.mistakes_id_seq
    as integer start with 1 increment by 1 no minvalue no maxvalue cache 1;
alter sequence public.mistakes_id_seq owned by public.mistakes.id;
alter table public.mistakes
    alter column id set default nextval('public.mistakes_id_seq'::regclass);

-- 主键(幂等)
do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'mistakes_pkey'
    ) then
        alter table public.mistakes add constraint mistakes_pkey primary key (id);
    end if;
end $$;

create index if not exists idx_mistakes_category       on public.mistakes (category);
create index if not exists idx_mistakes_error_count    on public.mistakes (error_count desc);
create index if not exists idx_mistakes_last_practiced on public.mistakes (last_practiced_at nulls first);
create index if not exists idx_mistakes_sub_category   on public.mistakes (sub_category);

-- 原子地把 error_count +1(供 PostgREST 以 /rpc/increment_error 调用)
-- set search_path = '' + 全限定名:符合 Supabase 函数安全最佳实践,避免 search_path 注入告警。
create or replace function public.increment_error(mistake_id integer)
returns public.mistakes
language sql
set search_path = ''
as $$
    update public.mistakes
       set error_count   = error_count + 1,
           last_wrong_at = now()
     where id = mistake_id
    returning *;
$$;
