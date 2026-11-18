-- ROMAX R3: oportunidades comerciales y adjuntos.
-- Gmail todavía no se conecta; esta migración prepara el modelo y sus barreras de tenant.
create table if not exists public.romax_opportunities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  status text not null default 'new',
  classification text not null default 'unknown',
  classification_confidence numeric(5,4),
  classification_reason text,
  commercial_client_id uuid references public.commercial_clients(id) on delete set null,
  commercial_site_id uuid references public.commercial_client_sites(id) on delete set null,
  commercial_contact_id uuid references public.commercial_client_contacts(id) on delete set null,
  match_status text not null default 'unmatched',
  match_notes text,
  suggested_match jsonb,
  subject text,
  sender_email text,
  received_at timestamptz,
  snippet text,
  source_system text not null default 'manual',
  source_message_id text,
  source_thread_id text,
  created_by uuid references auth.users(id) on delete set null,
  internal_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint romax_opportunities_status_chk
    check (status in ('new','reviewing','ready_for_analysis','in_analysis','quoted','discarded')),
  constraint romax_opportunities_classification_chk
    check (classification in ('quote_request','follow_up','information_only','other','unknown')),
  constraint romax_opportunities_confidence_chk
    check (classification_confidence is null or (classification_confidence >= 0 and classification_confidence <= 1)),
  constraint romax_opportunities_match_status_chk
    check (match_status in ('unmatched','suggested','confirmed','ambiguous')),
  constraint romax_opportunities_source_chk
    check (source_system in ('manual','gmail')),
  constraint romax_opportunities_gmail_ids_chk
    check (
      source_system <> 'gmail'
      or (source_message_id is not null and source_thread_id is not null)
    )
);

create table if not exists public.romax_opportunity_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  opportunity_id uuid not null references public.romax_opportunities(id) on delete cascade,
  source_system text not null default 'manual',
  source_message_id text,
  source_attachment_id text,
  filename text not null,
  mime_type text,
  size_bytes bigint,
  storage_path text,
  checksum_sha256 text,
  processing_status text not null default 'detected',
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint romax_opportunity_attachments_source_chk
    check (source_system in ('manual','gmail')),
  constraint romax_opportunity_attachments_status_chk
    check (processing_status in ('detected','queued','downloaded','processed','unsupported','failed')),
  constraint romax_opportunity_attachments_size_chk
    check (size_bytes is null or size_bytes >= 0),
  constraint romax_opportunity_attachments_gmail_ids_chk
    check (
      source_system <> 'gmail'
      or (source_message_id is not null and source_attachment_id is not null)
    )
);

create unique index if not exists romax_opportunities_gmail_message_uidx
  on public.romax_opportunities (organization_id, source_message_id)
  where source_system = 'gmail' and source_message_id is not null;

create unique index if not exists romax_opportunities_gmail_thread_uidx
  on public.romax_opportunities (organization_id, source_thread_id)
  where source_system = 'gmail' and source_thread_id is not null;

create unique index if not exists romax_opportunity_attachments_gmail_uidx
  on public.romax_opportunity_attachments (organization_id, source_attachment_id)
  where source_system = 'gmail' and source_attachment_id is not null;

create index if not exists romax_opportunities_org_status_idx
  on public.romax_opportunities (organization_id, status, received_at desc);

create index if not exists romax_opportunities_org_classification_idx
  on public.romax_opportunities (organization_id, classification, received_at desc);

create index if not exists romax_opportunity_attachments_opportunity_idx
  on public.romax_opportunity_attachments (organization_id, opportunity_id, created_at);

create or replace function public.romax_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists romax_opportunities_set_updated_at on public.romax_opportunities;
create trigger romax_opportunities_set_updated_at
before update on public.romax_opportunities
for each row execute function public.romax_set_updated_at();

drop trigger if exists romax_opportunity_attachments_set_updated_at on public.romax_opportunity_attachments;
create trigger romax_opportunity_attachments_set_updated_at
before update on public.romax_opportunity_attachments
for each row execute function public.romax_set_updated_at();

