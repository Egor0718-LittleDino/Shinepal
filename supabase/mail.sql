-- 享尼義賣：訂單 Email 通知（在 Supabase 的 SQL Editor 貼上整段後按 Run，執行一次即可）
-- 有新訂單、買家回報匯款、狀態改成已付款／已出貨／已取消時，呼叫 Google Apps Script 寄信。

create extension if not exists pg_net with schema extensions;

-- 寄信網址存在 private schema，網站訪客讀不到
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.mail_hook (
  id  int primary key default 1 check (id = 1),
  url text
);

create or replace function private.set_mail_hook(u text)
returns text language sql security definer set search_path = private as $$
  insert into private.mail_hook (id, url) values (1, u)
  on conflict (id) do update set url = excluded.url
  returning '設定完成';
$$;
revoke all on function private.set_mail_hook(text) from public, anon, authenticated;

create or replace function private.notify_order()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  u  text;
  s  public.shop_settings;
  ev text;
begin
  select url into u from private.mail_hook where id = 1;
  if u is null or u = '' then return new; end if;

  if tg_op = 'INSERT' then
    ev := 'new';
  elsif new.status = '已出貨' and new.tracking_no is not null and new.tracking_no <> ''
        and (old.status <> '已出貨' or old.tracking_no is null or old.tracking_no = '') then
    ev := '已出貨';   -- 已出貨＋有物流單號才寄（兩個欄位先改哪個都可以）
  elsif new.status is distinct from old.status and new.status in ('已回報匯款','已付款','已取消') then
    ev := new.status;
  elsif new.status = '已回報匯款' and new.transfer_last5 is distinct from old.transfer_last5 then
    ev := '已回報匯款';   -- 買家更正末五碼
  else
    return new;
  end if;

  select * into s from public.shop_settings where id = 1;
  perform net.http_post(
    url     := u,
    body    := jsonb_build_object(
                 'event', ev,
                 'order', to_jsonb(new),
                 'bank',  jsonb_build_object('name', s.bank_name, 'code', s.bank_code,
                                             'account', s.bank_account, 'holder', s.account_name)),
    headers := '{"Content-Type": "application/json"}'::jsonb
  );
  return new;
exception when others then
  return new;   -- 寄信失敗不能影響下單
end;
$$;
revoke all on function private.notify_order() from public, anon, authenticated;

drop trigger if exists orders_mail on public.orders;
create trigger orders_mail after insert or update on public.orders
  for each row execute function private.notify_order();
