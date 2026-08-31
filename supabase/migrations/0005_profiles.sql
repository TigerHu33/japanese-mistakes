-- ============================================================
-- 0005_profiles.sql —— ユーザー名ログイン対応
-- Supabase Auth は email/phone しか受け付けないため、実際の認証には
-- 「username@AUTH_EMAIL_DOMAIN」という合成メールアドレスを使う(ユーザーには非公開)。
-- 本物のメールアドレスは任意入力の連絡先として profiles.contact_email に保存するのみで、
-- ログイン・確認メール・パスワードリセットには一切使わない。
-- ⚠ 適用前提:Dashboard で Authentication → Providers → Email → "Confirm email" を OFF にすること。
--   合成メールは実在しないので、確認メールが届かず ON のままだと誰もログインできなくなる。
-- ============================================================

create table if not exists public.profiles (
    id            uuid        not null references auth.users(id) on delete cascade,
    username      text        not null,
    contact_email text,
    created_at    timestamptz not null default now(),
    constraint profiles_pkey primary key (id),
    constraint profiles_username_uniq unique (username)
);

-- auth.users に新規行ができたら raw_user_meta_data から username/contact_email を写す
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.profiles (id, username, contact_email)
    values (
        new.id,
        new.raw_user_meta_data ->> 'username',
        new.raw_user_meta_data ->> 'contact_email'
    );
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;

drop policy if exists "read own profile" on public.profiles;
create policy "read own profile"
    on public.profiles
    for select
    to authenticated
    using (id = auth.uid());

grant select on public.profiles to authenticated;

notify pgrst, 'reload schema';
