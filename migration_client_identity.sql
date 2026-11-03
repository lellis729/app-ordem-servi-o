-- Execute in the Supabase SQL Editor for an existing installation.
alter table public.clients add column if not exists client_number integer;

with numbered as (
  select id, row_number() over (partition by company_id order by created_at, id) as number
  from public.clients where client_number is null
)
update public.clients c set client_number=numbered.number from numbered where c.id=numbered.id;

create unique index if not exists clients_company_number_unique on public.clients(company_id,client_number);
create index if not exists clients_company_document_digits_idx
  on public.clients(company_id,(regexp_replace(coalesce(document,''),'\D','','g')));

create or replace function public.guard_client_identity() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_document text; v_duplicate record; v_next integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(new.company_id::text,0));
  v_document=regexp_replace(coalesce(new.document,''),'\D','','g');
  if v_document<>'' then
    select id,client_number,name into v_duplicate from public.clients
    where company_id=new.company_id and id is distinct from new.id
      and regexp_replace(coalesce(document,''),'\D','','g')=v_document limit 1;
    if found then
      raise exception 'CLIENT_ALREADY_EXISTS|%|%',v_duplicate.client_number,v_duplicate.name using errcode='23505';
    end if;
  end if;
  if tg_op='INSERT' and new.client_number is null then
    select coalesce(max(client_number),0)+1 into v_next from public.clients where company_id=new.company_id;
    new.client_number=v_next;
  end if;
  return new;
end $$;

drop trigger if exists clients_identity_guard on public.clients;
create trigger clients_identity_guard before insert or update of document on public.clients
  for each row execute function public.guard_client_identity();
