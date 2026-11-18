-- 享尼網站留言板：在 Supabase 的 SQL Editor 貼上整段後按 Run
create table if not exists public.messages (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  name       text not null default '匿名' check (char_length(name) between 1 and 30),
  message    text not null check (char_length(message) between 1 and 500),
  is_public  boolean not null default true
);

alter table public.messages enable row level security;

-- 任何訪客都可以留言（但不能把留言設成隱藏以外的狀態，也不能修改或刪除）
drop policy if exists "anyone can post" on public.messages;
create policy "anyone can post" on public.messages
  for insert to anon with check (is_public = true);

-- 任何訪客都只能讀到「公開」的留言
drop policy if exists "anyone can read public" on public.messages;
create policy "anyone can read public" on public.messages
  for select to anon using (is_public);

grant select (name, message, created_at, is_public), insert (name, message) on public.messages to anon;
