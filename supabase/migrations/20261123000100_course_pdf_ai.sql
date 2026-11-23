alter table public.sessions
  add column if not exists pdf_path text;

create table if not exists public.course_summaries (
  session_id uuid primary key references public.sessions (id) on delete cascade,
  summary text not null,
  source_pdf_path text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.course_summaries enable row level security;

drop policy if exists "Summaries readable by authenticated" on public.course_summaries;
create policy "Summaries readable by authenticated"
  on public.course_summaries for select to authenticated
  using (
    exists (select 1 from public.sessions s where s.id = session_id)
  );

drop policy if exists "Teachers and directors refresh summaries" on public.course_summaries;
create policy "Teachers and directors refresh summaries"
  on public.course_summaries for delete to authenticated
  using (
    public.current_app_role() = 'director'
    or exists (
      select 1 from public.sessions s
      where s.id = session_id and s.teacher_id = auth.uid()
    )
  );

grant select, delete on public.course_summaries to authenticated;

insert into storage.buckets (id, name, public)
values ('course_pdfs', 'course_pdfs', false)
on conflict (id) do nothing;

drop policy if exists "Course PDFs readable by authenticated" on storage.objects;
create policy "Course PDFs readable by authenticated"
  on storage.objects for select to authenticated
  using (bucket_id = 'course_pdfs');

drop policy if exists "Teachers and directors upload course PDFs" on storage.objects;
create policy "Teachers and directors upload course PDFs"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'course_pdfs'
    and public.current_app_role() in ('teacher', 'director')
  );

drop policy if exists "Teachers and directors replace course PDFs" on storage.objects;
create policy "Teachers and directors replace course PDFs"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'course_pdfs'
    and public.current_app_role() in ('teacher', 'director')
  )
  with check (
    bucket_id = 'course_pdfs'
    and public.current_app_role() in ('teacher', 'director')
  );
