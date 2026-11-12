-- Initial schema for the single-store ordering app.
-- Run once against a new Supabase project.
-- Preserve Mongo ObjectIds as legacy_id text during any future data import.

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.menu_items (
  id uuid primary key default gen_random_uuid(),
  legacy_id text unique,
  sid integer not null,
  item_type text not null,
  menu_row text not null,
  category_id uuid references public.categories(id) on delete set null,
  name text not null,
  display_name text not null,
  description text,
  price integer not null check (price >= 0),
  image_url text,
  is_available boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  legacy_id text unique,
  table_number text,
  order_source text
    check (order_source in ('WEB_QR', 'POS_APP', 'UBER', 'LEGACY')),
  status text
    check (status in ('PENDING', 'PREPARING', 'COMPLETED', 'CANCELLED')),
  takeout boolean not null,
  serial integer not null,
  total_price integer not null check (total_price >= 0),
  get_pay integer not null,
  sauerkraut boolean not null default false,
  ginger boolean not null default false,
  chili boolean not null default false,
  order_date timestamptz not null default now(),
  uber boolean not null default false,
  mark text,
  created_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  legacy_id text unique,
  order_id uuid not null references public.orders(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id) on delete set null,
  sid integer not null,
  item_type text not null,
  item_name text not null,
  display_name text not null,
  quantity integer check (quantity is null or quantity > 0),
  unit_price integer not null check (unit_price >= 0),
  options jsonb not null default '{}'::jsonb
    check (jsonb_typeof(options) = 'object')
);

-- Only users explicitly registered here can read orders in the merchant app.
create table public.merchant_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'STAFF' check (role in ('OWNER', 'STAFF')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index menu_items_category_id_idx
  on public.menu_items(category_id);
create index menu_items_sid_idx
  on public.menu_items(sid);
create index orders_order_date_idx
  on public.orders(order_date desc);
create index orders_status_created_at_idx
  on public.orders(status, order_date desc);
create index order_items_order_id_idx
  on public.order_items(order_id);
create index order_items_sid_idx
  on public.order_items(sid);

comment on column public.menu_items.is_available is
  'When importing the old menu, set this to NOT disabled.';
comment on column public.menu_items.sid is
  'Legacy sid value; no uniqueness or foreign-key meaning is assumed.';
comment on column public.orders.status is
  'May be NULL for legacy orders when the old system did not store a status.';
comment on column public.orders.order_source is
  'May be NULL for legacy orders when the source is unknown.';
comment on column public.order_items.sid is
  'Legacy sid value; no foreign-key meaning is assumed.';

alter table public.categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.merchant_users enable row level security;

grant usage on schema public to anon, authenticated;
grant select on public.categories, public.menu_items to anon, authenticated;
grant select on public.orders, public.order_items, public.merchant_users
  to authenticated;

create policy "Anyone can read active categories"
  on public.categories
  for select
  to anon, authenticated
  using (is_active);

create policy "Anyone can read available menu items"
  on public.menu_items
  for select
  to anon, authenticated
  using (
    is_available
    and (
      category_id is null
      or exists (
        select 1
        from public.categories as category
        where category.id = menu_items.category_id
          and category.is_active
      )
    )
  );

create policy "Merchant users can read their own membership"
  on public.merchant_users
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy "Active merchants can read orders"
  on public.orders
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.merchant_users as merchant
      where merchant.user_id = (select auth.uid())
        and merchant.is_active
    )
  );

create policy "Active merchants can read order items"
  on public.order_items
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.orders as order_record
      where order_record.id = order_items.order_id
    )
  );

-- Run once: add the orders table to Supabase Realtime.
alter publication supabase_realtime add table public.orders;