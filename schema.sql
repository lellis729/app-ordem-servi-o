-- Execute once in Supabase SQL Editor. After creating the first Auth user, follow README.md to provision its profile.
create extension if not exists pgcrypto;
create type public.app_role as enum ('admin','attendant','technician');
create type public.order_status as enum ('open','diagnosis','waiting_approval','waiting_parts','in_progress','done','delivered','cancelled');
create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null,
  full_name text not null default '', role public.app_role not null default 'attendant',
  created_at timestamptz not null default now()
);
create index profiles_company_idx on public.profiles(company_id);
create or replace function public.current_company_id() returns uuid language sql stable security definer set search_path=public as $$ select company_id from public.profiles where user_id=auth.uid() $$;
create or replace function public.has_role(allowed public.app_role[]) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.profiles where user_id=auth.uid() and role=any(allowed)) $$;
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;

create table public.clients (
 id uuid primary key default gen_random_uuid(), company_id uuid not null default public.current_company_id(), name text not null,
 document text, phone text, whatsapp text, email text, zip_code text, address text, city text, state text, notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.equipment (
 id uuid primary key default gen_random_uuid(), company_id uuid not null default public.current_company_id(), client_id uuid not null references public.clients(id) on delete restrict,
 equipment_type text not null, brand text, model text, serial_number text, manufacture_year integer, color text, notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.service_orders (
 id uuid primary key default gen_random_uuid(), company_id uuid not null default public.current_company_id(),
 order_number bigint generated always as identity (start with 1001) unique, client_id uuid not null references public.clients(id) on delete restrict,
 equipment_id uuid not null references public.equipment(id) on delete restrict, entry_at timestamptz not null default now(), due_date date,
 status public.order_status not null default 'open', reported_issue text, condition_notes text, diagnosis text, service_description text,
 parts_description text, technician text, labor_cost numeric(12,2) not null default 0 check(labor_cost>=0), parts_cost numeric(12,2) not null default 0 check(parts_cost>=0),
 discount numeric(12,2) not null default 0 check(discount>=0), total numeric(12,2) not null default 0 check(total>=0), payment_method text,
 notes text, created_by uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.order_status_history (
 id uuid primary key default gen_random_uuid(), company_id uuid not null default public.current_company_id(), order_id uuid not null references public.service_orders(id) on delete cascade,
 status public.order_status not null, changed_by uuid references auth.users(id), changed_at timestamptz not null default now(), notes text
);
create table public.parts (
 id uuid primary key default gen_random_uuid(), company_id uuid not null default public.current_company_id(), name text not null, code text,
 quantity integer not null default 0 check(quantity>=0), minimum_stock integer not null default 0 check(minimum_stock>=0),
 cost_price numeric(12,2) not null default 0, sale_price numeric(12,2) not null default 0,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(company_id,code)
);
create table public.stock_movements (
 id uuid primary key default gen_random_uuid(), company_id uuid not null default public.current_company_id(), part_id uuid not null references public.parts(id) on delete restrict,
 quantity integer not null check(quantity>0), movement_type text not null check(movement_type in ('entry','exit','service_use')),
 service_order_id uuid references public.service_orders(id), notes text, created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table public.order_parts (
 id uuid primary key default gen_random_uuid(), company_id uuid not null default public.current_company_id(), order_id uuid not null references public.service_orders(id) on delete cascade,
 part_id uuid not null references public.parts(id) on delete restrict, quantity integer not null check(quantity>0), unit_price numeric(12,2) not null default 0
);
create index clients_company_name_idx on public.clients(company_id,name);
create index orders_company_date_idx on public.service_orders(company_id,created_at desc);
create index orders_client_idx on public.service_orders(client_id);
create index equipment_serial_idx on public.equipment(company_id,serial_number);

-- Atomic stock movement. Raises an error when an exit would result in negative inventory.
create or replace function public.move_stock(p_part_id uuid,p_quantity integer,p_movement_type text,p_notes text default null)
returns void language plpgsql security invoker set search_path=public as $$
declare v_company uuid; v_current integer; v_delta integer;
begin
 if p_quantity<=0 or p_movement_type not in ('entry','exit') then raise exception 'Movimento inválido'; end if;
 select company_id,quantity into v_company,v_current from public.parts where id=p_part_id for update;
 if not found or v_company<>public.current_company_id() then raise exception 'Peça não encontrada'; end if;
 v_delta:=case when p_movement_type='entry' then p_quantity else -p_quantity end;
 if v_current+v_delta<0 then raise exception 'Estoque insuficiente'; end if;
 update public.parts set quantity=quantity+v_delta,updated_at=now() where id=p_part_id;
 insert into public.stock_movements(company_id,part_id,quantity,movement_type,notes,created_by)
 values(v_company,p_part_id,p_quantity,p_movement_type,p_notes,auth.uid());
end $$;

-- Append a status event for every status change, including changes made outside the web client.
create or replace function public.log_order_status() returns trigger language plpgsql security definer set search_path=public as $$
begin if tg_op='INSERT' or new.status is distinct from old.status then
 insert into public.order_status_history(company_id,order_id,status,changed_by) values(new.company_id,new.id,new.status,auth.uid()); end if; return new; end $$;
create trigger service_order_status_log after insert or update of status on public.service_orders for each row execute function public.log_order_status();
create trigger clients_touch before update on public.clients for each row execute function public.touch_updated_at();
create trigger equipment_touch before update on public.equipment for each row execute function public.touch_updated_at();
create trigger orders_touch before update on public.service_orders for each row execute function public.touch_updated_at();
create trigger parts_touch before update on public.parts for each row execute function public.touch_updated_at();

alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.equipment enable row level security;
alter table public.service_orders enable row level security;
alter table public.order_status_history enable row level security;
alter table public.parts enable row level security;
alter table public.stock_movements enable row level security;
alter table public.order_parts enable row level security;

create policy "profiles same company read" on public.profiles for select to authenticated using(company_id=public.current_company_id());
create policy "profiles admins manage" on public.profiles for all to authenticated using(company_id=public.current_company_id() and public.has_role(array['admin']::public.app_role[])) with check(company_id=public.current_company_id() and public.has_role(array['admin']::public.app_role[]));
create policy "clients company read" on public.clients for select to authenticated using(company_id=public.current_company_id());
create policy "clients staff write" on public.clients for all to authenticated using(company_id=public.current_company_id() and public.has_role(array['admin','attendant']::public.app_role[])) with check(company_id=public.current_company_id() and public.has_role(array['admin','attendant']::public.app_role[]));
create policy "equipment company read" on public.equipment for select to authenticated using(company_id=public.current_company_id());
create policy "equipment staff write" on public.equipment for all to authenticated using(company_id=public.current_company_id() and public.has_role(array['admin','attendant']::public.app_role[])) with check(company_id=public.current_company_id() and public.has_role(array['admin','attendant']::public.app_role[]));
create policy "orders company read" on public.service_orders for select to authenticated using(company_id=public.current_company_id());
create policy "orders staff insert" on public.service_orders for insert to authenticated with check(company_id=public.current_company_id() and public.has_role(array['admin','attendant']::public.app_role[]));
create policy "orders staff update" on public.service_orders for update to authenticated using(company_id=public.current_company_id() and public.has_role(array['admin','attendant','technician']::public.app_role[])) with check(company_id=public.current_company_id() and public.has_role(array['admin','attendant','technician']::public.app_role[]));
create policy "orders admins delete" on public.service_orders for delete to authenticated using(company_id=public.current_company_id() and public.has_role(array['admin']::public.app_role[]));
create policy "history company read" on public.order_status_history for select to authenticated using(company_id=public.current_company_id());
create policy "history company insert" on public.order_status_history for insert to authenticated with check(company_id=public.current_company_id());
create policy "parts company read" on public.parts for select to authenticated using(company_id=public.current_company_id());
create policy "parts staff write" on public.parts for all to authenticated using(company_id=public.current_company_id() and public.has_role(array['admin','attendant']::public.app_role[])) with check(company_id=public.current_company_id() and public.has_role(array['admin','attendant']::public.app_role[]));
create policy "movements company read" on public.stock_movements for select to authenticated using(company_id=public.current_company_id());
create policy "movements staff write" on public.stock_movements for insert to authenticated with check(company_id=public.current_company_id() and public.has_role(array['admin','attendant']::public.app_role[]));
create policy "order parts company read" on public.order_parts for select to authenticated using(company_id=public.current_company_id());
create policy "order parts staff write" on public.order_parts for all to authenticated using(company_id=public.current_company_id() and public.has_role(array['admin','attendant']::public.app_role[])) with check(company_id=public.current_company_id() and public.has_role(array['admin','attendant']::public.app_role[]));
grant usage on schema public to authenticated;
grant select,insert,update,delete on public.profiles,public.clients,public.equipment,public.service_orders,public.order_status_history,public.parts,public.stock_movements,public.order_parts to authenticated;
grant usage,select on all sequences in schema public to authenticated;
grant execute on function public.move_stock(uuid,integer,text,text) to authenticated;
