-- 享尼網站義賣系統（商品、庫存、訂單）
-- 使用方式：在 Supabase 的 SQL Editor 貼上整段後按 Run。可重複執行，不會清掉既有訂單。

-- ========== 1. 商店設定（只有一列） ==========
create table if not exists public.shop_settings (
  id                 int primary key default 1 check (id = 1),
  orders_open        boolean not null default true,     -- 關掉就暫停線上下單
  shipping_fee       int not null default 120 check (shipping_fee >= 0),  -- 宅配運費
  free_shipping_over int check (free_shipping_over > 0), -- 滿額免運（留空 = 不免運）
  pay_days           int not null default 3 check (pay_days between 1 and 14), -- 幾天內要匯款
  bank_name          text,  -- 例如：中華郵政
  bank_code          text,  -- 例如：700
  bank_account       text,  -- 帳號
  account_name       text   -- 戶名
);
insert into public.shop_settings (id) values (1) on conflict (id) do nothing;

-- ========== 2. 商品與庫存 ==========
create table if not exists public.products (
  sku    text primary key,                -- 對應網站上的商品代號，請勿修改
  name   text not null,
  price  int  not null check (price > 0),
  stock  int  check (stock >= 0),         -- 庫存；留空 = 不限量
  active boolean not null default true,   -- false = 網站上不能線上下單
  sort   int  not null default 0
);
insert into public.products (sku, name, price, active, sort) values
  ('si_apparel0:0', '享尼排汗短袖T恤', 400, true, 0),
  ('si_apparel1:0', '享尼棉質短袖T恤', 400, true, 1),
  ('si_bags0:0', '帆布袋（薄）', 100, true, 2),
  ('si_bags0:1', '帆布袋（厚）', 300, true, 3),
  ('si_bags1:0', '側背包', 600, true, 4),
  ('si_bags2:0', '方形包（小）', 250, true, 5),
  ('si_bags2:1', '方形包（大）', 350, true, 6),
  ('si_bags3:0', '筆袋', 300, true, 7),
  ('si_bags4:0', '化妝包', 400, true, 8),
  ('si_bags5:0', '旅行化妝包', 350, true, 9),
  ('si_bags6:0', '零錢包', 150, true, 10),
  ('si_craft0:0', '羊毛氈（小）', 150, true, 11),
  ('si_craft0:1', '羊毛氈（中）', 250, true, 12),
  ('si_craft1:0', '頌缽（小）', 500, true, 13),
  ('si_craft1:1', '頌缽（大）', 750, true, 14),
  ('si_craft2:0', '刀（小）', 400, false, 15),
  ('si_craft2:1', '刀（大）', 550, false, 16),
  ('si_acc0:0', '絲巾', 200, true, 17),
  ('si_acc1:0', '圍巾', 750, true, 18),
  ('si_acc2:0', '眼罩', 100, true, 19),
  ('si_stat0:0', '明信片', 80, true, 20),
  ('si_stat1:0', '便利貼', 50, true, 21),
  ('si_stat2:0', '資料夾', 80, true, 22),
  ('si_stat3:0', '風景圖', 150, true, 23),
  ('si_stat4:0', '護唇膏', 80, true, 24)
on conflict (sku) do nothing;

-- ========== 3. 滿額回饋級距（沿用捐款級距） ==========
create table if not exists public.reward_tiers (
  amount int primary key check (amount > 0),
  perks  text not null
);
insert into public.reward_tiers (amount, perks) values
  (500,  '電子感謝狀＋尼泊爾孩童插畫明信片'),
  (2000, '紙本獎狀＋主商品一件（厚帆布袋／享尼團服／小羊毛氈）＋小物一件（明信片／便利貼）')
on conflict (amount) do nothing;

-- ========== 4. 訂單 ==========
create sequence if not exists public.order_seq;
create table if not exists public.orders (
  id            uuid primary key default gen_random_uuid(),
  order_no      text unique not null,
  created_at    timestamptz not null default now(),
  status        text not null default '待付款'
                check (status in ('待付款','已回報匯款','已付款','已出貨','已完成','已取消')),
  buyer_name    text not null,
  phone         text not null,
  email         text not null,
  zip           text,
  address       text not null,
  note          text,
  items         jsonb not null,           -- [{sku,name,price,qty}]
  subtotal      int not null,
  shipping      int not null,
  total         int not null,
  reward_amount int,                       -- 達到的回饋級距（NT$）
  reward_perks  text,
  reward_choice text,                      -- 買家選的回饋品
  sizes         text,                      -- 服飾尺寸（例如 M×1、L×2）
  pay_by        timestamptz,               -- 匯款期限
  transfer_last5 text,
  transfer_reported_at timestamptz,
  tracking_no   text,                      -- 出貨後填物流單號
  admin_note    text                       -- 團隊內部備註
);
alter table public.orders add column if not exists sizes text;
create index if not exists orders_created_idx on public.orders (created_at desc);
create index if not exists orders_phone_idx on public.orders (phone, created_at desc);

