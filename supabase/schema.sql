create extension if not exists "pgcrypto";

create table if not exists public.applicants (
  id uuid primary key default gen_random_uuid(),
  new_number integer unique not null,
  full_name text not null,
  phone text,
  mobile text,
  national_id text,
  birth_date date,
  main_category text not null,
  sub_category text not null,
  specialty_text text,
  approved_specialty text not null,
  specialty_review_status text,
  graduation_university text,
  graduation_year integer,
  original_paper text,
  source_sheet text,
  source_row integer,
  issue_flags text,
  application_status text not null default 'جديد',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.applicant_files (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid not null references public.applicants(id) on delete cascade,
  file_type text not null default 'cv',
  file_name text not null,
  file_path text not null,
  uploaded_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.applicant_notes (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid not null references public.applicants(id) on delete cascade,
  note text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists applicants_set_updated_at on public.applicants;
create trigger applicants_set_updated_at
before update on public.applicants
for each row
execute function public.set_updated_at();

alter table public.applicants enable row level security;
alter table public.applicant_files enable row level security;
alter table public.applicant_notes enable row level security;

drop policy if exists "Authenticated users can read applicants" on public.applicants;
create policy "Authenticated users can read applicants"
on public.applicants for select
to authenticated
using (true);

drop policy if exists "Authenticated users can update applicants" on public.applicants;
create policy "Authenticated users can update applicants"
on public.applicants for update
to authenticated
using (true)
with check (true);

drop policy if exists "Authenticated users can insert applicants" on public.applicants;
create policy "Authenticated users can insert applicants"
on public.applicants for insert
to authenticated
with check (true);

drop policy if exists "Authenticated users can read files" on public.applicant_files;
create policy "Authenticated users can read files"
on public.applicant_files for select
to authenticated
using (true);

drop policy if exists "Authenticated users can manage files" on public.applicant_files;
create policy "Authenticated users can manage files"
on public.applicant_files for all
to authenticated
using (true)
with check (true);

drop policy if exists "Authenticated users can read notes" on public.applicant_notes;
create policy "Authenticated users can read notes"
on public.applicant_notes for select
to authenticated
using (true);

drop policy if exists "Authenticated users can manage notes" on public.applicant_notes;
create policy "Authenticated users can manage notes"
on public.applicant_notes for all
to authenticated
using (true)
with check (true);

create index if not exists applicants_main_category_idx on public.applicants(main_category);
create index if not exists applicants_sub_category_idx on public.applicants(sub_category);
create index if not exists applicants_approved_specialty_idx on public.applicants(approved_specialty);
create index if not exists applicants_full_name_idx on public.applicants(full_name);
create index if not exists applicants_application_status_idx on public.applicants(application_status);

insert into storage.buckets (id, name, public)
values ('applicant-files', 'applicant-files', false)
on conflict (id) do nothing;

drop policy if exists "Authenticated users can read applicant files" on storage.objects;
create policy "Authenticated users can read applicant files"
on storage.objects for select
to authenticated
using (bucket_id = 'applicant-files');

drop policy if exists "Authenticated users can upload applicant files" on storage.objects;
create policy "Authenticated users can upload applicant files"
on storage.objects for insert
to authenticated
with check (bucket_id = 'applicant-files');
