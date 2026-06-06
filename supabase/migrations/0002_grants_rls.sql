-- ============================================================
-- 0002_grants_rls.sql  —— 权限模型:全开放(anon 可读写)
-- ⚠ 安全级别:低。anon key 随前端公开,任何持有者都能增删改数据。
--    仅适合"先跑起来 / 自己用"。加固方案见 DEPLOY.md 第 5 节。
-- ============================================================

-- 开启 RLS 后用全放行 policy(比关闭 RLS 更规范,后续收紧只需改 policy)
alter table public.mistakes enable row level security;

drop policy if exists "public full access" on public.mistakes;
create policy "public full access"
    on public.mistakes
    for all
    to anon, authenticated
    using (true)
    with check (true);

-- 表 / 序列 / 函数 授权(PostgREST 需要 GRANT 与 RLS policy 双重放行)
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.mistakes to anon, authenticated;
grant usage, select on sequence public.mistakes_id_seq to anon, authenticated;
grant execute on function public.increment_error(integer) to anon, authenticated;
