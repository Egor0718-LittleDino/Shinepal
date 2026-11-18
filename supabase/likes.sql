-- 享尼網站留言板：按讚功能（在 Supabase 的 SQL Editor 貼上整段後按 Run，執行一次即可）
alter table public.messages
  add column if not exists likes integer not null default 0 check (likes >= 0);

-- 讓網站讀得到每則留言的編號與讚數
grant select (id, likes) on public.messages to anon;

-- 按讚 / 收回讚：只能 +1 或 -1，只對公開留言有效，訪客無法直接修改其他欄位
create or replace function public.like_message(mid bigint, delta integer default 1)
returns integer
language sql
security definer
set search_path = public
as $$
  update public.messages
     set likes = greatest(likes + case when delta > 0 then 1 else -1 end, 0)
   where id = mid and is_public
  returning likes;
$$;

revoke all on function public.like_message(bigint, integer) from public;
grant execute on function public.like_message(bigint, integer) to anon;
