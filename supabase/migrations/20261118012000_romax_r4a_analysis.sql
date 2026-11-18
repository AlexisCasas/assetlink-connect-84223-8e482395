-- ROMAX R4-A: technical analysis of a commercial opportunity.
-- Deliberately excludes monetary fields. Economics remain in R2/R4-C.
create table if not exists public.romax_opportunity_analyses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  opportunity_id uuid not null references public.romax_opportunities(id) on delete cascade,
  version_number integer not null,
  status text not null default 'draft',
  source_type text not null default 'manual',
  model_name text,
  requested_service text,
  scope_of_work text,
  missing_information jsonb not null default '[]'::jsonb,
  technical_considerations jsonb not null default '[]'::jsonb,
  risks jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint romax_opportunity_analyses_status_chk
    check (status in ('draft','ready_for_review','superseded')),
  constraint romax_opportunity_analyses_source_chk
    check (source_type in ('manual','ai')),
  constraint romax_opportunity_analyses_version_chk
    check (version_number > 0),
  constraint romax_opportunity_analyses_json_arrays_chk
    check (
      jsonb_typeof(missing_information) = 'array'
      and jsonb_typeof(technical_considerations) = 'array'
      and jsonb_typeof(risks) = 'array'
    ),
  constraint romax_opportunity_analyses_version_uidx
    unique (opportunity_id, version_number)
);

create table if not exists public.romax_opportunity_analysis_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  analysis_id uuid not null references public.romax_opportunity_analyses(id) on delete cascade,
  item_type text not null,
  description text not null,
  quantity numeric,
  unit_code text,
  technical_specification text,
  source_reference jsonb,
  confidence numeric(5,4),
  suggested_cost_item_id uuid references public.provider_cost_items(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint romax_opportunity_analysis_items_type_chk
    check (item_type in ('service','material','equipment','labor','mobilization','other')),
  constraint romax_opportunity_analysis_items_qty_chk
    check (quantity is null or quantity >= 0),
  constraint romax_opportunity_analysis_items_confidence_chk
    check (confidence is null or (confidence >= 0 and confidence <= 1))
);

create index if not exists romax_opportunity_analyses_opportunity_idx
  on public.romax_opportunity_analyses (organization_id, opportunity_id, version_number desc);

create index if not exists romax_opportunity_analysis_items_analysis_idx
  on public.romax_opportunity_analysis_items (organization_id, analysis_id, item_type);

create index if not exists romax_opportunity_analysis_items_cost_item_idx
  on public.romax_opportunity_analysis_items (organization_id, suggested_cost_item_id)
  where suggested_cost_item_id is not null;

create or replace function public.validate_romax_analysis_links()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.romax_opportunities o
    where o.id = new.opportunity_id
      and o.organization_id = new.organization_id
  ) then
    raise exception 'Analysis and opportunity must belong to the same organization';
  end if;

  if new.created_by is not null
     and not exists (
       select 1
       from public.organization_members m
       where m.organization_id = new.organization_id
         and m.user_id = new.created_by
         and m.is_active
     ) then
    raise exception 'Analysis creator must be an active organization member';
  end if;

  return new;
end;
$$;

drop trigger if exists romax_opportunity_analyses_validate_links on public.romax_opportunity_analyses;
create trigger romax_opportunity_analyses_validate_links
before insert or update on public.romax_opportunity_analyses
for each row execute function public.validate_romax_analysis_links();

create or replace function public.validate_romax_analysis_item_links()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.romax_opportunity_analyses a
    where a.id = new.analysis_id
      and a.organization_id = new.organization_id
  ) then
    raise exception 'Analysis item and analysis must belong to the same organization';
  end if;

  if new.suggested_cost_item_id is not null
     and not exists (
       select 1
       from public.provider_cost_items i
       where i.id = new.suggested_cost_item_id
         and i.organization_id = new.organization_id
     ) then
    raise exception 'Suggested cost resource does not belong to the analysis organization';
  end if;

  return new;
