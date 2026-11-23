-- Demo data for a Supabase project after the initial schema migration.
-- Create the student and teacher accounts in Supabase Auth first, then replace
-- the email addresses and class name below before running this script.
do $$
declare
  student_email text := 'jouinidina@gmail.com';
  teacher_email text := 'wadaalinda@gmail.com';
  director_email text := '';
  v_demo_class text := 'L1-A';
  v_student_id uuid;
  v_teacher_id uuid;
  v_director_id uuid;
begin
  if student_email like 'ETUDIANT@%' or teacher_email like 'ENSEIGNANT@%' then
    raise exception
      'Remplacez student_email et teacher_email en haut de supabase/seed.sql par les e-mails de comptes déjà créés dans Supabase Auth.';
  end if;

  select id into v_student_id
  from auth.users
  where lower(email) = lower(student_email);
  if v_student_id is null then
    raise exception 'Compte étudiant introuvable dans Supabase Auth : %',
      student_email;
  end if;

  select id into v_teacher_id
  from auth.users
  where lower(email) = lower(teacher_email);
  if v_teacher_id is null then
    raise exception 'Compte enseignant introuvable dans Supabase Auth : %',
      teacher_email;
  end if;

  insert into public.profiles (id, full_name)
  values
    (v_student_id, 'Yasmine El Amrani'),
    (v_teacher_id, 'Karim Bensaid')
  on conflict (id) do nothing;

  update public.profiles
  set full_name = 'Yasmine El Amrani',
      role = 'student',
      class_name = v_demo_class
  where id = v_student_id;
  if not found then
    raise exception 'Profil étudiant absent. Vérifiez que la migration initiale a été exécutée.';
  end if;

  update public.profiles
  set full_name = 'Karim Bensaid',
      role = 'teacher',
      class_name = v_demo_class
  where id = v_teacher_id;
  if not found then
    raise exception 'Profil enseignant absent. Vérifiez que la migration initiale a été exécutée.';
  end if;

  if director_email <> '' then
    select id into v_director_id
    from auth.users
    where lower(email) = lower(director_email);
    if v_director_id is null then
      raise exception 'Compte directeur introuvable dans Supabase Auth : %',
        director_email;
    end if;

    insert into public.profiles (id, full_name)
    values (v_director_id, 'Nadia Directrice')
    on conflict (id) do nothing;

    update public.profiles
    set full_name = 'Nadia Directrice',
        role = 'director',
        class_name = null
    where id = v_director_id;
  end if;

  with days as (
    select day::date as lesson_day
    from generate_series(
      date_trunc('week', now()),
      date_trunc('week', now()) + interval '4 days',
      interval '1 day'
    ) as generated(day)
    where extract(isodow from day) between 1 and 5
  ),
  courses(course_name, course_code, room, lesson_time) as (
    values
      ('Algorithmique avancée', 'INF-204', 'Salle B12', time '08:30'),
      ('Bases de données', 'INF-216', 'Labo 03', time '10:30'),
      ('Réseaux informatiques', 'INF-220', 'Salle A05', time '14:00'),
      ('Développement mobile', 'INF-231', 'Labo 02', time '16:00')
  )
  insert into public.sessions (
    course_name,
    course_code,
    teacher_name,
    teacher_id,
    class_name,
    room,
    starts_at
  )
  select
    courses.course_name,
    courses.course_code,
    'Karim Bensaid',
    v_teacher_id,
    v_demo_class,
    courses.room,
    days.lesson_day + courses.lesson_time
  from days
  cross join courses
  where not exists (
    select 1
    from public.sessions existing
    where existing.class_name = v_demo_class
      and existing.course_code = courses.course_code
      and existing.starts_at = days.lesson_day + courses.lesson_time
  );

  with numbered_sessions as (
    select
      s.id as session_id,
      row_number() over (order by s.starts_at) as sequence
    from public.sessions s
    where s.class_name = v_demo_class
      and s.teacher_id = v_teacher_id
      and s.starts_at >= date_trunc('week', now())
      and s.starts_at < date_trunc('week', now()) + interval '5 days'
  )
  insert into public.attendance_records (
    session_id,
    student_id,
    status,
    marked_by
  )
  select
    session_id,
    v_student_id,
    case sequence % 7
      when 0 then 'declared_present'
      when 1 then 'declared_absent'
      when 2 then 'absent'
      else 'present'
    end,
    case sequence % 7
      when 0 then v_student_id
      when 1 then v_student_id
      else v_teacher_id
    end
  from numbered_sessions
  on conflict (session_id, student_id) do nothing;

  insert into public.claims (
    session_id,
    student_id,
    course_name,
    reason,
    details
  )
  select
    attendance.session_id,
    v_student_id,
    session.course_name,
    'Présent en cours',
    'Donnée de démonstration : veuillez vérifier la feuille de présence.'
  from public.attendance_records attendance
  join public.sessions session on session.id = attendance.session_id
  where attendance.student_id = v_student_id
    and attendance.status = 'absent'
    and session.class_name = v_demo_class
    and not exists (
      select 1
      from public.claims existing
      where existing.session_id = attendance.session_id
        and existing.student_id = v_student_id
    )
  order by session.starts_at
  limit 2;
end;
$$;

-- Check the demo records after running the script.
select role, class_name, count(*) as profile_count
from public.profiles
group by role, class_name
order by role, class_name;

select course_name, course_code, room, starts_at
from public.sessions
where class_name = 'L1-A'
order by starts_at;

select status, count(*) as attendance_count
from public.attendance_records
group by status
order by status;

select status, count(*) as claim_count
from public.claims
group by status
order by status;
