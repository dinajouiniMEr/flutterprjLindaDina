create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default 'Utilisateur',
  role text not null default 'student'
    check (role in ('student', 'teacher', 'director')),
  class_name text,
  created_at timestamptz not null default now()
);

create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.current_class_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select class_name from public.profiles where id = auth.uid()
$$;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), 'Utilisateur')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.create_profile_for_new_user();

create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  course_name text not null,
  course_code text not null default '',
  teacher_name text not null default 'Enseignant',
  teacher_id uuid references public.profiles (id) on delete set null,
  class_name text not null,
  room text not null default 'Salle à confirmer',
  starts_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id) on delete cascade,
  student_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'declared_present'
    check (status in (
      'declared_present', 'declared_absent', 'present', 'absent', 'late'
    )),
  marked_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (session_id, student_id)
);

create table public.claims (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id) on delete cascade,
  student_id uuid not null references public.profiles (id) on delete cascade,
  course_name text not null,
  reason text not null,
  details text not null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  resolved_by uuid references public.profiles (id) on delete set null,
  resolution text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  entity_type text not null,
  entity_id uuid not null,
  action text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  actor_id uuid references public.profiles (id) on delete set null,
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.log_attendance_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.audit_logs (
      entity_type, entity_id, action, actor_id, new_values
    )
    values (tg_table_name, new.id, tg_op, auth.uid(), to_jsonb(new));
    return new;
  elsif tg_op = 'UPDATE' then
    insert into public.audit_logs (
      entity_type, entity_id, action, actor_id, old_values, new_values
    )
    values (
      tg_table_name, new.id, tg_op, auth.uid(), to_jsonb(old), to_jsonb(new)
    );
    return new;
  else
    insert into public.audit_logs (
      entity_type, entity_id, action, actor_id, old_values
    )
    values (tg_table_name, old.id, tg_op, auth.uid(), to_jsonb(old));
    return old;
  end if;
end;
$$;

create trigger audit_attendance_records
  after insert or update or delete on public.attendance_records
  for each row execute procedure public.log_attendance_change();

create trigger audit_claims
  after insert or update or delete on public.claims
  for each row execute procedure public.log_attendance_change();

alter table public.profiles enable row level security;
alter table public.sessions enable row level security;
alter table public.attendance_records enable row level security;
alter table public.claims enable row level security;
alter table public.audit_logs enable row level security;

create policy "Profiles are visible to their owner and directors"
  on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or public.current_app_role() = 'director'
    or (
      public.current_app_role() = 'teacher'
      and exists (
        select 1 from public.sessions s
        where s.teacher_id = auth.uid()
          and s.class_name = profiles.class_name
      )
    )
  );

create policy "Users see sessions for their role"
  on public.sessions for select to authenticated
  using (
    public.current_app_role() = 'director'
    or (public.current_app_role() = 'teacher' and teacher_id = auth.uid())
    or (
      public.current_app_role() = 'student'
      and class_name = public.current_class_name()
    )
  );

create policy "Teachers and directors manage sessions"
  on public.sessions for insert to authenticated
  with check (
    public.current_app_role() = 'director'
    or (public.current_app_role() = 'teacher' and teacher_id = auth.uid())
  );

create policy "Teachers and directors update sessions"
  on public.sessions for update to authenticated
  using (
    public.current_app_role() = 'director'
    or (public.current_app_role() = 'teacher' and teacher_id = auth.uid())
  )
  with check (
    public.current_app_role() = 'director'
    or (public.current_app_role() = 'teacher' and teacher_id = auth.uid())
  );

create policy "Users see relevant attendance records"
  on public.attendance_records for select to authenticated
  using (
    student_id = auth.uid()
    or public.current_app_role() = 'director'
    or (
      public.current_app_role() = 'teacher'
      and exists (
        select 1 from public.sessions s
        where s.id = session_id and s.teacher_id = auth.uid()
      )
    )
  );

create policy "Students declare their own presence"
  on public.attendance_records for insert to authenticated
  with check (
    student_id = auth.uid()
    and marked_by = auth.uid()
    and status in ('declared_present', 'declared_absent')
    and public.current_app_role() = 'student'
    and exists (
      select 1 from public.sessions s
      where s.id = session_id and s.class_name = public.current_class_name()
    )
  );

create policy "Teachers validate attendance"
  on public.attendance_records for insert to authenticated
  with check (
    public.current_app_role() in ('teacher', 'director')
    and exists (
      select 1 from public.sessions s
      where s.id = session_id
        and (
          public.current_app_role() = 'director'
          or s.teacher_id = auth.uid()
        )
      and exists (
        select 1 from public.profiles p
        where p.id = student_id and p.class_name = s.class_name
      )
    )
  );

create policy "Students can repeat their pending declaration"
  on public.attendance_records for update to authenticated
  using (
    student_id = auth.uid()
    and status in ('declared_present', 'declared_absent')
  )
  with check (
    student_id = auth.uid()
    and marked_by = auth.uid()
    and status in ('declared_present', 'declared_absent')
    and exists (
      select 1 from public.sessions s
      where s.id = session_id and s.class_name = public.current_class_name()
    )
  );

create policy "Teachers and directors validate attendance"
  on public.attendance_records for update to authenticated
  using (
    public.current_app_role() = 'director'
    or (
      public.current_app_role() = 'teacher'
      and exists (
        select 1 from public.sessions s
        where s.id = session_id and s.teacher_id = auth.uid()
      )
    )
  )
  with check (
    public.current_app_role() in ('teacher', 'director')
    and exists (
      select 1
      from public.sessions s
      join public.profiles p on p.id = student_id
      where s.id = session_id
        and p.class_name = s.class_name
        and (
          public.current_app_role() = 'director'
          or s.teacher_id = auth.uid()
        )
    )
  );

create policy "Users see relevant claims"
  on public.claims for select to authenticated
  using (
    student_id = auth.uid()
    or public.current_app_role() = 'director'
    or (
      public.current_app_role() = 'teacher'
      and exists (
        select 1 from public.sessions s
        where s.id = session_id and s.teacher_id = auth.uid()
      )
    )
  );

create policy "Students submit their own claims"
  on public.claims for insert to authenticated
  with check (
    student_id = auth.uid()
    and public.current_app_role() = 'student'
    and status = 'pending'
    and resolved_by is null
    and exists (
      select 1 from public.sessions s
      where s.id = session_id and s.class_name = public.current_class_name()
    )
  );

create policy "Teachers and directors resolve claims"
  on public.claims for update to authenticated
  using (
    public.current_app_role() = 'director'
    or (
      public.current_app_role() = 'teacher'
      and exists (
        select 1 from public.sessions s
        where s.id = session_id and s.teacher_id = auth.uid()
      )
    )
  )
  with check (
    status in ('approved', 'rejected')
    and resolved_by = auth.uid()
    and public.current_app_role() in ('teacher', 'director')
    and exists (
      select 1
      from public.sessions s
      join public.profiles p on p.id = student_id
      where s.id = session_id
        and p.class_name = s.class_name
        and (
          public.current_app_role() = 'director'
          or s.teacher_id = auth.uid()
        )
    )
  );

create policy "Directors can read audit history"
  on public.audit_logs for select to authenticated
  using (public.current_app_role() = 'director');

grant select on public.profiles to authenticated;
grant select, insert, update on public.sessions to authenticated;
grant select, insert, update on public.attendance_records to authenticated;
grant select, insert, update on public.claims to authenticated;
grant select on public.audit_logs to authenticated;
