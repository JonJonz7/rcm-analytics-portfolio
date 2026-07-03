-- ---------------------------------------------------------------------------
-- RCM Analytics Demo — database schema (PostgreSQL / Supabase)
--
-- DEMO ONLY. This schema is a generic illustration of a multi-tenant
-- claims-analytics data model with row-level security. It is not a
-- production schema and contains no product-specific analytical logic.
-- ---------------------------------------------------------------------------

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Tenancy
-- ---------------------------------------------------------------------------

create table organizations (
    org_id      uuid primary key default gen_random_uuid(),
    org_name    text not null,
    created_at  timestamptz not null default now()
);

create table app_users (
    user_id     uuid primary key,          -- mirrors auth.users.id in Supabase
    org_id      uuid not null references organizations (org_id) on delete cascade,
    email       text not null unique,
    user_role   text not null default 'viewer'
                check (user_role in ('admin', 'analyst', 'viewer')),
    created_at  timestamptz not null default now()
);

create index idx_app_users_org on app_users (org_id);

-- ---------------------------------------------------------------------------
-- Claims data (synthetic in this demo — see seed_synthetic.sql)
-- ---------------------------------------------------------------------------

create table claim_records (
    record_id        bigint generated always as identity primary key,
    org_id           uuid not null references organizations (org_id) on delete cascade,
    external_ref     text not null,        -- caller-supplied claim reference
    service_date     date not null,
    procedure_code   text not null,
    insurer_name     text not null,
    charge_amount    numeric(12, 2) not null check (charge_amount >= 0),
    remit_amount     numeric(12, 2) not null default 0 check (remit_amount >= 0),
    record_status    text not null
                     check (record_status in ('paid', 'denied', 'pending')),
    adjustment_code  text,                 -- generic remark code, nullable
    decision_date    date,
    created_at       timestamptz not null default now(),
    unique (org_id, external_ref)
);

create index idx_claim_records_org_date on claim_records (org_id, service_date);
create index idx_claim_records_org_status on claim_records (org_id, record_status);

-- ---------------------------------------------------------------------------
-- Saved analysis output (opaque JSON payload per run)
-- ---------------------------------------------------------------------------

create table report_runs (
    run_id           uuid primary key default gen_random_uuid(),
    org_id           uuid not null references organizations (org_id) on delete cascade,
    run_at           timestamptz not null default now(),
    summary_payload  jsonb not null default '{}'::jsonb
);

create index idx_report_runs_org on report_runs (org_id, run_at desc);

-- ---------------------------------------------------------------------------
-- Row-level security
--
-- Pattern: every tenant-scoped table is locked down by default; members of an
-- organization may read their own organization's rows; writes to analytical
-- output go through the service role only (no write policy is defined for
-- authenticated users, so writes are denied by default).
-- ---------------------------------------------------------------------------

alter table organizations enable row level security;
alter table app_users     enable row level security;
alter table claim_records enable row level security;
alter table report_runs   enable row level security;

-- Helper: the set of org_ids the current authenticated user belongs to.
create or replace function current_user_org_ids()
returns setof uuid
language sql
security definer
stable
as $$
    select org_id from app_users where user_id = auth.uid();
$$;

create policy org_member_read_organizations
    on organizations for select
    to authenticated
    using (org_id in (select current_user_org_ids()));

create policy user_read_own_profile
    on app_users for select
    to authenticated
    using (user_id = auth.uid());

create policy org_member_read_claims
    on claim_records for select
    to authenticated
    using (org_id in (select current_user_org_ids()));

create policy org_admin_write_claims
    on claim_records for insert
    to authenticated
    with check (
        org_id in (
            select org_id from app_users
            where user_id = auth.uid() and user_role in ('admin', 'analyst')
        )
    );

create policy org_member_read_runs
    on report_runs for select
    to authenticated
    using (org_id in (select current_user_org_ids()));

-- report_runs writes: service role only (bypasses RLS); no user write policy.