-- ========== 5. 權限：訪客只能讀商品與設定，不能直接讀寫訂單 ==========
alter table public.shop_settings enable row level security;
alter table public.products      enable row level security;
alter table public.reward_tiers  enable row level security;
alter table public.orders        enable row level security;

drop policy if exists "read settings" on public.shop_settings;
create policy "read settings" on public.shop_settings for select to anon using (true);
drop policy if exists "read products" on public.products;
create policy "read products" on public.products for select to anon using (true);
drop policy if exists "read tiers" on public.reward_tiers;
create policy "read tiers" on public.reward_tiers for select to anon using (true);
-- orders：不建立任何 anon 規則 = 訪客完全讀不到、改不了訂單

revoke all on public.orders from anon, authenticated;
grant select on public.shop_settings, public.products, public.reward_tiers to anon;

-- ========== 6. 下單（價格、庫存、運費、回饋都由資料庫計算，網頁無法竄改） ==========
create or replace function public.place_order(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s        shop_settings;
  it       jsonb;
  pr       products;
  lines    jsonb := '[]'::jsonb;
  qtys     jsonb := '{}'::jsonb;
  k        text;
  q        int;
  sub      int := 0;
  ship     int;
  tier     reward_tiers;
  v_name   text := btrim(coalesce(p->>'name',''));
  v_phone  text := regexp_replace(coalesce(p->>'phone',''), '[^0-9]', '', 'g');
  v_email  text := lower(btrim(coalesce(p->>'email','')));
  v_zip    text := left(btrim(coalesce(p->>'zip','')), 6);
  v_addr   text := btrim(coalesce(p->>'address',''));
  v_note   text := left(btrim(coalesce(p->>'note','')), 300);
  v_choice text := left(btrim(coalesce(p->>'reward_choice','')), 100);
  v_sizes  text := left(btrim(coalesce(p->>'sizes','')), 100);
  needs_size boolean := false;
  v_no     text;
  v_pay_by timestamptz;
begin
  select * into s from shop_settings where id = 1;
  if not s.orders_open then raise exception 'ORDERS_CLOSED'; end if;

  if char_length(v_name) not between 1 and 40 then raise exception 'BAD_NAME'; end if;
  if v_phone !~ '^09[0-9]{8}$' then raise exception 'BAD_PHONE'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 120 then raise exception 'BAD_EMAIL'; end if;
  if char_length(v_addr) not between 6 and 200 then raise exception 'BAD_ADDRESS'; end if;
  if (p->>'agree') is distinct from 'true' then raise exception 'NO_CONSENT'; end if;

  -- 同一支手機 24 小時內最多 3 筆未付款訂單，避免惡意佔庫存
  if (select count(*) from orders where phone = v_phone and status = '待付款'
        and created_at > now() - interval '24 hours') >= 3 then
    raise exception 'TOO_MANY_ORDERS';
  end if;

  if jsonb_typeof(p->'items') <> 'array' or jsonb_array_length(p->'items') not between 1 and 30 then
    raise exception 'BAD_ITEMS';
  end if;
  for it in select * from jsonb_array_elements(p->'items') loop
    k := it->>'sku';
    q := (it->>'qty')::int;
    if k is null or q is null or q < 1 or q > 99 then raise exception 'BAD_ITEMS'; end if;
    qtys := jsonb_set(qtys, array[k], to_jsonb(coalesce((qtys->>k)::int, 0) + q));
  end loop;

  for k, q in select key, value::int from jsonb_each_text(qtys) order by key loop
    select * into pr from products where sku = k for update;
    if not found or not pr.active then raise exception 'UNAVAILABLE:%', k; end if;
    if pr.stock is not null and pr.stock < q then raise exception 'OUT_OF_STOCK:%:%', k, pr.stock; end if;
    if q > 99 then raise exception 'BAD_ITEMS'; end if;
    update products set stock = stock - q where sku = k and stock is not null;
    if k like 'si_apparel%' then needs_size := true; end if;
    sub := sub + pr.price * q;
    lines := lines || jsonb_build_object('sku', pr.sku, 'name', pr.name, 'price', pr.price, 'qty', q);
  end loop;

  if needs_size and v_sizes = '' then raise exception 'NEED_SIZES'; end if;

  ship := case when s.free_shipping_over is not null and sub >= s.free_shipping_over then 0 else s.shipping_fee end;
  select * into tier from reward_tiers where amount <= sub order by amount desc limit 1;
  v_no := 'SN' || to_char(now() at time zone 'Asia/Taipei', 'YYMMDD') || '-' || lpad((nextval('order_seq') % 100000)::text, 5, '0');
  -- 匯款期限：下單日起算 pay_days 天，當天 23:59（台灣時間）
  v_pay_by := (date_trunc('day', now() at time zone 'Asia/Taipei') + make_interval(days => s.pay_days + 1)) at time zone 'Asia/Taipei';

  insert into orders (order_no, buyer_name, phone, email, zip, address, note, items, subtotal, shipping, total,
                      reward_amount, reward_perks, reward_choice, sizes, pay_by)
  values (v_no, v_name, v_phone, v_email, nullif(v_zip,''), v_addr, nullif(v_note,''), lines, sub, ship, sub + ship,
          tier.amount, tier.perks, case when tier.amount is null then null else nullif(v_choice,'') end,
          case when needs_size then v_sizes end, v_pay_by);

  return jsonb_build_object(
    'order_no', v_no, 'items', lines, 'subtotal', sub, 'shipping', ship, 'total', sub + ship,
    'reward_amount', tier.amount, 'reward_perks', tier.perks, 'pay_by', v_pay_by,
    'bank', jsonb_build_object('name', s.bank_name, 'code', s.bank_code, 'account', s.bank_account, 'holder', s.account_name));
end;
$$;

-- ========== 7. 訂單查詢（需訂單編號＋手機，不回傳地址等個資） ==========
create or replace function public.get_order(p_order_no text, p_phone text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'order_no', o.order_no, 'created_at', o.created_at, 'status', o.status, 'items', o.items,
    'subtotal', o.subtotal, 'shipping', o.shipping, 'total', o.total,
    'reward_amount', o.reward_amount, 'reward_perks', o.reward_perks, 'reward_choice', o.reward_choice, 'sizes', o.sizes,
    'pay_by', o.pay_by, 'transfer_reported', o.transfer_reported_at is not null, 'tracking_no', o.tracking_no,
    'bank', jsonb_build_object('name', s.bank_name, 'code', s.bank_code, 'account', s.bank_account, 'holder', s.account_name))
  from orders o cross join shop_settings s
  where o.order_no = upper(btrim(p_order_no))
    and o.phone = regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g')
    and s.id = 1;
$$;

-- ========== 8. 回報匯款（帳號末五碼） ==========
create or replace function public.report_transfer(p_order_no text, p_phone text, p_last5 text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare n int;
begin
  if coalesce(p_last5,'') !~ '^[0-9]{5}$' then raise exception 'BAD_LAST5'; end if;
  update orders set transfer_last5 = p_last5, transfer_reported_at = now(), status = '已回報匯款'
   where order_no = upper(btrim(p_order_no))
     and phone = regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g')
     and status in ('待付款','已回報匯款');
  get diagnostics n = row_count;
  if n = 0 then raise exception 'NOT_FOUND'; end if;
  return '已回報匯款';
end;
$$;

revoke all on function public.place_order(jsonb) from public;
revoke all on function public.get_order(text, text) from public;
revoke all on function public.report_transfer(text, text, text) from public;
grant execute on function public.place_order(jsonb) to anon;
grant execute on function public.get_order(text, text) to anon;
grant execute on function public.report_transfer(text, text, text) to anon;

-- ========== 9. 訂單改成「已取消」時，自動把庫存加回去 ==========
create or replace function public.restock_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare it jsonb;
begin
  if new.status = '已取消' and old.status <> '已取消' then
    for it in select * from jsonb_array_elements(old.items) loop
      update products set stock = stock + (it->>'qty')::int where sku = it->>'sku' and stock is not null;
    end loop;
  elsif old.status = '已取消' and new.status <> '已取消' then
    for it in select * from jsonb_array_elements(old.items) loop
      update products set stock = greatest(stock - (it->>'qty')::int, 0) where sku = it->>'sku' and stock is not null;
    end loop;
  end if;
  return new;
end;
$$;
drop trigger if exists orders_restock on public.orders;
create trigger orders_restock after update of status on public.orders
  for each row execute function public.restock_on_cancel();
