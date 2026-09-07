alter table public.applicants
add column if not exists application_status text not null default 'جديد';

alter table public.applicants
add column if not exists notes text;

alter table public.applicants
add column if not exists updated_at timestamptz not null default now();

create table if not exists public.applicant_files (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid not null references public.applicants(id) on delete cascade,
  file_type text not null default 'cv',
  file_name text not null,
  file_path text not null,
  uploaded_by uuid references auth.users(id),
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