create or replace function public.validate_romax_opportunity_links()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.organizations o
    where o.id = new.organization_id
      and o.organization_type = 'provider_company'::public.organization_type
      and o.status = 'active'
  ) then
    raise exception 'ROMAX opportunity requires an active provider organization';
  end if;

  if new.commercial_client_id is not null and not exists (
    select 1 from public.commercial_clients c
    where c.id = new.commercial_client_id
      and c.organization_id = new.organization_id
  ) then
    raise exception 'Commercial client does not belong to the opportunity organization';
  end if;

  if new.commercial_site_id is not null and not exists (
    select 1 from public.commercial_client_sites s
    where s.id = new.commercial_site_id
      and s.organization_id = new.organization_id
      and (new.commercial_client_id is null or s.commercial_client_id = new.commercial_client_id)
  ) then
    raise exception 'Commercial site does not belong to the opportunity client/organization';
  end if;

  if new.commercial_contact_id is not null and not exists (
    select 1 from public.commercial_client_contacts c
    where c.id = new.commercial_contact_id
      and c.organization_id = new.organization_id
      and (new.commercial_client_id is null or c.commercial_client_id = new.commercial_client_id)
  ) then
    raise exception 'Commercial contact does not belong to the opportunity client/organization';
  end if;

  return new;
end;
$$;

drop trigger if exists romax_opportunities_validate_links on public.romax_opportunities;
create trigger romax_opportunities_validate_links
before insert or update on public.romax_opportunities
for each row execute function public.validate_romax_opportunity_links();

create or replace function public.validate_romax_opportunity_attachment_org()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.romax_opportunities o
    where o.id = new.opportunity_id
      and o.organization_id = new.organization_id
  ) then
    raise exception 'Attachment and opportunity must belong to the same organization';
  end if;
  return new;
end;
$$;

drop trigger if exists romax_opportunity_attachments_validate_org on public.romax_opportunity_attachments;
create trigger romax_opportunity_attachments_validate_org
before insert or update on public.romax_opportunity_attachments
for each row execute function public.validate_romax_opportunity_attachment_org();

alter table public.romax_opportunities enable row level security;
alter table public.romax_opportunity_attachments enable row level security;

drop policy if exists romax_opportunities_read on public.romax_opportunities;
create policy romax_opportunities_read
on public.romax_opportunities
for select to authenticated
using (public.is_organization_member(organization_id));

drop policy if exists romax_opportunities_insert on public.romax_opportunities;
create policy romax_opportunities_insert
on public.romax_opportunities
for insert to authenticated
with check (
  public.has_organization_role(
    organization_id,
    array['owner','admin','manager','quote_manager']::public.organization_member_role[]
  )
  and (created_by is null or created_by = auth.uid())
);

drop policy if exists romax_opportunities_update on public.romax_opportunities;
create policy romax_opportunities_update
on public.romax_opportunities
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

drop policy if exists romax_opportunities_delete on public.romax_opportunities;
create policy romax_opportunities_delete
on public.romax_opportunities
for delete to authenticated
using (
  public.has_organization_role(
    organization_id,
    array['owner','admin','manager','quote_manager']::public.organization_member_role[]
  )
);

drop policy if exists romax_opportunity_attachments_read on public.romax_opportunity_attachments;
create policy romax_opportunity_attachments_read
on public.romax_opportunity_attachments
for select to authenticated
using (public.is_organization_member(organization_id));

drop policy if exists romax_opportunity_attachments_insert on public.romax_opportunity_attachments;
create policy romax_opportunity_attachments_insert
on public.romax_opportunity_attachments
for insert to authenticated
with check (
  public.has_organization_role(
    organization_id,
    array['owner','admin','manager','quote_manager']::public.organization_member_role[]
  )
);

drop policy if exists romax_opportunity_attachments_update on public.romax_opportunity_attachments;
create policy romax_opportunity_attachments_update
on public.romax_opportunity_attachments
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

drop policy if exists romax_opportunity_attachments_delete on public.romax_opportunity_attachments;
create policy romax_opportunity_attachments_delete
on public.romax_opportunity_attachments
for delete to authenticated
using (
  public.has_organization_role(
    organization_id,
    array['owner','admin','manager','quote_manager']::public.organization_member_role[]
  )
);