end;
$$;

drop trigger if exists romax_opportunity_analysis_items_validate_links on public.romax_opportunity_analysis_items;
create trigger romax_opportunity_analysis_items_validate_links
before insert or update on public.romax_opportunity_analysis_items
for each row execute function public.validate_romax_analysis_item_links();

drop trigger if exists romax_opportunity_analyses_set_updated_at on public.romax_opportunity_analyses;
create trigger romax_opportunity_analyses_set_updated_at
before update on public.romax_opportunity_analyses
for each row execute function public.romax_set_updated_at();

drop trigger if exists romax_opportunity_analysis_items_set_updated_at on public.romax_opportunity_analysis_items;
create trigger romax_opportunity_analysis_items_set_updated_at
before update on public.romax_opportunity_analysis_items
for each row execute function public.romax_set_updated_at();

alter table public.romax_opportunity_analyses enable row level security;
alter table public.romax_opportunity_analysis_items enable row level security;

drop policy if exists romax_opportunity_analyses_read on public.romax_opportunity_analyses;
create policy romax_opportunity_analyses_read
on public.romax_opportunity_analyses
for select to authenticated
using (public.is_organization_member(organization_id));

drop policy if exists romax_opportunity_analyses_insert on public.romax_opportunity_analyses;
create policy romax_opportunity_analyses_insert
on public.romax_opportunity_analyses
for insert to authenticated
with check (
  public.has_organization_role(
    organization_id,
    array['owner','admin','manager','quote_manager']::public.organization_member_role[]
  )
  and (created_by is null or created_by = auth.uid())
);

drop policy if exists romax_opportunity_analyses_update on public.romax_opportunity_analyses;
create policy romax_opportunity_analyses_update
on public.romax_opportunity_analyses
for update to authenticated
using (
  public.has_organization_role(
    organization_id,
    array['owner','admin','manager','quote_manager']::public.organization_member_role[]
  )
)
with check (
  public.has_organization_role(
    organization_id,
    array['owner','admin','manager','quote_manager']::public.organization_member_role[]
  )
);

drop policy if exists romax_opportunity_analyses_delete on public.romax_opportunity_analyses;
create policy romax_opportunity_analyses_delete
on public.romax_opportunity_analyses
for delete to authenticated
using (
  public.has_organization_role(
    organization_id,
    array['owner','admin','manager','quote_manager']::public.organization_member_role[]
  )
);

drop policy if exists romax_opportunity_analysis_items_read on public.romax_opportunity_analysis_items;
create policy romax_opportunity_analysis_items_read
on public.romax_opportunity_analysis_items
for select to authenticated
using (public.is_organization_member(organization_id));

drop policy if exists romax_opportunity_analysis_items_insert on public.romax_opportunity_analysis_items;
create policy romax_opportunity_analysis_items_insert
on public.romax_opportunity_analysis_items
for insert to authenticated
with check (
  public.has_organization_role(
    organization_id,
    array['owner','admin','manager','quote_manager']::public.organization_member_role[]
  )
);

drop policy if exists romax_opportunity_analysis_items_update on public.romax_opportunity_analysis_items;
create policy romax_opportunity_analysis_items_update
on public.romax_opportunity_analysis_items
for update to authenticated
using (
  public.has_organization_role(
    organization_id,
    array['owner','admin','manager','quote_manager']::public.organization_member_role[]
  )
)
with check (
  public.has_organization_role(
    organization_id,
    array['owner','admin','manager','quote_manager']::public.organization_member_role[]
  )
);

drop policy if exists romax_opportunity_analysis_items_delete on public.romax_opportunity_analysis_items;
create policy romax_opportunity_analysis_items_delete
on public.romax_opportunity_analysis_items
for delete to authenticated
using (
  public.has_organization_role(
    organization_id,
    array['owner','admin','manager','quote_manager']::public.organization_member_role[]
  )
);
