-- ============================================================
-- 0004_auth.sql —— 引入 Supabase Auth，mistakes 按 user_id 隔离
-- 套题库（papers/paper_passages/paper_questions）保持全体登录用户共享，不隔离。
-- ⚠ 分步执行：本文件跑完后 mistakes.user_id 仍允许为 NULL（兼容存量数据），
--    待「现有数据回填」章节（见 DEPLOY.md）跑完再手动 SET NOT NULL。
-- ============================================================

-- 1) mistakes 加 user_id，默认取当前登录用户，方便前端 INSERT 时无需显式传参
alter table public.mistakes
    add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.mistakes
    alter column user_id set default auth.uid();

create index if not exists idx_mistakes_user_id on public.mistakes (user_id);

-- 2) mistakes：收回 anon 权限，authenticated 仅能读写自己的行
drop policy if exists "public full access" on public.mistakes;

create policy "own rows only"
    on public.mistakes
    for all
    to authenticated
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

revoke select, insert, update, delete on public.mistakes from anon;
revoke usage, select on sequence public.mistakes_id_seq from anon;
revoke execute on function public.increment_error(integer) from anon;

-- 3) 套题库：只登录不隔离——去掉 anon，authenticated 全表可见（保留原 for all，模试导入脚本仍走这条）
drop policy if exists "public full access" on public.papers;
create policy "authenticated full access" on public.papers
    for all to authenticated using (true) with check (true);

drop policy if exists "public full access" on public.paper_passages;
create policy "authenticated full access" on public.paper_passages
    for all to authenticated using (true) with check (true);

drop policy if exists "public full access" on public.paper_questions;
create policy "authenticated full access" on public.paper_questions
    for all to authenticated using (true) with check (true);

revoke select, insert, update, delete on public.papers          from anon;
revoke select, insert, update, delete on public.paper_passages  from anon;
revoke select, insert, update, delete on public.paper_questions from anon;
revoke usage, select on sequence public.papers_id_seq          from anon;
revoke usage, select on sequence public.paper_passages_id_seq  from anon;
revoke usage, select on sequence public.paper_questions_id_seq from anon;

notify pgrst, 'reload schema';
