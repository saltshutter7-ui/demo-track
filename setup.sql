-- =====================================================================================================
-- TF-TRACKER  -  setup.sql   (ONE file for a NEW, EMPTY Supabase project)
-- Supabase > SQL Editor > New query > paste ALL of this > Run.  Run it only ONCE, on a new project.
-- It creates the tables, the security rules (RLS) and all functions of TF-Tracker.  It contains NO data:
-- no workshops, no divisions, no users, no PRs.  Those are added afterwards by the first Admin.
-- Merged from supabase-step1 ... step33.  NOT run on a real Supabase by Claude (only on a local Postgres): first try it on a test project.
-- Left out on purpose: test function (step 3), column drop (1b), re-import helper, and the nightly auto-delete of old data (step 12 / 15 part C).
-- =====================================================================================================

-- ################ from supabase-step1.sql ################
-- TF-Tracker : STEP 1 (pilot) - run in Supabase > SQL Editor.  Safe to run once on a NEW project.
-- Data table: one row = one PR (transformer complaint). Dates are real DATE values.

create table if not exists public.data (
  id            bigint generated always as identity primary key,
  workshop      text not null,
  division      text not null,
  substation    text,
  feeder        text,
  place_of_damage text,
  capacity      int,
  complain_no   text,
  pr_no         text not null,
  pr_date       date,
  je_name       text,
  je_mobile     text,
  firm          text,
  issue_date    date,
  driver_name   text,
  driver_mobile text,
  repl_date     date,
  return_date   date,
  remark        text,
  updated_at    timestamptz not null default now(),
  constraint data_uni unique (workshop, pr_no)       -- same PR NO in two workshops is allowed; same workshop is not
);

create index if not exists data_div_prdate  on public.data (division, pr_date);
create index if not exists data_ws_prdate   on public.data (workshop, pr_date);
create index if not exists data_issue       on public.data (division, issue_date);
create index if not exists data_repl        on public.data (division, repl_date);
create index if not exists data_ret         on public.data (division, return_date);

-- Row Level Security: ON, and NO policy yet = nobody can read/write through the public API.
-- (The service_role key used by the import script bypasses RLS.)  Policies come in the next step.
alter table public.data enable row level security;

-- ################ from supabase-step2-users-rls.sql ################
-- TF-Tracker : STEP 2 (pilot) - users, workshops and Row Level Security.  Run in Supabase > SQL Editor, ONE time.
-- NOT TESTED by Claude on a real database yet: run it, then do the checks at the bottom before trusting it.
--
-- Words used here:
--   data.division  = the EDD / sub-division name that is in the data (E.E. E.D.D.-III Azamgarh ...)
--   org_division   = the app's DIVISION (the unit of one Division Head / Admin) - it owns some workshops.

create table if not exists public.workshops (
  name         text primary key,            -- AZAMGARH, MAU, BALLIA ...
  org_division text not null                -- which Admin's division owns this workshop
);

create table if not exists public.profiles (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  login_id     text not null unique,         -- what the person types as User ID
  display      text,
  role         text not null check (role in ('creator','discom','admin','je')),
  org_division text,                         -- admin: his division (null for creator / discom)
  scope        text[] not null default '{}', -- je: his workshops
  can_edit     boolean not null default false,
  active       boolean not null default true,
  must_change  boolean not null default false
);

-- helper functions (security definer = they may read profiles even though the caller may not read all of it)
create or replace function public.my_role()     returns text    language sql stable security definer set search_path = public as
  $$ select role from public.profiles where user_id = auth.uid() and active $$;
create or replace function public.my_division() returns text    language sql stable security definer set search_path = public as
  $$ select org_division from public.profiles where user_id = auth.uid() and active $$;
create or replace function public.my_can_edit() returns boolean language sql stable security definer set search_path = public as
  $$ select coalesce((select can_edit from public.profiles where user_id = auth.uid() and active), false) $$;
create or replace function public.my_workshops() returns text[] language sql stable security definer set search_path = public as
$$
  select case p.role
    when 'creator' then array(select name from public.workshops)
    when 'discom'  then array(select name from public.workshops)
    when 'admin'   then array(select name from public.workshops w where w.org_division = p.org_division)
    when 'je'      then p.scope
    else '{}'::text[] end
  from public.profiles p where p.user_id = auth.uid() and p.active
$$;

alter table public.workshops enable row level security;
alter table public.profiles  enable row level security;

-- who may read what -------------------------------------------------------
drop policy if exists ws_read on public.workshops;
create policy ws_read on public.workshops for select to authenticated
  using (name = any (coalesce((select public.my_workshops()), '{}')));

drop policy if exists pr_read on public.profiles;
create policy pr_read on public.profiles for select to authenticated
  using ( user_id = auth.uid()
          or (select public.my_role()) = 'creator'
          or ((select public.my_role()) = 'admin' and org_division = (select public.my_division())) );
-- (creating / changing users is done only by the server with the service_role key, never from the browser)

drop policy if exists data_read   on public.data;
drop policy if exists data_insert on public.data;
drop policy if exists data_update on public.data;
drop policy if exists data_delete on public.data;

create policy data_read on public.data for select to authenticated
  using (workshop = any (coalesce((select public.my_workshops()), '{}')));

-- only admin / je with can_edit may write, and only inside their own workshops (creator and discom: read only)
create policy data_insert on public.data for insert to authenticated
  with check ((select public.my_can_edit()) and (select public.my_role()) in ('admin','je')
              and workshop = any (coalesce((select public.my_workshops()), '{}')));
create policy data_update on public.data for update to authenticated
  using      ((select public.my_can_edit()) and (select public.my_role()) in ('admin','je')
              and workshop = any (coalesce((select public.my_workshops()), '{}')))
  with check ((select public.my_can_edit()) and (select public.my_role()) in ('admin','je')
              and workshop = any (coalesce((select public.my_workshops()), '{}')));
create policy data_delete on public.data for delete to authenticated
  using      ((select public.my_can_edit()) and (select public.my_role()) in ('admin','je')
              and workshop = any (coalesce((select public.my_workshops()), '{}')));

-- table privileges (new tables are not exposed automatically, so we grant exactly what is needed; anon gets nothing)
revoke all on public.data, public.workshops, public.profiles from anon;
grant select, insert, update, delete on public.data to authenticated;
grant select on public.workshops, public.profiles to authenticated;
grant execute on function public.my_role(), public.my_division(), public.my_can_edit(), public.my_workshops() to authenticated;

-- (no workshops are created here: the first Admin adds his own workshops in the Admin tab)

-- =====================================================================
-- TEST USERS (do these by hand, after running the part above)
-- 1) Supabase > Authentication > Users > Add user > Create new user:
--      email  admin1@tf.uppcl   password (your choice)   tick "Auto Confirm User"
--      email  je_mau@tf.uppcl   password (your choice)   tick "Auto Confirm User"
--      email  head1@tf.uppcl    password (your choice)   tick "Auto Confirm User"
-- 2) Then run these three inserts:
--
-- insert into public.profiles (user_id, login_id, display, role, org_division, scope, can_edit)
--   select id, 'admin1', 'Test Admin', 'admin', 'EWD AZAMGARH', '{}', true  from auth.users where email = 'admin1@tf.uppcl';
-- insert into public.profiles (user_id, login_id, display, role, org_division, scope, can_edit)
--   select id, 'je_mau', 'Test JE Mau', 'je', null, '{MAU}', true     from auth.users where email = 'je_mau@tf.uppcl';
-- insert into public.profiles (user_id, login_id, display, role, org_division, scope, can_edit)
--   select id, 'head1', 'Test DISCOM head', 'discom', null, '{}', false from auth.users where email = 'head1@tf.uppcl';
--
-- CHECKS the test page must show:  admin1 sees AZAMGARH + BALLIA + MAU;  je_mau sees ONLY MAU;
--   head1 sees all but cannot insert/update/delete;  a person with no profile row sees NOTHING;  the anon key alone sees NOTHING.

-- ################ from supabase-step4-summary.sql ################
-- STEP 4: the heavy counting of the Summary tab, done inside the database.
-- Same 15 metrics (0..14) as flags_() in Code.gs.  SECURITY INVOKER: every caller only counts the rows RLS lets him see.
-- p_date = the "Date" box, p_from / p_to = the From / To boxes.

-- a wrong / duplicate PR = firm "DUPLICATE/WRONG PR" (same rule as isDup_ in Code.gs)
create or replace function public.is_dup(firm text) returns boolean language sql immutable as
$$ select upper(btrim(regexp_replace(coalesce(firm,''), '\s+', ' ', 'g'))) ~ '^DUPLICATE\s*/?\s*WRONG\s*PR\.?$' $$;

-- a stored column "dup" so that the counting does not run the text rule for every row (about 5x faster)
alter table public.data add column if not exists dup boolean generated always as (public.is_dup(firm)) stored;
create index if not exists data_dup on public.data (dup) where dup;

-- one row per workshop x division x capacity, with the 15 counts
create or replace function public.summary_agg(p_date date, p_from date, p_to date)
returns table(workshop text, division text, capacity int,
              m0 bigint, m1 bigint, m2 bigint, m3 bigint, m4 bigint, m5 bigint, m6 bigint, m7 bigint,
              m8 bigint, m9 bigint, m10 bigint, m11 bigint, m12 bigint, m13 bigint, m14 bigint)
language sql stable security invoker set search_path = public as
$$
  with r as (
    select d.workshop,
           upper(btrim(regexp_replace(coalesce(d.division,''), '\s+', ' ', 'g'))) as division,
           coalesce(d.capacity, 0) as capacity,
           d.dup as dup,
           coalesce(d.pr_date, date '1900-01-01') as pr,      -- no PR date = "0" in the old code (older than everything)
           d.issue_date as i, d.repl_date as p, d.return_date as t
    from public.data d
  )
  select r.workshop, r.division, r.capacity,
    count(*) filter (where not dup and pr < p_from and (i is null or i >= p_from) and (t is null or t > p_from - 1)),                                  -- 0
    count(*) filter (where not dup and pr = p_date),                                                                                                   -- 1
    count(*) filter (where not dup and pr = p_date and i is not null),                                                                                 -- 2
    count(*) filter (where not dup and pr = p_date and p is not null),                                                                                 -- 3
    count(*) filter (where not dup and i = p_date),                                                                                                    -- 4
    count(*) filter (where not dup and p = p_date),                                                                                                    -- 5
    count(*) filter (where not dup and pr between p_from and p_to),                                                                                    -- 6
    count(*) filter (where not dup and i between p_from and p_to),                                                                                     -- 7
    count(*) filter (where not dup and p between p_from and p_to),                                                                                     -- 8
    count(*) filter (where not dup and pr <= p_to and (i is null or i > p_to) and (t is null or t > p_to)),                                            -- 9
    count(*) filter (where not dup and i is not null and i <= p_to and (p is null or p > p_to) and (t is null or t > p_to)),                           -- 10
    count(*) filter (where not dup and t = p_date),                                                                                                    -- 11
    count(*) filter (where not dup and t between p_from and p_to),                                                                                     -- 12
    count(*) filter (where not dup and p is not null and p <= p_to and (t is null or t > p_to)),                                                       -- 13
    count(*) filter (where dup and pr between p_from and p_to)                                                                                         -- 14
  from r
  group by r.workshop, r.division, r.capacity
  order by 1, 2, 3
$$;

-- pending for issue, date wise (PR date) x capacity, per workshop  (metric 9 only)
create or replace function public.summary_pending(p_to date)
returns table(workshop text, pr_date date, capacity int, n bigint)
language sql stable security invoker set search_path = public as
$$
  select d.workshop, d.pr_date, coalesce(d.capacity, 0), count(*)
  from public.data d
  where not d.dup
    and coalesce(d.pr_date, date '1900-01-01') <= p_to
    and (d.issue_date is null or d.issue_date > p_to)
    and (d.return_date is null or d.return_date > p_to)
  group by d.workshop, d.pr_date, coalesce(d.capacity, 0)
  order by 1, 2, 3
$$;

grant execute on function public.is_dup(text), public.summary_agg(date, date, date), public.summary_pending(date) to authenticated;

-- ################ from supabase-step5-compare.sql ################
-- STEP 5: Comparison tab counting (this period vs the SAME dates of the previous year), done in the database.
-- Counts PRs by PR DATE, capacity wise, like getCompare() in Code.gs. Wrong/duplicate PRs and rows without a PR date are not counted.
-- One output row = period ('c' this period, 'p' previous year) x day offset x workshop x division x substation x capacity.
-- (day offset = days since the From date of that period: used by "Day wise"; the other modes just add the offsets up)
-- p_day = true only for "Day wise" (then the day offset is kept; otherwise it is 0 and far fewer rows are returned).
-- p_div = optional division filter (the Division box); SECURITY INVOKER = RLS decides which workshops the caller sees.

drop function if exists public.compare_agg(date, date, text);
create or replace function public.compare_agg(p_from date, p_to date, p_div text default null, p_day boolean default false)
returns table(period text, off int, workshop text, division text, substation text, capacity int, n bigint)
language sql stable security invoker set search_path = public as
$$
  with w as (select p_from as f, p_to as t,
                    (p_from - interval '1 year')::date as pf, (p_to - interval '1 year')::date as pt),
  x as (
    select 'c'::text as period, (d.pr_date - w.f) as off, d.workshop, d.division, d.substation, d.capacity
      from public.data d, w
     where not d.dup and d.pr_date between w.f and w.t
    union all
    select 'p', (d.pr_date - w.pf), d.workshop, d.division, d.substation, d.capacity
      from public.data d, w
     where not d.dup and d.pr_date between w.pf and w.pt
  )
  select period, (case when p_day then off else 0 end)::int, workshop,
         upper(btrim(regexp_replace(coalesce(division,''),  '\s+', ' ', 'g'))) as division,
         upper(btrim(regexp_replace(coalesce(substation,''),'\s+', ' ', 'g'))) as substation,
         coalesce(capacity, 0), count(*)
    from x
   where p_div is null or p_div = '' or
         upper(btrim(regexp_replace(coalesce(division,''), '\s+', ' ', 'g'))) = upper(btrim(regexp_replace(p_div, '\s+', ' ', 'g')))
   group by 1, 2, 3, 4, 5, 6
   order by 1, 2, 3, 4, 5, 6
$$;
grant execute on function public.compare_agg(date, date, text, boolean) to authenticated;

-- ################ from supabase-step6-json.sql ################
-- STEP 6: FIX for the 1000-row limit.  Supabase returns at most 1000 ROWS per call, and silently cuts the rest.
-- (Your Test 7 showed "1000 rows returned": the last-year number was cut, the right one is bigger.)
-- These wrappers return ONE value (a JSON document), so nothing is cut.  Rows are packed as short arrays to save data transfer.
-- Run AFTER step 4 and step 5.

-- summary_json -> {"agg": [[workshop, division, capacity, m0..m14], ...], "pending": [[workshop, pr_date, capacity, n], ...]}
create or replace function public.summary_json(p_date date, p_from date, p_to date)
returns jsonb language sql stable security invoker set search_path = public as
$$
  select jsonb_build_object(
    'agg', coalesce((select jsonb_agg(jsonb_build_array(workshop, division, capacity, m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14))
                       from public.summary_agg(p_date, p_from, p_to)), '[]'::jsonb),
    'pending', coalesce((select jsonb_agg(jsonb_build_array(workshop, pr_date, capacity, n))
                           from public.summary_pending(p_to)), '[]'::jsonb))
$$;

-- compare_json -> [[period, day_offset, workshop, division, substation, capacity, n], ...]
create or replace function public.compare_json(p_from date, p_to date, p_div text default null, p_day boolean default false)
returns jsonb language sql stable security invoker set search_path = public as
$$
  select coalesce(jsonb_agg(jsonb_build_array(period, off, workshop, division, substation, capacity, n)), '[]'::jsonb)
    from public.compare_agg(p_from, p_to, p_div, p_day)
$$;

grant execute on function public.summary_json(date, date, date), public.compare_json(date, date, text, boolean) to authenticated;

-- ################ from supabase-step7-lists.sql ################
-- STEP 7: the two READ functions of the Data tab and of the "click a number to see the records" list.
-- Rows come back in the SAME 20-column order the old app used (Category and TIME are empty text for now), dates as DD.MM.YYYY,
-- so the existing screens can show them without changes.  The result is ONE json value, so the 1000-row limit does not cut it.
-- SECURITY INVOKER: RLS decides which workshops the caller sees.

create or replace function public.row20(d public.data) returns jsonb language sql stable as
$$ select jsonb_build_array(
     d.workshop, coalesce(d.division,''), coalesce(d.substation,''), coalesce(d.feeder,''), coalesce(d.place_of_damage,''),
     coalesce(d.capacity::text,''), '' /* Category (removed) */, coalesce(d.complain_no,''), d.pr_no, coalesce(to_char(d.pr_date,'DD.MM.YYYY'),''),
     coalesce(d.je_name,''), coalesce(d.je_mobile,''), coalesce(d.firm,''), coalesce(to_char(d.issue_date,'DD.MM.YYYY'),''),
     coalesce(d.driver_name,''), coalesce(d.driver_mobile,''), coalesce(to_char(d.repl_date,'DD.MM.YYYY'),''), '' /* TIME (removed) */,
     coalesce(to_char(d.return_date,'DD.MM.YYYY'),''), coalesce(d.remark,'')) $$;

create or replace function public.can_edit_rows() returns boolean language sql stable as
$$ select coalesce(public.my_can_edit() and public.my_role() in ('admin','je'), false) $$;

-- Data tab: the PR records of ONE PR date (or all dates), newest first, at most 6000 rows
create or replace function public.data_json(p_date date default null, p_all boolean default false)
returns jsonb language sql stable security invoker set search_path = public as
$$
  with s as (
    select d.* from public.data d
     where p_all or (p_date is not null and d.pr_date = p_date)
  ), top as (
    select * from s order by pr_date desc nulls last, id desc limit 6000
  )
  select jsonb_build_object(
    'total', (select count(*) from s),
    'canEdit', public.can_edit_rows(),
    'rows', coalesce((select jsonb_agg(public.row20(t) order by t.pr_date desc nulls last, t.id desc) from top t), '[]'::jsonb))
$$;

-- list behind a number of the Summary: the records of ONE metric (0..14, same meaning as in summary_agg).
-- p_limit rows per call (default 300, to save data transfer), p_offset = how many rows were already loaded ("Load more" button).
drop function if exists public.list_json(int, date, date, date, text, text[], text[], int[], date);
create or replace function public.list_json(p_metric int, p_date date, p_from date, p_to date,
                                            p_ws text default null, p_divs text[] default null, p_subs text[] default null,
                                            p_caps int[] default null, p_prd date default null,
                                            p_limit int default 300, p_offset int default 0)
returns jsonb language sql stable security invoker set search_path = public as
$$
  with r as (
    select d.*, coalesce(d.pr_date, date '1900-01-01') as pr
      from public.data d
     where (p_ws is null or d.workshop = p_ws)
       and (p_caps is null or coalesce(d.capacity, 0) = any (p_caps))
       and (p_divs is null or upper(btrim(regexp_replace(coalesce(d.division,''),  '\s+', ' ', 'g'))) = any (p_divs))
       and (p_subs is null or upper(btrim(regexp_replace(coalesce(d.substation,''),'\s+', ' ', 'g'))) = any (p_subs))
       and (p_prd is null or d.pr_date = p_prd)
  ), h as (
    select r.*,
      case when r.dup then (p_metric = 14 and r.pr between p_from and p_to)
      else case p_metric
        when 0  then r.pr < p_from and (r.issue_date is null or r.issue_date >= p_from) and (r.return_date is null or r.return_date > p_from - 1)
        when 1  then r.pr = p_date
        when 2  then r.pr = p_date and r.issue_date is not null
        when 3  then r.pr = p_date and r.repl_date is not null
        when 4  then r.issue_date = p_date
        when 5  then r.repl_date = p_date
        when 6  then r.pr between p_from and p_to
        when 7  then r.issue_date between p_from and p_to
        when 8  then r.repl_date between p_from and p_to
        when 9  then r.pr <= p_to and (r.issue_date is null or r.issue_date > p_to) and (r.return_date is null or r.return_date > p_to)
        when 10 then r.issue_date is not null and r.issue_date <= p_to and (r.repl_date is null or r.repl_date > p_to) and (r.return_date is null or r.return_date > p_to)
        when 11 then r.return_date = p_date
        when 12 then r.return_date between p_from and p_to
        when 13 then r.repl_date is not null and r.repl_date <= p_to and (r.return_date is null or r.return_date > p_to)
        else false end
      end as hit
    from r
  ), top as (
    select d.* from public.data d
      join (select id from h where hit order by pr, pr_no collate "C" limit least(greatest(p_limit, 1), 2000) offset greatest(p_offset, 0)) k on k.id = d.id
  )
  select jsonb_build_object(
    'total', (select count(*) from h where hit),
    'rows', coalesce((select jsonb_agg(public.row20(t) || to_jsonb((select case when public.can_edit_rows() then 1 else 0 end)) order by coalesce(t.pr_date, date '1900-01-01'), t.pr_no collate "C") from top t), '[]'::jsonb))
$$;

grant execute on function public.row20(public.data), public.can_edit_rows(), public.data_json(date, boolean),
  public.list_json(int, date, date, date, text, text[], text[], int[], date, int, int) to authenticated;

-- ################ from supabase-step8-app.sql ################
-- STEP 8: what the new Summary / Comparison screen needs on top of steps 1-7.  Run ONCE in the SQL Editor (after step 7).
-- (a) list_json gets two more optional filters (PR date from / to) for the "Pending for issue - age wise" numbers.
-- (b) compare2_json = same as compare_json but WITHOUT the substation column: the new screen has no substation view, so the answer is about 3x smaller (saves egress).
-- (c) password_changed() lets a user clear his own "must change password" flag after he changed it.

-- (a)
-- list behind a number of the Summary: the records of ONE metric (0..14, same meaning as in summary_agg).
-- p_limit rows per call (default 300, to save data transfer), p_offset = how many rows were already loaded ("Load more" button).
drop function if exists public.list_json(int, date, date, date, text, text[], text[], int[], date);
drop function if exists public.list_json(int, date, date, date, text, text[], text[], int[], date, int, int);
create or replace function public.list_json(p_metric int, p_date date, p_from date, p_to date,
                                            p_ws text default null, p_divs text[] default null, p_subs text[] default null,
                                            p_caps int[] default null, p_prd date default null,
                                            p_limit int default 300, p_offset int default 0,
                                            p_prd_from date default null, p_prd_to date default null)
returns jsonb language sql stable security invoker set search_path = public as
$$
  with r as (
    select d.*, coalesce(d.pr_date, date '1900-01-01') as pr
      from public.data d
     where (p_ws is null or d.workshop = p_ws)
       and (p_caps is null or coalesce(d.capacity, 0) = any (p_caps))
       and (p_divs is null or upper(btrim(regexp_replace(coalesce(d.division,''),  '\s+', ' ', 'g'))) = any (p_divs))
       and (p_subs is null or upper(btrim(regexp_replace(coalesce(d.substation,''),'\s+', ' ', 'g'))) = any (p_subs))
       and (p_prd is null or d.pr_date = p_prd)
       and (p_prd_from is null or coalesce(d.pr_date, date '1900-01-01') >= p_prd_from)
       and (p_prd_to   is null or coalesce(d.pr_date, date '1900-01-01') <= p_prd_to)
  ), h as (
    select r.*,
      case when r.dup then (p_metric = 14 and r.pr between p_from and p_to)
      else case p_metric
        when 0  then r.pr < p_from and (r.issue_date is null or r.issue_date >= p_from) and (r.return_date is null or r.return_date > p_from - 1)
        when 1  then r.pr = p_date
        when 2  then r.pr = p_date and r.issue_date is not null
        when 3  then r.pr = p_date and r.repl_date is not null
        when 4  then r.issue_date = p_date
        when 5  then r.repl_date = p_date
        when 6  then r.pr between p_from and p_to
        when 7  then r.issue_date between p_from and p_to
        when 8  then r.repl_date between p_from and p_to
        when 9  then r.pr <= p_to and (r.issue_date is null or r.issue_date > p_to) and (r.return_date is null or r.return_date > p_to)
        when 10 then r.issue_date is not null and r.issue_date <= p_to and (r.repl_date is null or r.repl_date > p_to) and (r.return_date is null or r.return_date > p_to)
        when 11 then r.return_date = p_date
        when 12 then r.return_date between p_from and p_to
        when 13 then r.repl_date is not null and r.repl_date <= p_to and (r.return_date is null or r.return_date > p_to)
        else false end
      end as hit
    from r
  ), top as (
    select d.* from public.data d
      join (select id from h where hit order by pr, pr_no collate "C" limit least(greatest(p_limit, 1), 2000) offset greatest(p_offset, 0)) k on k.id = d.id
  )
  select jsonb_build_object(
    'total', (select count(*) from h where hit),
    'rows', coalesce((select jsonb_agg(public.row20(t) || to_jsonb((select case when public.can_edit_rows() then 1 else 0 end)) order by coalesce(t.pr_date, date '1900-01-01'), t.pr_no collate "C") from top t), '[]'::jsonb))
$$;


-- (b) [period, day_offset, workshop, division, capacity, n]
create or replace function public.compare2_json(p_from date, p_to date, p_div text default null, p_day boolean default false)
returns jsonb language sql stable security invoker set search_path = public as
$$
  select coalesce(jsonb_agg(jsonb_build_array(period, off, workshop, division, capacity, n)), '[]'::jsonb)
    from (select period, off, workshop, division, capacity, sum(n)::bigint as n
            from public.compare_agg(p_from, p_to, p_div, p_day)
           group by 1, 2, 3, 4, 5 order by 1, 2, 3, 4, 5) x
$$;

-- (c)
create or replace function public.password_changed() returns void language sql security definer set search_path = public as
$$ update public.profiles set must_change = false where user_id = auth.uid() $$;

grant execute on function
  public.list_json(int, date, date, date, text, text[], text[], int[], date, int, int, date, date),
  public.compare2_json(date, date, text, boolean),
  public.password_changed() to authenticated;

-- ################ from supabase-step9-add-user.sql ################
-- STEP 9: one-line helper to give a login its profile.  Run this file ONCE in the SQL Editor.
-- Use:  select public.add_profile('mau2', 'Ramesh Kumar', 'je', 'EWD AZAMGARH', array['MAU'], true);
-- The login (Authentication > Users > Add user, e-mail  mau2@tf.uppcl ) must exist first.  Running it again for the same ID just updates it.
create or replace function public.add_profile(p_login text, p_name text, p_role text, p_div text, p_scope text[] default '{}', p_edit boolean default false)
returns text language plpgsql security definer set search_path = public, auth as
$$
declare uid uuid; lid text := lower(btrim(p_login));
begin
  if p_role not in ('creator','discom','admin','je') then raise exception 'role must be creator, discom, admin or je'; end if;
  select id into uid from auth.users where lower(email) = lid || '@tf.uppcl';
  if uid is null then raise exception 'First create the login % in Authentication > Users > Add user', lid || '@tf.uppcl'; end if;
  insert into public.profiles (user_id, login_id, display, role, org_division, scope, can_edit, active, must_change)
  values (uid, lid, p_name, p_role, p_div, coalesce(p_scope,'{}'), p_edit, true, false)
  on conflict (user_id) do update set login_id = excluded.login_id, display = excluded.display, role = excluded.role,
        org_division = excluded.org_division, scope = excluded.scope, can_edit = excluded.can_edit, active = true;
  return 'OK: ' || lid || ' (' || p_role || ')';
end $$;
revoke all on function public.add_profile(text,text,text,text,text[],boolean) from public, anon, authenticated;

-- ################ from supabase-step10-save.sql ################
-- STEP 10: SAVING data (new PR, edit, Excel paste, delete) - same rules as saveGrid / saveRows / deleteRecord of the old Code.gs.
-- Run ONCE in Supabase > SQL Editor (after steps 1-9).
--
-- save_rows(items)  items = [{ "k": ["WORKSHOP","PRNO"] or null, "o": [20 old values] or null, "r": [20 values] }]
--   r = the 20 columns of the old DATA sheet:  Workshop, Division, Substation, Feeder, Place, Capacity, (Category - ignored), Complain no,
--       PR no, PR date, JE name, JE mobile, Firm, Issue date, Driver name, Driver mobile, Replacement date, (Time - ignored), Return date, Remark
--   dates are written DD.MM.YYYY.   k = the PR that is being edited (empty for a new row).   o = the values the user saw before editing (so only changed cells are applied).
--   Answer: { added, updated, same, skipped, notes[], keys[], bad[], rows{ "<item no>": [20 saved values] } }
-- delete_pr(workshop, pr)  deletes one PR (only if the user may edit that workshop).
-- Rules kept from the old app:
--   * a wrong / duplicate PR (firm "DUPLICATE/WRONG PR") has no issue date, no replacement / return date, no driver mobile; driver name is JE(D)
--   * PR no, PR date and a known workshop are compulsory; dates must be DD.MM.YYYY; a mobile is tidied when it is a 10-digit number, otherwise kept exactly as written
--   * a user may change only the workshops he is allowed to; a pasted row of ANOTHER workshop of the same division is saved there only if that PR is new
--   * a pasted row whose PR already exists only fills the non-empty cells (an empty cell never erases old data)

-- ---------- small helpers (same behaviour as capOf_ / mobClean_ / dk_ of Code.gs) ----------
create or replace function public.tf_cap(s text) returns int language plpgsql immutable as
$$
declare t text := btrim(replace(coalesce(s,''), E' ', ' ')); u text := upper(t); m text;
begin
  m := substring(u from '(?:^|[^0-9./])([0-9]+)\s*K\.?\s*V\.?\s*A');
  if m is null then m := substring(u from '(?:^|[^0-9./])([0-9]+)\s*KV'); end if;
  if m is not null then return m::int; end if;
  if t ~ '^[0-9]+(\.0+)?$' then return split_part(t, '.', 1)::int; end if;
  return 0;
end $$;

-- '' | 10 digits | null (invalid)
create or replace function public.tf_mob(v text) returns text language plpgsql immutable as
$$
declare s text := btrim(replace(coalesce(v,''), E' ', ' ')); m text[]; d text; dg text;
begin
  if s = '' then return ''; end if;
  m := regexp_match(s, '^([0-9])(?:\.([0-9]+))?\s*[eE]\s*\+?([0-9]+)$');
  if m is not null then
    dg := m[1] || coalesce(m[2], '');
    if length(dg) <> m[3]::int + 1 then return null; end if;
    s := dg;
  end if;
  d := regexp_replace(s, '[^0-9]', '', 'g');
  if length(d) = 12 and left(d, 2) = '91' then d := substr(d, 3);
  elsif length(d) = 11 and left(d, 1) = '0' then d := substr(d, 2); end if;
  if length(d) = 10 then return d; end if;
  return null;
end $$;

-- 'DD.MM.YYYY' -> date (null when empty / invalid; years 1990..2100 like dk_)
create or replace function public.tf_d(s text) returns date language plpgsql immutable as
$$
declare m text[];
begin
  s := btrim(coalesce(s,''));
  m := regexp_match(s, '^([0-9]{1,2})[./-]([0-9]{1,2})[./-]([0-9]{2}|[0-9]{4})$');          -- 29.10.2026   29/10/2026   29-10-26   9.5.2026
  if m is null then
    m := regexp_match(s, '^([0-9]{4})-([0-9]{2})-([0-9]{2})(?:[ T].*)?$');                     -- 2026-10-29
    if m is null then return null; end if;
    m := array[m[3], m[2], m[1]];
  end if;
  if length(m[3]) = 2 then m[3] := '20' || m[3]; end if;
  if m[3]::int < 1990 or m[3]::int > 2100 then return null; end if;
  return make_date(m[3]::int, m[2]::int, m[1]::int);
exception when others then return null;
end $$;

-- spelling distance of two short words (number of letters to add / remove / change)
create or replace function public.tf_lev(a text, b text) returns int language plpgsql immutable as
$$
declare la int := length(a); lb int := length(b); prev int[]; cur int[]; i int; j int; c int;
begin
  if la = 0 then return lb; end if; if lb = 0 then return la; end if;
  prev := array(select generate_series(0, lb));
  for i in 1..la loop
    cur := array[i];
    for j in 1..lb loop
      c := case when substr(a, i, 1) = substr(b, j, 1) then 0 else 1 end;
      cur := cur || least(prev[j + 1] + 1, cur[j] + 1, prev[j] + c);
    end loop;
    prev := cur;
  end loop;
  return prev[lb + 1];
end $$;

-- name typed by the user -> registered workshop name ('' if not recognised or not unique).
-- Also accepts small spelling mistakes (AZAMAGARH -> AZAMGARH, BALIA -> BALLIA): 1 wrong letter for 4-6 letters, 2 for 7 or more.
create or replace function public.tf_wskey(s text, wsl text[]) returns text language plpgsql immutable as
$$
declare t text := regexp_replace(upper(coalesce(s,'')), '[^A-Z0-9]', '', 'g'); t2 text; w text; k text; hit text[] := '{}'; d int; best int := 99; bw text := ''; nb int := 0; lim int;
begin
  if t = '' then return ''; end if;
  t2 := case when t ~ '^EW[CDS].' and length(t) > 5 then substr(t, 4) else t end;
  foreach w in array coalesce(wsl, '{}') loop
    if regexp_replace(upper(w), '[^A-Z0-9]', '', 'g') = t then return w; end if;
  end loop;
  foreach w in array coalesce(wsl, '{}') loop
    k := regexp_replace(upper(w), '[^A-Z0-9]', '', 'g');
    if (case when k ~ '^EW[CDS].' and length(k) > 5 then substr(k, 4) else k end) = t2 then return w; end if;
  end loop;
  foreach w in array coalesce(wsl, '{}') loop
    k := regexp_replace(upper(w), '[^A-Z0-9]', '', 'g'); k := case when k ~ '^EW[CDS].' and length(k) > 5 then substr(k, 4) else k end;
    if length(k) >= 3 and (position(k in t2) > 0 or (length(t2) >= 3 and position(t2 in k) > 0)) then hit := hit || w; end if;
  end loop;
  if array_length(hit, 1) = 1 then return hit[1]; end if;
  if array_length(hit, 1) > 1 then return ''; end if;
  -- spelling mistake: the single nearest workshop
  foreach w in array coalesce(wsl, '{}') loop
    k := regexp_replace(upper(w), '[^A-Z0-9]', '', 'g'); k := case when k ~ '^EW[CDS].' and length(k) > 5 then substr(k, 4) else k end;
    if length(k) < 4 or length(t2) < 4 then continue; end if;
    lim := case when least(length(k), length(t2)) >= 7 then 2 else 1 end;
    d := public.tf_lev(t2, k);
    if d <= lim then
      if d < best then best := d; bw := w; nb := 1; elsif d = best then nb := nb + 1; end if;
    end if;
  end loop;
  return case when nb = 1 then bw else '' end;
end $$;

-- ---------- save ----------
create or replace function public.save_rows(p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as
$$
declare
  v_role text := public.my_role(); v_div text := public.my_division(); v_scope text[] := coalesce(public.my_workshops(), '{}');
  wsl text[]; one text;
  n int := 0; it jsonb; r text[]; o text[]; kk text[]; t text[]; cur text[];
  cols text[]; i int; why text; foreign_ boolean; kw text; ex public.data; sav public.data;
  added int := 0; updated int := 0; same int := 0; skipped int := 0; fixd int := 0; notes jsonb := '[]'::jsonb; keys jsonb := '[]'::jsonb; bad jsonb := '[]'::jsonb; rowsout jsonb := '{}'::jsonb;
  mob text; cname text[] := array['Workshop','DIVISION','SUBSTATION','FEEDER','PLACE OF DAMAGE','CAPACITY','Category','COMPLAIN NUMBER','PR NO','PR DATE','JE Name','JE Mobile','ISSUED TO FIRM','ISSUE DATE','DRIVER NAME','DRIVER MOBILE','REPLACEMENT DATE','TIME','RETURN DATE','REMARK'];
  dupf constant text := 'DUPLICATE/WRONG PR';
  newkey text; done boolean;
begin
  if not coalesce(public.my_can_edit(), false) or v_role not in ('admin','je') then raise exception 'You do not have permission to change data.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('added',0,'updated',0,'same',0,'skipped',0,'notes','[]'::jsonb,'keys','[]'::jsonb,'bad','[]'::jsonb,'rows','{}'::jsonb,'datefix',0);
  end if;
  if jsonb_array_length(p_items) > 2000 then raise exception 'Too many rows in one call (maximum 2000).'; end if;
  select coalesce(array_agg(name order by name), '{}') into wsl from public.workshops where org_division = v_div;
  if array_length(v_scope, 1) = 1 then one := v_scope[1]; end if;

  for it in select * from jsonb_array_elements(p_items) loop
    n := n + 1; why := ''; foreign_ := false; done := false;
    -- the 20 values of the new row (trimmed)
    r := array(select btrim(replace(coalesce(x, ''), E' ', ' ')) from jsonb_array_elements_text(coalesce(it->'r', '[]'::jsonb)) x);
    while coalesce(array_length(r, 1), 0) < 20 loop r := r || ''::text; end loop;
    r[9] := case when r[9] ~ '^[0-9]+\.0+$' then split_part(r[9], '.', 1) else r[9] end;        -- PR no "123.0" -> "123"
    r[7] := ''; r[18] := '';                                                                      -- Category and TIME are not used any more
    if it->'o' is not null and jsonb_typeof(it->'o') = 'array' then
      o := array(select btrim(replace(coalesce(x, ''), E' ', ' ')) from jsonb_array_elements_text(it->'o') x);
      while coalesce(array_length(o, 1), 0) < 20 loop o := o || ''::text; end loop;
    else o := null; end if;
    if it->'k' is not null and jsonb_typeof(it->'k') = 'array' and jsonb_array_length(it->'k') = 2 then
      kk := array(select x from jsonb_array_elements_text(it->'k') x);
    else kk := null; end if;
    -- wrong / duplicate PR: no issue / replacement / return
    if public.is_dup(r[13]) then r[13] := dupf; r[14] := ''; r[15] := 'JE(D)'; r[16] := ''; r[17] := ''; r[19] := ''; end if;
    if r[1] = '' and one is not null then r[1] := one; end if;
    kw := public.tf_wskey(r[1], wsl); if kw <> '' then r[1] := kw; end if;

    if r[9] = '' then why := 'PR NO is empty';
    elsif public.tf_d(r[10]) is null then why := 'PR DATE is invalid/empty (DD.MM.YYYY required)';
    elsif kw = '' then why := 'Workshop is empty/not recognised (' || array_to_string(wsl, ' / ') || ')';
    elsif not (kw = any (v_scope)) then
      if kk is not null then why := 'WARNING - this row is for workshop "' || kw || '", but you can only save entries of ' || array_to_string(v_scope, ' / ') || '. It was NOT saved.';
      else foreign_ := true; end if;
    else
      foreach i in array array[14, 17, 19] loop        -- issue / replacement / return date that is not a date: the row is still saved, the date is left empty
        if r[i] <> '' and public.tf_d(r[i]) is null then                -- and what was written goes into the Remark (so nothing is lost; the PR shows as pending until a user corrects it)
          if position('[' || cname[i] || ' as written: ' || r[i] || ']' in r[20]) = 0 then r[20] := btrim(r[20] || ' [' || cname[i] || ' as written: ' || r[i] || ']'); end if;
          r[i] := ''; fixd := fixd + 1;
        end if;
      end loop;
    end if;
    if why = '' then
      foreach i in array array[12, 16] loop             -- mobiles: only what was changed in this save is checked
        if r[i] = '' or (o is not null and r[i] = o[i]) then continue; end if;
        mob := public.tf_mob(r[i]);
        if mob is not null then r[i] := mob; else r[i] := btrim(r[i]); end if;      -- a good 10-digit number is tidied; anything else is kept exactly as it was written
      end loop;
    end if;

    if why = '' then
      select * into ex from public.data where workshop = r[1] and pr_no = r[9];
      if foreign_ and found then why := 'this PR already exists in workshop ' || kw || ' - skipped'; end if;
    end if;

    if why = '' and kk is not null then
      -- ---- edit of an existing row (kk = its old key) ----
      select * into ex from public.data where workshop = kk[1] and pr_no = kk[2];
      if not found then why := 'the old entry was not found (did someone delete it?)';
      elsif not (ex.workshop = any (v_scope)) then why := 'You do not have permission to change this entry';
      else
        cur := array(select jsonb_array_elements_text(public.row20(ex)));
        t := r;
        if o is not null then          -- only the cells the user changed are applied on the stored row
          t := cur;
          for i in 1..20 loop if r[i] <> o[i] then t[i] := r[i]; end if; end loop;
          if public.is_dup(t[13]) then t[13] := dupf; t[14] := ''; t[15] := 'JE(D)'; t[16] := ''; t[17] := ''; t[19] := ''; end if;
        end if;
        t[7] := ''; t[18] := '';
        newkey := t[1] || '|' || t[9];
        if newkey <> kk[1] || '|' || kk[2] and exists (select 1 from public.data where workshop = t[1] and pr_no = t[9]) then
          why := 'This PR NO already exists in this workshop';
        elsif not (t[1] = any (v_scope)) then why := 'You do not have permission to change this entry';
        else
          cols := t;
          if cols = cur then same := same + 1;
          else
            update public.data set workshop = t[1], division = t[2], substation = nullif(t[3], ''), feeder = nullif(t[4], ''), place_of_damage = nullif(t[5], ''),
                   capacity = nullif(public.tf_cap(t[6]), 0), complain_no = nullif(t[8], ''), pr_no = t[9], pr_date = public.tf_d(t[10]),
                   je_name = nullif(t[11], ''), je_mobile = nullif(t[12], ''), firm = nullif(t[13], ''), issue_date = public.tf_d(t[14]),
                   driver_name = nullif(t[15], ''), driver_mobile = nullif(t[16], ''), repl_date = public.tf_d(t[17]), return_date = public.tf_d(t[19]),
                   remark = nullif(t[20], ''), updated_at = now()
             where id = ex.id returning * into sav;
            updated := updated + 1;
          end if;
          done := true;
        end if;
      end if;
    elsif why = '' then
      select * into ex from public.data where workshop = r[1] and pr_no = r[9];
      if found then
        -- ---- PR already exists: only the non-empty cells are filled / changed ----
        if not (ex.workshop = any (v_scope)) then why := 'You do not have permission to change this entry';
        else
          cur := array(select jsonb_array_elements_text(public.row20(ex)));
          t := cur;
          for i in 1..20 loop if r[i] <> '' and r[i] <> cur[i] then t[i] := r[i]; end if; end loop;
          if public.is_dup(t[13]) then t[13] := dupf; t[14] := ''; t[15] := 'JE(D)'; t[16] := ''; t[17] := ''; t[19] := ''; end if;
          t[7] := ''; t[18] := '';
          if t = cur then same := same + 1;
          else
            update public.data set division = t[2], substation = nullif(t[3], ''), feeder = nullif(t[4], ''), place_of_damage = nullif(t[5], ''),
                   capacity = nullif(public.tf_cap(t[6]), 0), complain_no = nullif(t[8], ''), pr_date = public.tf_d(t[10]),
                   je_name = nullif(t[11], ''), je_mobile = nullif(t[12], ''), firm = nullif(t[13], ''), issue_date = public.tf_d(t[14]),
                   driver_name = nullif(t[15], ''), driver_mobile = nullif(t[16], ''), repl_date = public.tf_d(t[17]), return_date = public.tf_d(t[19]),
                   remark = nullif(t[20], ''), updated_at = now()
             where id = ex.id returning * into sav;
            updated := updated + 1;
          end if;
          t := t; done := true;
        end if;
      else
        -- ---- new row ----
        begin
          insert into public.data (workshop, division, substation, feeder, place_of_damage, capacity, complain_no, pr_no, pr_date, je_name, je_mobile, firm,
                                   issue_date, driver_name, driver_mobile, repl_date, return_date, remark)
          values (r[1], r[2], nullif(r[3], ''), nullif(r[4], ''), nullif(r[5], ''), nullif(public.tf_cap(r[6]), 0), nullif(r[8], ''), r[9], public.tf_d(r[10]),
                  nullif(r[11], ''), nullif(r[12], ''), nullif(r[13], ''), public.tf_d(r[14]), nullif(r[15], ''), nullif(r[16], ''), public.tf_d(r[17]), public.tf_d(r[19]), nullif(r[20], ''))
          returning * into sav;
          added := added + 1; t := r; done := true;
        exception when unique_violation then why := 'this PR already exists in workshop ' || kw || ' - skipped';
        end;
      end if;
    end if;

    if why <> '' then
      skipped := skipped + 1; bad := bad || to_jsonb(n - 1);
      if jsonb_array_length(notes) < 15 then notes := notes || to_jsonb('Line ' || n || ' (PR ' || coalesce(nullif(r[9], ''), '-') || '): ' || why); end if;
    elsif done then
      keys := keys || to_jsonb(coalesce(sav.workshop, t[1]) || '|' || coalesce(sav.pr_no, t[9]));
      if sav.id is not null and (sav.workshop = (case when kk is not null then t[1] else r[1] end)) then
        rowsout := rowsout || jsonb_build_object((n - 1)::text, public.row20(sav));
      end if;
    else   -- "same": nothing to write, the row is as it is
      keys := keys || to_jsonb(coalesce(t[1], r[1]) || '|' || coalesce(t[9], r[9]));
    end if;
    sav := null;
  end loop;

  return jsonb_build_object('added', added, 'updated', updated, 'same', same, 'skipped', skipped, 'notes', notes, 'keys', keys, 'bad', bad, 'rows', rowsout, 'datefix', fixd);
end $$;

-- ---------- delete (RLS decides who may delete what) ----------
create or replace function public.delete_pr(p_ws text, p_pr text) returns boolean
language plpgsql security invoker set search_path = public as
$$
declare c int;
begin
  delete from public.data where workshop = p_ws and pr_no = btrim(p_pr);
  get diagnostics c = row_count;
  if c = 0 then raise exception 'PR % not found, or you do not have permission to delete it.', p_pr; end if;
  return true;
end $$;

revoke all on function public.save_rows(jsonb) from public, anon;
grant execute on function public.save_rows(jsonb), public.delete_pr(text, text),
  public.tf_cap(text), public.tf_mob(text), public.tf_d(text), public.tf_wskey(text, text[]), public.tf_lev(text, text) to authenticated;

-- ################ from supabase-step11-admin.sql ################
-- TF-Tracker : STEP 11 - tab access per user, many Admins, Admin writes his own workshops, Driver Master.
-- Run ONCE in Supabase > SQL Editor (after steps 1-10).  Safe to run again.

-- 1) tab access: NULL = all tabs of the role.  Otherwise a list of: sum, data, drv   (example: {sum} = Summary only)
alter table public.profiles add column if not exists tabs text[];
update public.profiles set tabs = array_remove(tabs, 'cmp') where 'cmp' = any(tabs);
update public.profiles set tabs = null where tabs = '{}';

-- a user whose tabs do not include 'data' can never edit
create or replace function public.my_can_edit() returns boolean language sql stable security definer set search_path = public as
  $$ select coalesce((select can_edit and (tabs is null or 'data' = any(tabs)) from public.profiles where user_id = auth.uid() and active), false) $$;

-- JEs created before this step have no org_division: copy it from their first workshop (so their Admin can see them)
update public.profiles p set org_division = (select w.org_division from public.workshops w where w.name = p.scope[1])
 where p.role = 'je' and p.org_division is null and cardinality(p.scope) > 0;

-- 2) Driver Master ----------------------------------------------------------
create or replace function public.tf_nk(t text) returns text language sql immutable as
  $$ select upper(regexp_replace(coalesce(t,''), '[^A-Za-z0-9]', '', 'g')) $$;

create table if not exists public.drivers (
  id        uuid primary key default gen_random_uuid(),
  firm      text not null,
  workshop  text not null references public.workshops(name) on update cascade on delete cascade,
  driver    text not null,
  mobile    text not null default '' check (mobile = '' or mobile ~ '^[0-9]{10}$'),
  gps       text not null default '',
  vehicle   text not null default ''
);
create unique index if not exists drivers_uq on public.drivers (workshop, public.tf_nk(firm), public.tf_nk(driver));
alter table public.drivers enable row level security;

drop policy if exists drv_read on public.drivers;
create policy drv_read on public.drivers for select to authenticated
  using (workshop = any (coalesce((select public.my_workshops()), '{}')));
drop policy if exists drv_ins on public.drivers;
create policy drv_ins on public.drivers for insert to authenticated
  with check ((select public.my_can_edit()) and (select public.my_role()) in ('admin','je')
              and workshop = any (coalesce((select public.my_workshops()), '{}')) and public.tf_nk(firm) <> 'DUPLICATEWRONGPR');
drop policy if exists drv_upd on public.drivers;
create policy drv_upd on public.drivers for update to authenticated
  using      ((select public.my_can_edit()) and (select public.my_role()) in ('admin','je')
              and workshop = any (coalesce((select public.my_workshops()), '{}')) and public.tf_nk(firm) <> 'DUPLICATEWRONGPR')
  with check ((select public.my_can_edit()) and (select public.my_role()) in ('admin','je')
              and workshop = any (coalesce((select public.my_workshops()), '{}')) and public.tf_nk(firm) <> 'DUPLICATEWRONGPR');
drop policy if exists drv_del on public.drivers;
create policy drv_del on public.drivers for delete to authenticated
  using      ((select public.my_can_edit()) and (select public.my_role()) in ('admin','je')
              and workshop = any (coalesce((select public.my_workshops()), '{}')) and public.tf_nk(firm) <> 'DUPLICATEWRONGPR');
revoke all on public.drivers from anon;
grant select, insert, update, delete on public.drivers to authenticated;

-- every workshop gets the default entry  firm DUPLICATE/WRONG PR, driver JE(D)
create or replace function public.tf_drv_default() returns trigger language plpgsql security definer set search_path = public as
$$ begin
  insert into public.drivers (firm, workshop, driver) values ('DUPLICATE/WRONG PR', new.name, 'JE(D)') on conflict do nothing;
  return new;
end $$;
drop trigger if exists tf_drv_default on public.workshops;
create trigger tf_drv_default after insert on public.workshops for each row execute function public.tf_drv_default();
insert into public.drivers (firm, workshop, driver) select 'DUPLICATE/WRONG PR', name, 'JE(D)' from public.workshops on conflict do nothing;

-- 3) workshops: an Admin writes the names of HIS OWN workshops ---------------
create or replace function public.tf_caller() returns public.profiles language sql stable security definer set search_path = public as
  $$ select p from public.profiles p where p.user_id = auth.uid() and p.active $$;

create or replace function public.ws_add(p_name text, p_div text default null) returns text
language plpgsql security definer set search_path = public as
$$
declare c public.profiles := public.tf_caller(); n text := upper(regexp_replace(btrim(coalesce(p_name,'')), '\s+', ' ', 'g')); d text;
begin
  if c.user_id is null or c.role not in ('admin','creator') then raise exception 'Only an Admin can add a workshop.'; end if;
  if n !~ '^[A-Z0-9][A-Z0-9 ._&()/-]{1,29}$' then raise exception 'Workshop name: 2-30 characters (letters, numbers, space . - & ( ) /).'; end if;
  d := case when c.role = 'admin' then c.org_division else nullif(btrim(coalesce(p_div,'')), '') end;
  if d is null then raise exception 'Division is required.'; end if;
  if exists (select 1 from public.workshops where name = n) then raise exception 'The workshop % already exists.', n; end if;
  insert into public.workshops (name, org_division) values (n, d);
  return n;
end $$;

create or replace function public.ws_rename(p_old text, p_new text) returns text
language plpgsql security definer set search_path = public as
$$
declare c public.profiles := public.tf_caller(); n text := upper(regexp_replace(btrim(coalesce(p_new,'')), '\s+', ' ', 'g')); w public.workshops;
begin
  if c.user_id is null or c.role not in ('admin','creator') then raise exception 'Only an Admin can rename a workshop.'; end if;
  select * into w from public.workshops where name = p_old;
  if w.name is null or (c.role = 'admin' and w.org_division is distinct from c.org_division) then raise exception 'Workshop not found in your division.'; end if;
  if n !~ '^[A-Z0-9][A-Z0-9 ._&()/-]{1,29}$' then raise exception 'Workshop name: 2-30 characters (letters, numbers, space . - & ( ) /).'; end if;
  if n = p_old then return n; end if;
  if exists (select 1 from public.workshops where name = n) then raise exception 'The workshop % already exists.', n; end if;
  update public.workshops set name = n where name = p_old;                 -- drivers follow by foreign key
  update public.data set workshop = n where workshop = p_old;
  update public.profiles set scope = array_replace(scope, p_old, n) where p_old = any(scope);
  return n;
end $$;

create or replace function public.ws_delete(p_name text) returns text
language plpgsql security definer set search_path = public as
$$
declare c public.profiles := public.tf_caller(); w public.workshops;
begin
  if c.user_id is null or c.role not in ('admin','creator') then raise exception 'Only an Admin can delete a workshop.'; end if;
  select * into w from public.workshops where name = p_name;
  if w.name is null or (c.role = 'admin' and w.org_division is distinct from c.org_division) then raise exception 'Workshop not found in your division.'; end if;
  if exists (select 1 from public.data where workshop = p_name limit 1) then raise exception 'This workshop has data. It cannot be deleted (rename it instead).'; end if;
  update public.profiles set scope = array_remove(scope, p_name) where p_name = any(scope);
  delete from public.workshops where name = p_name;                      -- its drivers go with it
  return p_name;
end $$;

-- 4) change a user (name, workshops, Can edit, tabs, active) ----------------
create or replace function public.admin_set_user(p_login text, p_name text, p_scope text[], p_edit boolean, p_tabs text[], p_active boolean) returns text
language plpgsql security definer set search_path = public as
$$
declare c public.profiles := public.tf_caller(); t public.profiles; sc text[] := coalesce(p_scope, '{}'); tb text[] := p_tabs; ed boolean := coalesce(p_edit,false);
begin
  if c.user_id is null or c.role not in ('admin','creator') then raise exception 'Only an Admin can change users.'; end if;
  select * into t from public.profiles where login_id = lower(btrim(p_login));
  if t.user_id is null then raise exception 'User not found.'; end if;
  if t.role = 'creator' then raise exception 'This user cannot be changed here.'; end if;
  if c.role = 'admin' and not (t.role = 'je' and t.org_division is not distinct from c.org_division) then raise exception 'You can change only the users of your own division.'; end if;
  if t.user_id = c.user_id and not coalesce(p_active, true) then raise exception 'You cannot deactivate your own ID.'; end if;
  if tb is not null then
    if cardinality(tb) = 0 then raise exception 'Choose at least one tab.'; end if;
    if exists (select 1 from unnest(tb) x where x not in ('sum','data','drv')) then raise exception 'Unknown tab.'; end if;
    if not ('data' = any(tb)) then ed := false; end if;
  end if;
  if t.role = 'je' then
    if cardinality(sc) = 0 then raise exception 'Choose at least one workshop.'; end if;
    if exists (select 1 from unnest(sc) x where x not in (select name from public.workshops where org_division = coalesce(t.org_division, c.org_division))) then
      raise exception 'A workshop is not in this division.'; end if;
  else sc := t.scope; end if;
  update public.profiles set display = coalesce(nullif(btrim(p_name),''), display), scope = sc, can_edit = ed, tabs = tb, active = coalesce(p_active, active)
   where user_id = t.user_id;
  return 'OK';
end $$;

revoke all on function public.ws_add(text,text), public.ws_rename(text,text), public.ws_delete(text), public.admin_set_user(text,text,text[],boolean,text[],boolean), public.tf_caller() from public, anon;
grant execute on function public.ws_add(text,text), public.ws_rename(text,text), public.ws_delete(text), public.admin_set_user(text,text,text[],boolean,text[],boolean) to authenticated;
grant execute on function public.tf_nk(text) to authenticated;

-- 5) the Edge Function (service_role) must be allowed to read / write the profile table
grant usage on schema public to service_role;
grant select, insert, update, delete on public.profiles, public.workshops, public.drivers, public.data to service_role;

-- ################ from supabase-step13-dup.sql ################
-- STEP 13: a DUPLICATE/WRONG PR can have nothing filled after the firm (issue date, driver mobile, replacement, return are cleared; driver = JE(D)).
-- Run ONCE in SQL Editor (it replaces the save function of step 10; if you run the new step 10 you do not need this).
-- STEP 10: SAVING data (new PR, edit, Excel paste, delete) - same rules as saveGrid / saveRows / deleteRecord of the old Code.gs.
-- Run ONCE in Supabase > SQL Editor (after steps 1-9).
--
-- save_rows(items)  items = [{ "k": ["WORKSHOP","PRNO"] or null, "o": [20 old values] or null, "r": [20 values] }]
--   r = the 20 columns of the old DATA sheet:  Workshop, Division, Substation, Feeder, Place, Capacity, (Category - ignored), Complain no,
--       PR no, PR date, JE name, JE mobile, Firm, Issue date, Driver name, Driver mobile, Replacement date, (Time - ignored), Return date, Remark
--   dates are written DD.MM.YYYY.   k = the PR that is being edited (empty for a new row).   o = the values the user saw before editing (so only changed cells are applied).
--   Answer: { added, updated, same, skipped, notes[], keys[], bad[], rows{ "<item no>": [20 saved values] } }
-- delete_pr(workshop, pr)  deletes one PR (only if the user may edit that workshop).
-- Rules kept from the old app:
--   * a wrong / duplicate PR (firm "DUPLICATE/WRONG PR") has no issue date, no replacement / return date, no driver mobile; driver name is JE(D)
--   * PR no, PR date and a known workshop are compulsory; dates must be DD.MM.YYYY; mobiles must be 10 digits
--   * a user may change only the workshops he is allowed to; a pasted row of ANOTHER workshop of the same division is saved there only if that PR is new
--   * a pasted row whose PR already exists only fills the non-empty cells (an empty cell never erases old data)

-- ---------- small helpers (same behaviour as capOf_ / mobClean_ / dk_ of Code.gs) ----------
create or replace function public.tf_cap(s text) returns int language plpgsql immutable as
$$
declare t text := btrim(replace(coalesce(s,''), E' ', ' ')); u text := upper(t); m text;
begin
  m := substring(u from '(?:^|[^0-9./])([0-9]+)\s*K\.?\s*V\.?\s*A');
  if m is null then m := substring(u from '(?:^|[^0-9./])([0-9]+)\s*KV'); end if;
  if m is not null then return m::int; end if;
  if t ~ '^[0-9]+(\.0+)?$' then return split_part(t, '.', 1)::int; end if;
  return 0;
end $$;

-- '' | 10 digits | null (invalid)
create or replace function public.tf_mob(v text) returns text language plpgsql immutable as
$$
declare s text := btrim(replace(coalesce(v,''), E' ', ' ')); m text[]; d text; dg text;
begin
  if s = '' then return ''; end if;
  m := regexp_match(s, '^([0-9])(?:\.([0-9]+))?\s*[eE]\s*\+?([0-9]+)$');
  if m is not null then
    dg := m[1] || coalesce(m[2], '');
    if length(dg) <> m[3]::int + 1 then return null; end if;
    s := dg;
  end if;
  d := regexp_replace(s, '[^0-9]', '', 'g');
  if length(d) = 12 and left(d, 2) = '91' then d := substr(d, 3);
  elsif length(d) = 11 and left(d, 1) = '0' then d := substr(d, 2); end if;
  if length(d) = 10 then return d; end if;
  return null;
end $$;

-- 'DD.MM.YYYY' -> date (null when empty / invalid; years 1990..2100 like dk_)
create or replace function public.tf_d(s text) returns date language plpgsql immutable as
$$
declare m text[];
begin
  m := regexp_match(coalesce(s,''), '^([0-9]{2})\.([0-9]{2})\.([0-9]{4})$');
  if m is null or m[3]::int < 1990 or m[3]::int > 2100 then return null; end if;
  return make_date(m[3]::int, m[2]::int, m[1]::int);
exception when others then return null;
end $$;

-- name typed by the user -> registered workshop name ('' if not recognised or not unique), same idea as wsKey_
create or replace function public.tf_wskey(s text, wsl text[]) returns text language plpgsql immutable as
$$
declare t text := regexp_replace(upper(coalesce(s,'')), '[^A-Z0-9]', '', 'g'); t2 text; w text; k text; hit text[] := '{}';
begin
  if t = '' then return ''; end if;
  t2 := case when t ~ '^EW[CDS].' and length(t) > 5 then substr(t, 4) else t end;
  foreach w in array coalesce(wsl, '{}') loop
    if regexp_replace(upper(w), '[^A-Z0-9]', '', 'g') = t then return w; end if;
  end loop;
  foreach w in array coalesce(wsl, '{}') loop
    k := regexp_replace(upper(w), '[^A-Z0-9]', '', 'g');
    if (case when k ~ '^EW[CDS].' and length(k) > 5 then substr(k, 4) else k end) = t2 then return w; end if;
  end loop;
  foreach w in array coalesce(wsl, '{}') loop
    k := regexp_replace(upper(w), '[^A-Z0-9]', '', 'g'); k := case when k ~ '^EW[CDS].' and length(k) > 5 then substr(k, 4) else k end;
    if length(k) >= 3 and (position(k in t2) > 0 or (length(t2) >= 3 and position(t2 in k) > 0)) then hit := hit || w; end if;
  end loop;
  return case when array_length(hit, 1) = 1 then hit[1] else '' end;
end $$;

-- ---------- save ----------
create or replace function public.save_rows(p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as
$$
declare
  v_role text := public.my_role(); v_div text := public.my_division(); v_scope text[] := coalesce(public.my_workshops(), '{}');
  wsl text[]; one text;
  n int := 0; it jsonb; r text[]; o text[]; kk text[]; t text[]; cur text[];
  cols text[]; i int; why text; foreign_ boolean; kw text; ex public.data; sav public.data;
  added int := 0; updated int := 0; same int := 0; skipped int := 0; notes jsonb := '[]'::jsonb; keys jsonb := '[]'::jsonb; bad jsonb := '[]'::jsonb; rowsout jsonb := '{}'::jsonb;
  mob text; cname text[] := array['Workshop','DIVISION','SUBSTATION','FEEDER','PLACE OF DAMAGE','CAPACITY','Category','COMPLAIN NUMBER','PR NO','PR DATE','JE Name','JE Mobile','ISSUED TO FIRM','ISSUE DATE','DRIVER NAME','DRIVER MOBILE','REPLACEMENT DATE','TIME','RETURN DATE','REMARK'];
  dupf constant text := 'DUPLICATE/WRONG PR';
  newkey text; done boolean;
begin
  if not coalesce(public.my_can_edit(), false) or v_role not in ('admin','je') then raise exception 'You do not have permission to change data.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('added',0,'updated',0,'same',0,'skipped',0,'notes','[]'::jsonb,'keys','[]'::jsonb,'bad','[]'::jsonb,'rows','{}'::jsonb);
  end if;
  if jsonb_array_length(p_items) > 2000 then raise exception 'Too many rows in one call (maximum 2000).'; end if;
  select coalesce(array_agg(name order by name), '{}') into wsl from public.workshops where org_division = v_div;
  if array_length(v_scope, 1) = 1 then one := v_scope[1]; end if;

  for it in select * from jsonb_array_elements(p_items) loop
    n := n + 1; why := ''; foreign_ := false; done := false;
    -- the 20 values of the new row (trimmed)
    r := array(select btrim(replace(coalesce(x, ''), E' ', ' ')) from jsonb_array_elements_text(coalesce(it->'r', '[]'::jsonb)) x);
    while coalesce(array_length(r, 1), 0) < 20 loop r := r || ''::text; end loop;
    r[9] := case when r[9] ~ '^[0-9]+\.0+$' then split_part(r[9], '.', 1) else r[9] end;        -- PR no "123.0" -> "123"
    r[7] := ''; r[18] := '';                                                                      -- Category and TIME are not used any more
    if it->'o' is not null and jsonb_typeof(it->'o') = 'array' then
      o := array(select btrim(replace(coalesce(x, ''), E' ', ' ')) from jsonb_array_elements_text(it->'o') x);
      while coalesce(array_length(o, 1), 0) < 20 loop o := o || ''::text; end loop;
    else o := null; end if;
    if it->'k' is not null and jsonb_typeof(it->'k') = 'array' and jsonb_array_length(it->'k') = 2 then
      kk := array(select x from jsonb_array_elements_text(it->'k') x);
    else kk := null; end if;
    -- wrong / duplicate PR: no issue / replacement / return
    if public.is_dup(r[13]) then r[13] := dupf; r[14] := ''; r[15] := 'JE(D)'; r[16] := ''; r[17] := ''; r[19] := ''; end if;
    if r[1] = '' and one is not null then r[1] := one; end if;
    kw := public.tf_wskey(r[1], wsl); if kw <> '' then r[1] := kw; end if;

    if r[9] = '' then why := 'PR NO is empty';
    elsif public.tf_d(r[10]) is null then why := 'PR DATE is invalid/empty (DD.MM.YYYY required)';
    elsif kw = '' then why := 'Workshop is empty/not recognised (' || array_to_string(wsl, ' / ') || ')';
    elsif not (kw = any (v_scope)) then
      if kk is not null then why := 'WARNING - this row is for workshop "' || kw || '", but you can only save entries of ' || array_to_string(v_scope, ' / ') || '. It was NOT saved.';
      else foreign_ := true; end if;
    else
      foreach i in array array[10, 14, 17, 19] loop
        if r[i] <> '' and public.tf_d(r[i]) is null then why := cname[i] || ' date must be written as DD.MM.YYYY'; exit; end if;
      end loop;
    end if;
    if why = '' then
      foreach i in array array[12, 16] loop             -- mobiles: only what was changed in this save is checked
        if r[i] = '' or (o is not null and r[i] = o[i]) then continue; end if;
        mob := public.tf_mob(r[i]);
        if mob is null then why := cname[i] || ' must be 10 digits (E+ notation is not accepted)'; exit; end if;
        r[i] := mob;
      end loop;
    end if;

    if why = '' then
      select * into ex from public.data where workshop = r[1] and pr_no = r[9];
      if foreign_ and found then why := 'this PR already exists in workshop ' || kw || ' - skipped'; end if;
    end if;

    if why = '' and kk is not null then
      -- ---- edit of an existing row (kk = its old key) ----
      select * into ex from public.data where workshop = kk[1] and pr_no = kk[2];
      if not found then why := 'the old entry was not found (did someone delete it?)';
      elsif not (ex.workshop = any (v_scope)) then why := 'You do not have permission to change this entry';
      else
        cur := array(select jsonb_array_elements_text(public.row20(ex)));
        t := r;
        if o is not null then          -- only the cells the user changed are applied on the stored row
          t := cur;
          for i in 1..20 loop if r[i] <> o[i] then t[i] := r[i]; end if; end loop;
          if public.is_dup(t[13]) then t[13] := dupf; t[14] := ''; t[15] := 'JE(D)'; t[16] := ''; t[17] := ''; t[19] := ''; end if;
        end if;
        t[7] := ''; t[18] := '';
        newkey := t[1] || '|' || t[9];
        if newkey <> kk[1] || '|' || kk[2] and exists (select 1 from public.data where workshop = t[1] and pr_no = t[9]) then
          why := 'This PR NO already exists in this workshop';
        elsif not (t[1] = any (v_scope)) then why := 'You do not have permission to change this entry';
        else
          cols := t;
          if cols = cur then same := same + 1;
          else
            update public.data set workshop = t[1], division = t[2], substation = nullif(t[3], ''), feeder = nullif(t[4], ''), place_of_damage = nullif(t[5], ''),
                   capacity = nullif(public.tf_cap(t[6]), 0), complain_no = nullif(t[8], ''), pr_no = t[9], pr_date = public.tf_d(t[10]),
                   je_name = nullif(t[11], ''), je_mobile = nullif(t[12], ''), firm = nullif(t[13], ''), issue_date = public.tf_d(t[14]),
                   driver_name = nullif(t[15], ''), driver_mobile = nullif(t[16], ''), repl_date = public.tf_d(t[17]), return_date = public.tf_d(t[19]),
                   remark = nullif(t[20], ''), updated_at = now()
             where id = ex.id returning * into sav;
            updated := updated + 1;
          end if;
          done := true;
        end if;
      end if;
    elsif why = '' then
      select * into ex from public.data where workshop = r[1] and pr_no = r[9];
      if found then
        -- ---- PR already exists: only the non-empty cells are filled / changed ----
        if not (ex.workshop = any (v_scope)) then why := 'You do not have permission to change this entry';
        else
          cur := array(select jsonb_array_elements_text(public.row20(ex)));
          t := cur;
          for i in 1..20 loop if r[i] <> '' and r[i] <> cur[i] then t[i] := r[i]; end if; end loop;
          if public.is_dup(t[13]) then t[13] := dupf; t[14] := ''; t[15] := 'JE(D)'; t[16] := ''; t[17] := ''; t[19] := ''; end if;
          t[7] := ''; t[18] := '';
          if t = cur then same := same + 1;
          else
            update public.data set division = t[2], substation = nullif(t[3], ''), feeder = nullif(t[4], ''), place_of_damage = nullif(t[5], ''),
                   capacity = nullif(public.tf_cap(t[6]), 0), complain_no = nullif(t[8], ''), pr_date = public.tf_d(t[10]),
                   je_name = nullif(t[11], ''), je_mobile = nullif(t[12], ''), firm = nullif(t[13], ''), issue_date = public.tf_d(t[14]),
                   driver_name = nullif(t[15], ''), driver_mobile = nullif(t[16], ''), repl_date = public.tf_d(t[17]), return_date = public.tf_d(t[19]),
                   remark = nullif(t[20], ''), updated_at = now()
             where id = ex.id returning * into sav;
            updated := updated + 1;
          end if;
          t := t; done := true;
        end if;
      else
        -- ---- new row ----
        begin
          insert into public.data (workshop, division, substation, feeder, place_of_damage, capacity, complain_no, pr_no, pr_date, je_name, je_mobile, firm,
                                   issue_date, driver_name, driver_mobile, repl_date, return_date, remark)
          values (r[1], r[2], nullif(r[3], ''), nullif(r[4], ''), nullif(r[5], ''), nullif(public.tf_cap(r[6]), 0), nullif(r[8], ''), r[9], public.tf_d(r[10]),
                  nullif(r[11], ''), nullif(r[12], ''), nullif(r[13], ''), public.tf_d(r[14]), nullif(r[15], ''), nullif(r[16], ''), public.tf_d(r[17]), public.tf_d(r[19]), nullif(r[20], ''))
          returning * into sav;
          added := added + 1; t := r; done := true;
        exception when unique_violation then why := 'this PR already exists in workshop ' || kw || ' - skipped';
        end;
      end if;
    end if;

    if why <> '' then
      skipped := skipped + 1; bad := bad || to_jsonb(n - 1);
      if jsonb_array_length(notes) < 15 then notes := notes || to_jsonb('Line ' || n || ' (PR ' || coalesce(nullif(r[9], ''), '-') || '): ' || why); end if;
    elsif done then
      keys := keys || to_jsonb(coalesce(sav.workshop, t[1]) || '|' || coalesce(sav.pr_no, t[9]));
      if sav.id is not null and (sav.workshop = (case when kk is not null then t[1] else r[1] end)) then
        rowsout := rowsout || jsonb_build_object((n - 1)::text, public.row20(sav));
      end if;
    else   -- "same": nothing to write, the row is as it is
      keys := keys || to_jsonb(coalesce(t[1], r[1]) || '|' || coalesce(t[9], r[9]));
    end if;
    sav := null;
  end loop;

  return jsonb_build_object('added', added, 'updated', updated, 'same', same, 'skipped', skipped, 'notes', notes, 'keys', keys, 'bad', bad, 'rows', rowsout);
end $$;

-- ---------- delete (RLS decides who may delete what) ----------
create or replace function public.delete_pr(p_ws text, p_pr text) returns boolean
language plpgsql security invoker set search_path = public as
$$
declare c int;
begin
  delete from public.data where workshop = p_ws and pr_no = btrim(p_pr);
  get diagnostics c = row_count;
  if c = 0 then raise exception 'PR % not found, or you do not have permission to delete it.', p_pr; end if;
  return true;
end $$;

revoke all on function public.save_rows(jsonb) from public, anon;
grant execute on function public.save_rows(jsonb), public.delete_pr(text, text),
  public.tf_cap(text), public.tf_mob(text), public.tf_d(text), public.tf_wskey(text, text[]) to authenticated;

-- ################ from supabase-step14-spelling.sql ################
-- STEP 14: wrong spelling of a workshop (AZAMAGARH, BALIA ...) is counted as the right workshop.
-- Run ONCE in SQL Editor (after steps 10-13).  Safe to run again.
-- 1) the matching function now understands small spelling mistakes (also used when saving / pasting)
-- spelling distance of two short words (number of letters to add / remove / change)
create or replace function public.tf_lev(a text, b text) returns int language plpgsql immutable as
$$
declare la int := length(a); lb int := length(b); prev int[]; cur int[]; i int; j int; c int;
begin
  if la = 0 then return lb; end if; if lb = 0 then return la; end if;
  prev := array(select generate_series(0, lb));
  for i in 1..la loop
    cur := array[i];
    for j in 1..lb loop
      c := case when substr(a, i, 1) = substr(b, j, 1) then 0 else 1 end;
      cur := cur || least(prev[j + 1] + 1, cur[j] + 1, prev[j] + c);
    end loop;
    prev := cur;
  end loop;
  return prev[lb + 1];
end $$;

-- name typed by the user -> registered workshop name ('' if not recognised or not unique).
-- Also accepts small spelling mistakes (AZAMAGARH -> AZAMGARH, BALIA -> BALLIA): 1 wrong letter for 4-6 letters, 2 for 7 or more.
create or replace function public.tf_wskey(s text, wsl text[]) returns text language plpgsql immutable as
$$
declare t text := regexp_replace(upper(coalesce(s,'')), '[^A-Z0-9]', '', 'g'); t2 text; w text; k text; hit text[] := '{}'; d int; best int := 99; bw text := ''; nb int := 0; lim int;
begin
  if t = '' then return ''; end if;
  t2 := case when t ~ '^EW[CDS].' and length(t) > 5 then substr(t, 4) else t end;
  foreach w in array coalesce(wsl, '{}') loop
    if regexp_replace(upper(w), '[^A-Z0-9]', '', 'g') = t then return w; end if;
  end loop;
  foreach w in array coalesce(wsl, '{}') loop
    k := regexp_replace(upper(w), '[^A-Z0-9]', '', 'g');
    if (case when k ~ '^EW[CDS].' and length(k) > 5 then substr(k, 4) else k end) = t2 then return w; end if;
  end loop;
  foreach w in array coalesce(wsl, '{}') loop
    k := regexp_replace(upper(w), '[^A-Z0-9]', '', 'g'); k := case when k ~ '^EW[CDS].' and length(k) > 5 then substr(k, 4) else k end;
    if length(k) >= 3 and (position(k in t2) > 0 or (length(t2) >= 3 and position(t2 in k) > 0)) then hit := hit || w; end if;
  end loop;
  if array_length(hit, 1) = 1 then return hit[1]; end if;
  if array_length(hit, 1) > 1 then return ''; end if;
  -- spelling mistake: the single nearest workshop
  foreach w in array coalesce(wsl, '{}') loop
    k := regexp_replace(upper(w), '[^A-Z0-9]', '', 'g'); k := case when k ~ '^EW[CDS].' and length(k) > 5 then substr(k, 4) else k end;
    if length(k) < 4 or length(t2) < 4 then continue; end if;
    lim := case when least(length(k), length(t2)) >= 7 then 2 else 1 end;
    d := public.tf_lev(t2, k);
    if d <= lim then
      if d < best then best := d; bw := w; nb := 1; elsif d = best then nb := nb + 1; end if;
    end if;
  end loop;
  return case when nb = 1 then bw else '' end;
end $$;


-- 2) whatever way a row gets into the table, its workshop name is corrected to the registered one
create or replace function public.tf_fix_ws() returns trigger language plpgsql security definer set search_path = public as
$$
declare k text;
begin
  if new.workshop is not null and not exists (select 1 from public.workshops where name = new.workshop) then
    k := public.tf_wskey(new.workshop, array(select name from public.workshops));
    if k <> '' then new.workshop := k; end if;
  end if;
  return new;
end $$;
drop trigger if exists tf_fix_ws on public.data;
create trigger tf_fix_ws before insert or update of workshop on public.data for each row execute function public.tf_fix_ws();

-- 3) rows that are ALREADY in the table with a wrong spelling (they are invisible to users now) are corrected
update public.data d set workshop = x.k
  from (select distinct on (w.workshop) w.workshop as bad, public.tf_wskey(w.workshop, array(select name from public.workshops)) as k
          from (select distinct workshop from public.data where workshop not in (select name from public.workshops)) w) x
 where d.workshop = x.bad and x.k <> ''
   and not exists (select 1 from public.data e where e.workshop = x.k and e.pr_no = d.pr_no);

-- 4) what is still not recognised (fix by hand, or tell Claude):
select workshop, count(*) as rows_left from public.data where workshop not in (select name from public.workshops) group by 1 order by 2 desc;

-- ################ from supabase-step15-compare.sql ################
-- TF-Tracker : STEP 15 - Comparison tab (Admin only) + automatic delete of data older than 2 years 2 months.
-- Run ONCE in Supabase > SQL Editor (after steps 1-14).  Part A and B are safe to run again.  Part C (the nightly delete) is OPTIONAL and cannot be undone.

-- ============================================================ A) numbers for the Comparison tab
-- compare_fmt: PR counts (by PR DATE) per workshop / division / capacity for [p_from, p_to] ('c' = this year)
-- and for the SAME dates one year earlier ('p').  Wrong / duplicate PRs are not counted (same rule as the Summary).
-- SECURITY INVOKER: the row level security decides which workshops the caller sees (an Admin: only his own division).
create or replace function public.compare_fmt(p_from date, p_to date)
returns jsonb language sql stable security invoker set search_path = public as
$$
  with w as (select p_from as f, p_to as t, (p_from - interval '1 year')::date as pf, (p_to - interval '1 year')::date as pt),
  x as (
    select 'c'::text as period, d.workshop, d.division, d.capacity from public.data d, w where not d.dup and d.pr_date between w.f  and w.t
    union all
    select 'p',                 d.workshop, d.division, d.capacity from public.data d, w where not d.dup and d.pr_date between w.pf and w.pt
  )
  select coalesce(jsonb_agg(jsonb_build_array(period, workshop, dv, cap, n)), '[]'::jsonb)
    from (select period, workshop, upper(btrim(regexp_replace(coalesce(division,''), '\s+', ' ', 'g'))) as dv, coalesce(capacity, 0) as cap, count(*) as n
            from x group by 1, 2, 3, 4 order by 1, 2, 3, 4) q
$$;

-- ============================================================ B) "Install on 01.04.YYYY" numbers (typed by the Admin in the Comparison tab)
create table if not exists public.installed (
  org_division text not null,
  div_key      text not null,            -- division name without spaces / dots, capital letters (example EEEDDIAZAMGARH)
  yr           int  not null check (yr between 2000 and 2100),   -- the year of 01.04.<yr>
  qty          int  not null check (qty >= 0),
  primary key (org_division, div_key, yr)
);
alter table public.installed enable row level security;
revoke all on public.installed from anon, authenticated;       -- the browser never touches the table: only the two functions below

create or replace function public.installed_json() returns jsonb
language sql stable security definer set search_path = public as
$$
  select coalesce(jsonb_agg(jsonb_build_array(i.div_key, i.yr, i.qty)), '[]'::jsonb)
    from public.installed i join public.profiles p on p.user_id = auth.uid() and p.active and p.role = 'admin' and p.org_division = i.org_division
$$;

create or replace function public.set_installed(p_key text, p_yr int, p_qty int) returns text
language plpgsql security definer set search_path = public as
$$
declare c public.profiles := public.tf_caller(); k text := upper(regexp_replace(coalesce(p_key,''), '[^A-Za-z0-9]', '', 'g'));
begin
  if c.user_id is null or c.role <> 'admin' or c.org_division is null then raise exception 'Only an Admin can change the installed numbers.'; end if;
  if k = '' or length(k) > 80 then raise exception 'Bad division.'; end if;
  if p_yr is null or p_yr not between 2000 and 2100 then raise exception 'Bad year.'; end if;
  if p_qty is null or p_qty < 0 then
    delete from public.installed where org_division = c.org_division and div_key = k and yr = p_yr;     -- empty box = remove
    return 'OK';
  end if;
  insert into public.installed (org_division, div_key, yr, qty) values (c.org_division, k, p_yr, p_qty)
  on conflict (org_division, div_key, yr) do update set qty = excluded.qty;
  return 'OK';
end $$;

revoke all on function public.installed_json(), public.set_installed(text, int, int) from public, anon;
grant execute on function public.compare_fmt(date, date), public.installed_json(), public.set_installed(text, int, int) to authenticated;

-- (part C of step 15, the nightly auto-delete of old data, is NOT included.)

-- ################ from supabase-step16-pendency.sql ################
-- TF-Tracker : STEP 16 - "Last month pendency" no longer counts a transformer that is ALREADY FITTED.
-- Before: a PR raised before the From date and issued on / after the From date stayed in "Last month pendency" even after it was fitted
--         (it was a snapshot of the From date).  Now: such a PR leaves the pendency as soon as its REPLACEMENT DATE is filled.
-- This changes both the number in the Summary and the list that opens by a click on it, so they stay equal.
-- Run ONCE in Supabase > SQL Editor.  Safe to run again.  No data is changed.

create or replace function public.summary_agg(p_date date, p_from date, p_to date)
returns table(workshop text, division text, capacity int,
              m0 bigint, m1 bigint, m2 bigint, m3 bigint, m4 bigint, m5 bigint, m6 bigint, m7 bigint,
              m8 bigint, m9 bigint, m10 bigint, m11 bigint, m12 bigint, m13 bigint, m14 bigint)
language sql stable security invoker set search_path = public as
$$
  with r as (
    select d.workshop,
           upper(btrim(regexp_replace(coalesce(d.division,''), '\s+', ' ', 'g'))) as division,
           coalesce(d.capacity, 0) as capacity,
           d.dup as dup,
           coalesce(d.pr_date, date '1900-01-01') as pr,      -- no PR date = "0" in the old code (older than everything)
           d.issue_date as i, d.repl_date as p, d.return_date as t
    from public.data d
  )
  select r.workshop, r.division, r.capacity,
    count(*) filter (where not dup and pr < p_from and (i is null or i >= p_from) and (t is null or t > p_from - 1) and p is null),                                  -- 0
    count(*) filter (where not dup and pr = p_date),                                                                                                   -- 1
    count(*) filter (where not dup and pr = p_date and i is not null),                                                                                 -- 2
    count(*) filter (where not dup and pr = p_date and p is not null),                                                                                 -- 3
    count(*) filter (where not dup and i = p_date),                                                                                                    -- 4
    count(*) filter (where not dup and p = p_date),                                                                                                    -- 5
    count(*) filter (where not dup and pr between p_from and p_to),                                                                                    -- 6
    count(*) filter (where not dup and i between p_from and p_to),                                                                                     -- 7
    count(*) filter (where not dup and p between p_from and p_to),                                                                                     -- 8
    count(*) filter (where not dup and pr <= p_to and (i is null or i > p_to) and (t is null or t > p_to)),                                            -- 9
    count(*) filter (where not dup and i is not null and i <= p_to and (p is null or p > p_to) and (t is null or t > p_to)),                           -- 10
    count(*) filter (where not dup and t = p_date),                                                                                                    -- 11
    count(*) filter (where not dup and t between p_from and p_to),                                                                                     -- 12
    count(*) filter (where not dup and p is not null and p <= p_to and (t is null or t > p_to)),                                                       -- 13
    count(*) filter (where dup and pr between p_from and p_to)                                                                                         -- 14
  from r
  group by r.workshop, r.division, r.capacity
  order by 1, 2, 3
$$;

-- pending for issue, date wise (PR date) x capacity, per workshop  (metric 9 only)

create or replace function public.list_json(p_metric int, p_date date, p_from date, p_to date,
                                            p_ws text default null, p_divs text[] default null, p_subs text[] default null,
                                            p_caps int[] default null, p_prd date default null,
                                            p_limit int default 300, p_offset int default 0,
                                            p_prd_from date default null, p_prd_to date default null)
returns jsonb language sql stable security invoker set search_path = public as
$$
  with r as (
    select d.*, coalesce(d.pr_date, date '1900-01-01') as pr
      from public.data d
     where (p_ws is null or d.workshop = p_ws)
       and (p_caps is null or coalesce(d.capacity, 0) = any (p_caps))
       and (p_divs is null or upper(btrim(regexp_replace(coalesce(d.division,''),  '\s+', ' ', 'g'))) = any (p_divs))
       and (p_subs is null or upper(btrim(regexp_replace(coalesce(d.substation,''),'\s+', ' ', 'g'))) = any (p_subs))
       and (p_prd is null or d.pr_date = p_prd)
       and (p_prd_from is null or coalesce(d.pr_date, date '1900-01-01') >= p_prd_from)
       and (p_prd_to   is null or coalesce(d.pr_date, date '1900-01-01') <= p_prd_to)
  ), h as (
    select r.*,
      case when r.dup then (p_metric = 14 and r.pr between p_from and p_to)
      else case p_metric
        when 0  then r.pr < p_from and (r.issue_date is null or r.issue_date >= p_from) and (r.return_date is null or r.return_date > p_from - 1) and r.repl_date is null
        when 1  then r.pr = p_date
        when 2  then r.pr = p_date and r.issue_date is not null
        when 3  then r.pr = p_date and r.repl_date is not null
        when 4  then r.issue_date = p_date
        when 5  then r.repl_date = p_date
        when 6  then r.pr between p_from and p_to
        when 7  then r.issue_date between p_from and p_to
        when 8  then r.repl_date between p_from and p_to
        when 9  then r.pr <= p_to and (r.issue_date is null or r.issue_date > p_to) and (r.return_date is null or r.return_date > p_to)
        when 10 then r.issue_date is not null and r.issue_date <= p_to and (r.repl_date is null or r.repl_date > p_to) and (r.return_date is null or r.return_date > p_to)
        when 11 then r.return_date = p_date
        when 12 then r.return_date between p_from and p_to
        when 13 then r.repl_date is not null and r.repl_date <= p_to and (r.return_date is null or r.return_date > p_to)
        else false end
      end as hit
    from r
  ), top as (
    select d.* from public.data d
      join (select id from h where hit order by pr, pr_no collate "C" limit least(greatest(p_limit, 1), 2000) offset greatest(p_offset, 0)) k on k.id = d.id
  )
  select jsonb_build_object(
    'total', (select count(*) from h where hit),
    'rows', coalesce((select jsonb_agg(public.row20(t) || to_jsonb((select case when public.can_edit_rows() then 1 else 0 end)) order by coalesce(t.pr_date, date '1900-01-01'), t.pr_no collate "C") from top t), '[]'::jsonb))
$$;

-- ################ from supabase-step17-dashboard.sql ################
-- TF-Tracker : STEP 17 - numbers for the Dashboard (icon in the Summary toolbar).
-- Run ONCE in Supabase > SQL Editor.  Safe to run again.  No data is changed.
--
-- The Dashboard follows the PRs RAISED between From and To (by PR DATE) and says how far they have travelled by the To date:
--   total      = PRs raised in the period            (wrong / duplicate PRs not counted, same rule as the Summary)
--   issued     = of them, ISSUE DATE on or before To
--   replaced   = of them, REPLACEMENT DATE on or before To
--   returned   = of them, RETURN DATE on or before To
--   pend_issue = not issued yet
--   pend_repl  = issued, replacement not done yet
--   pend_ret   = replaced, old transformer not returned yet
-- (So these numbers are about the PRs of the period. They are NOT the same as the TOTAL ISSUE / TOTAL REPLACEMENT columns of the
--  Summary, which count the issues / replacements that happened in the period, whatever the PR date was.)
-- SECURITY INVOKER: row level security decides which workshops the caller sees (JE: his own, Admin: his division, DISCOM: all).

create or replace function public.dashboard_json(p_from date, p_to date)
returns jsonb language sql stable security invoker set search_path = public as
$$
  select coalesce(jsonb_agg(jsonb_build_array(workshop, total, issued, replaced, returned, pend_issue, pend_repl, pend_ret) order by workshop), '[]'::jsonb)
    from (
      select d.workshop,
             count(*)                                                                                                         as total,
             count(*) filter (where d.issue_date  is not null and d.issue_date  <= p_to)                                       as issued,
             count(*) filter (where d.repl_date   is not null and d.repl_date   <= p_to)                                       as replaced,
             count(*) filter (where d.return_date is not null and d.return_date <= p_to)                                       as returned,
             count(*) filter (where d.issue_date is null or d.issue_date > p_to)                                               as pend_issue,
             count(*) filter (where d.issue_date <= p_to and (d.repl_date is null or d.repl_date > p_to))                      as pend_repl,
             count(*) filter (where d.repl_date <= p_to and (d.return_date is null or d.return_date > p_to))                   as pend_ret
        from public.data d
       where not d.dup and d.pr_date between p_from and p_to
       group by d.workshop
    ) q
$$;
grant execute on function public.dashboard_json(date, date) to authenticated;

-- ################ from supabase-step22-compare-all.sql ################
-- TF-Tracker : STEP 22 - the Comparison tab for EVERY login (Admin, JE, DISCOM), with a Workshop filter.
-- Run ONCE in Supabase > SQL Editor.  Safe to run again.  No data is changed.
--
-- WHY a new function: the normal data rules (row level security) show a JE only his own workshop.  For the Comparison everybody should see
-- the whole organisation, so these two functions are SECURITY DEFINER.  They return only COUNTS (PRs per workshop / division / capacity)
-- and the "Install on 01.04.YYYY" numbers - never a PR number, place, JE name or mobile number.
--   Admin / JE : the whole organisation (division) he belongs to.     DISCOM / Creator : every organisation.
--   Anybody else (or a deactivated login) gets an error.
-- Typing the Install numbers stays Admin only (set_installed from step 15 is not changed).

-- Comparison history: when the weekly job deletes old PRs (older than 3 years), their DAILY counts (workshop, division, capacity, PR date) are kept here,
-- so the Comparison tab can still compare any old period.  Tiny table (about 10 rows per workshop and day).  No PR details are kept.
create table if not exists public.cmp_hist (
  workshop text not null, division text not null, capacity int not null, d date not null, n int not null check (n > 0),
  primary key (workshop, division, capacity, d)
);
alter table public.cmp_hist enable row level security;
revoke all on public.cmp_hist from public, anon, authenticated;

create or replace function public.compare_all(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as
$$
declare c public.profiles := public.tf_caller(); r jsonb;
begin
  if c.user_id is null or not c.active or c.role not in ('admin', 'je', 'discom', 'creator') then raise exception 'Not allowed.'; end if;
  with w as (select p_from as f, p_to as t, (p_from - interval '1 year')::date as pf, (p_to - interval '1 year')::date as pt),
  dd as (
    select d.* from public.data d
     where not d.dup
       and (c.role in ('discom', 'creator') or c.org_division is null
            or d.workshop in (select name from public.workshops where org_division = c.org_division))
  ),
  hh as (          -- deleted (old) PRs, counted per day; a day that has live PRs again is taken from the live data only
    select h.* from public.cmp_hist h
     where not exists (select 1 from public.data x where x.pr_date = h.d)
       and (c.role in ('discom', 'creator') or c.org_division is null
            or h.workshop in (select name from public.workshops where org_division = c.org_division))
  ),
  x as (
    select 'c'::text as period, d.workshop, d.division, d.capacity, 1 as n from dd d, w where d.pr_date between w.f  and w.t
    union all
    select 'p',                 d.workshop, d.division, d.capacity, 1 from dd d, w where d.pr_date between w.pf and w.pt
    union all
    select 'c', h.workshop, h.division, h.capacity, h.n from hh h, w where h.d between w.f  and w.t
    union all
    select 'p', h.workshop, h.division, h.capacity, h.n from hh h, w where h.d between w.pf and w.pt
  )
  select coalesce(jsonb_agg(jsonb_build_array(period, workshop, dv, cap, n)), '[]'::jsonb) into r
    from (select period, workshop, upper(btrim(regexp_replace(coalesce(division,''), '\s+', ' ', 'g'))) as dv, coalesce(capacity, 0) as cap, sum(n)::bigint as n
            from x group by 1, 2, 3, 4 order by 1, 2, 3, 4) q;
  return r;
end $$;

create or replace function public.installed_all_json() returns jsonb
language plpgsql stable security definer set search_path = public as
$$
declare c public.profiles := public.tf_caller(); r jsonb;
begin
  if c.user_id is null or not c.active or c.role not in ('admin', 'je', 'discom', 'creator') then raise exception 'Not allowed.'; end if;
  select coalesce(jsonb_agg(jsonb_build_array(i.div_key, i.yr, i.qty)), '[]'::jsonb) into r
    from public.installed i
   where c.role in ('discom', 'creator') or c.org_division is null or i.org_division = c.org_division;
  return r;
end $$;

revoke all on function public.compare_all(date, date), public.installed_all_json() from public, anon;
grant execute on function public.compare_all(date, date), public.installed_all_json() to authenticated;

-- ################ from supabase-step30-pending-return.sql ################
-- TF-Tracker : STEP 30 - PENDING FOR RETURN = the PR has an ISSUE DATE but no RETURN DATE (by the To date). Wrong / duplicate PRs are never counted.
-- (Before: the replacement date also had to be filled.)  Changes the Summary numbers, the list behind them, the Capacity table and the Dashboard.
-- Run ONCE in Supabase > SQL Editor (after step 16, 17 and 22).  Safe to run again.  No data is changed.

create or replace function public.summary_agg(p_date date, p_from date, p_to date)
returns table(workshop text, division text, capacity int,
              m0 bigint, m1 bigint, m2 bigint, m3 bigint, m4 bigint, m5 bigint, m6 bigint, m7 bigint,
              m8 bigint, m9 bigint, m10 bigint, m11 bigint, m12 bigint, m13 bigint, m14 bigint)
language sql stable security invoker set search_path = public as
$$
  with r as (
    select d.workshop,
           upper(btrim(regexp_replace(coalesce(d.division,''), '\s+', ' ', 'g'))) as division,
           coalesce(d.capacity, 0) as capacity,
           d.dup as dup,
           coalesce(d.pr_date, date '1900-01-01') as pr,      -- no PR date = "0" in the old code (older than everything)
           d.issue_date as i, d.repl_date as p, d.return_date as t
    from public.data d
  )
  select r.workshop, r.division, r.capacity,
    count(*) filter (where not dup and pr < p_from and (i is null or i >= p_from) and (t is null or t > p_from - 1) and p is null),                                  -- 0
    count(*) filter (where not dup and pr = p_date),                                                                                                   -- 1
    count(*) filter (where not dup and pr = p_date and i is not null),                                                                                 -- 2
    count(*) filter (where not dup and pr = p_date and p is not null),                                                                                 -- 3
    count(*) filter (where not dup and i = p_date),                                                                                                    -- 4
    count(*) filter (where not dup and p = p_date),                                                                                                    -- 5
    count(*) filter (where not dup and pr between p_from and p_to),                                                                                    -- 6
    count(*) filter (where not dup and i between p_from and p_to),                                                                                     -- 7
    count(*) filter (where not dup and p between p_from and p_to),                                                                                     -- 8
    count(*) filter (where not dup and pr <= p_to and (i is null or i > p_to) and (t is null or t > p_to)),                                            -- 9
    count(*) filter (where not dup and i is not null and i <= p_to and (p is null or p > p_to) and (t is null or t > p_to)),                           -- 10
    count(*) filter (where not dup and t = p_date),                                                                                                    -- 11
    count(*) filter (where not dup and t between p_from and p_to),                                                                                     -- 12
    count(*) filter (where not dup and i is not null and i <= p_to and (t is null or t > p_to)),                                                       -- 13
    count(*) filter (where dup and pr between p_from and p_to)                                                                                         -- 14
  from r
  group by r.workshop, r.division, r.capacity
  order by 1, 2, 3
$$;

-- pending for issue, date wise (PR date) x capacity, per workshop  (metric 9 only)

create or replace function public.list_json(p_metric int, p_date date, p_from date, p_to date,
                                            p_ws text default null, p_divs text[] default null, p_subs text[] default null,
                                            p_caps int[] default null, p_prd date default null,
                                            p_limit int default 300, p_offset int default 0,
                                            p_prd_from date default null, p_prd_to date default null)
returns jsonb language sql stable security invoker set search_path = public as
$$
  with r as (
    select d.*, coalesce(d.pr_date, date '1900-01-01') as pr
      from public.data d
     where (p_ws is null or d.workshop = p_ws)
       and (p_caps is null or coalesce(d.capacity, 0) = any (p_caps))
       and (p_divs is null or upper(btrim(regexp_replace(coalesce(d.division,''),  '\s+', ' ', 'g'))) = any (p_divs))
       and (p_subs is null or upper(btrim(regexp_replace(coalesce(d.substation,''),'\s+', ' ', 'g'))) = any (p_subs))
       and (p_prd is null or d.pr_date = p_prd)
       and (p_prd_from is null or coalesce(d.pr_date, date '1900-01-01') >= p_prd_from)
       and (p_prd_to   is null or coalesce(d.pr_date, date '1900-01-01') <= p_prd_to)
  ), h as (
    select r.*,
      case when r.dup then (p_metric = 14 and r.pr between p_from and p_to)
      else case p_metric
        when 0  then r.pr < p_from and (r.issue_date is null or r.issue_date >= p_from) and (r.return_date is null or r.return_date > p_from - 1) and r.repl_date is null
        when 1  then r.pr = p_date
        when 2  then r.pr = p_date and r.issue_date is not null
        when 3  then r.pr = p_date and r.repl_date is not null
        when 4  then r.issue_date = p_date
        when 5  then r.repl_date = p_date
        when 6  then r.pr between p_from and p_to
        when 7  then r.issue_date between p_from and p_to
        when 8  then r.repl_date between p_from and p_to
        when 9  then r.pr <= p_to and (r.issue_date is null or r.issue_date > p_to) and (r.return_date is null or r.return_date > p_to)
        when 10 then r.issue_date is not null and r.issue_date <= p_to and (r.repl_date is null or r.repl_date > p_to) and (r.return_date is null or r.return_date > p_to)
        when 11 then r.return_date = p_date
        when 12 then r.return_date between p_from and p_to
        when 13 then r.issue_date is not null and r.issue_date <= p_to and (r.return_date is null or r.return_date > p_to)
        else false end
      end as hit
    from r
  ), top as (
    select d.* from public.data d
      join (select id from h where hit order by pr, pr_no collate "C" limit least(greatest(p_limit, 1), 2000) offset greatest(p_offset, 0)) k on k.id = d.id
  )
  select jsonb_build_object(
    'total', (select count(*) from h where hit),
    'rows', coalesce((select jsonb_agg(public.row20(t) || to_jsonb((select case when public.can_edit_rows() then 1 else 0 end)) order by coalesce(t.pr_date, date '1900-01-01'), t.pr_no collate "C") from top t), '[]'::jsonb))
$$;

create or replace function public.dashboard_json(p_from date, p_to date)
returns jsonb language sql stable security invoker set search_path = public as
$$
  select coalesce(jsonb_agg(jsonb_build_array(workshop, total, issued, replaced, returned, pend_issue, pend_repl, pend_ret) order by workshop), '[]'::jsonb)
    from (
      select d.workshop,
             count(*)                                                                                                         as total,
             count(*) filter (where d.issue_date  is not null and d.issue_date  <= p_to)                                       as issued,
             count(*) filter (where d.repl_date   is not null and d.repl_date   <= p_to)                                       as replaced,
             count(*) filter (where d.return_date is not null and d.return_date <= p_to)                                       as returned,
             count(*) filter (where d.issue_date is null or d.issue_date > p_to)                                               as pend_issue,
             count(*) filter (where d.issue_date <= p_to and (d.repl_date is null or d.repl_date > p_to))                      as pend_repl,
             count(*) filter (where d.issue_date <= p_to and (d.return_date is null or d.return_date > p_to))                   as pend_ret
        from public.data d
       where not d.dup and d.pr_date between p_from and p_to
       group by d.workshop
    ) q
$$;
grant execute on function public.dashboard_json(date, date) to authenticated;

-- ################ from supabase-step31-pr-search.sql ################
-- TF-Tracker : STEP 31 - PR / Complaint search on the LOGIN page (no login needed).
-- Run ONCE in Supabase > SQL Editor.  Safe to run again.  No data is changed.
--
-- One person types ONE full PR number or complaint number and gets that PR's position + repeated-damage history (same workshop,
-- same place of damage, same capacity) + JE / driver names with mobile numbers (so they can be called).
-- Safety: the table itself stays closed (RLS).  Only this function is open to the login page, and it
--   * accepts only an EXACT PR / complaint number of 6 to 30 characters (no wildcard, no list, no browsing),
--   * returns at most 5 matching PRs and at most 12 history lines,
--   * never returns remarks.
-- To HIDE the mobile numbers on the login page, change   show_mob boolean := true;   to   false   below and run this step again.

create or replace function public.pr_lookup(p_q text)
returns jsonb language plpgsql stable security definer set search_path = public as
$$
declare
  q        text    := upper(btrim(coalesce(p_q, '')));
  show_mob boolean := true;
  out      jsonb;
begin
  if length(q) < 6 or length(q) > 30 or q !~ '^[A-Z0-9/ ._-]+$' then
    return jsonb_build_object('error', 'Type the full PR number or complaint number (at least 6 characters).');
  end if;
  select coalesce(jsonb_agg(x order by x->>'sort' desc), '[]'::jsonb) into out
  from (
    select jsonb_build_object(
      'sort', coalesce(to_char(d.pr_date, 'YYYYMMDD'), ''),
      'pr', d.pr_no, 'complain', d.complain_no, 'workshop', d.workshop, 'division', d.division, 'substation', d.substation,
      'feeder', d.feeder, 'place', d.place_of_damage, 'cap', d.capacity,
      'pr_date', to_char(d.pr_date, 'DD.MM.YYYY'), 'issue', to_char(d.issue_date, 'DD.MM.YYYY'),
      'repl', to_char(d.repl_date, 'DD.MM.YYYY'), 'ret', to_char(d.return_date, 'DD.MM.YYYY'),
      'dup', d.dup, 'firm', d.firm,
      'je', d.je_name, 'je_mob', case when show_mob then d.je_mobile else null end,
      'drv', d.driver_name, 'drv_mob', case when show_mob then d.driver_mobile else null end,
      'hist', case when btrim(coalesce(d.place_of_damage, '')) = '' or d.dup then '[]'::jsonb else coalesce((
         select jsonb_agg(jsonb_build_object('pr', h.pr_no, 'pr_date', to_char(h.pr_date, 'DD.MM.YYYY'), 'cap', h.capacity,
                  'issue', to_char(h.issue_date, 'DD.MM.YYYY'), 'repl', to_char(h.repl_date, 'DD.MM.YYYY')) order by h.pr_date, h.pr_no)
           from (select * from public.data h0
                  where h0.workshop = d.workshop and not h0.dup
                    and upper(btrim(regexp_replace(coalesce(h0.place_of_damage, ''), '\s+', ' ', 'g'))) = upper(btrim(regexp_replace(d.place_of_damage, '\s+', ' ', 'g')))
                    and coalesce(h0.capacity, 0) = coalesce(d.capacity, 0)
                  order by h0.pr_date, h0.pr_no limit 12) h), '[]'::jsonb) end
    ) as x
    from public.data d
    where upper(btrim(d.pr_no)) = q or upper(btrim(coalesce(d.complain_no, ''))) = q
    order by d.pr_date desc nulls last
    limit 5
  ) s;
  if jsonb_array_length(out) = 0 then
    return jsonb_build_object('rows', '[]'::jsonb);
  end if;
  return jsonb_build_object('rows', (select coalesce(jsonb_agg(e - 'sort'), '[]'::jsonb) from jsonb_array_elements(out) e));
end
$$;

revoke all on function public.pr_lookup(text) from public;
grant execute on function public.pr_lookup(text) to anon, authenticated;

-- ################ from supabase-step32-pr-find.sql ################
-- TF-Tracker : STEP 32 - the login-page search now also finds by PLACE OF DAMAGE and by the FIRST 4+ characters of a PR / complaint number.
-- Run ONCE in Supabase > SQL Editor (after step 31).  Safe to run again.  No data is changed.
--
-- pr_find(text) gives only a SHORT LIST (PR, complaint, place, capacity, date, status) - NO mobile numbers, NO names.
-- The person taps one line and the page then asks pr_lookup (step 31) for that ONE PR, which gives the full card and the Call buttons.
-- Safety: at least 4 characters, at most 15 lines, no wildcard characters, table stays closed (RLS).

create or replace function public.pr_find(p_q text)
returns jsonb language plpgsql stable security definer set search_path = public as
$$
declare
  q   text := upper(btrim(regexp_replace(coalesce(p_q, ''), '\s+', ' ', 'g')));
  e   text;
  out jsonb;
begin
  if length(q) < 4 or length(q) > 40 or q !~ '^[A-Z0-9/ ._()-]+$' then
    return jsonb_build_object('error', 'Type at least 4 letters or digits.');
  end if;
  e := replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_');
  select coalesce(jsonb_agg(x order by x->>'sort' desc), '[]'::jsonb) into out
  from (
    select jsonb_build_object(
      'sort', coalesce(to_char(d.pr_date, 'YYYYMMDD'), '') || d.pr_no,
      'pr', d.pr_no, 'complain', d.complain_no, 'workshop', d.workshop, 'place', d.place_of_damage, 'substation', d.substation,
      'cap', d.capacity, 'pr_date', to_char(d.pr_date, 'DD.MM.YYYY'), 'dup', d.dup,
      'st', case when d.dup then 'D' when d.repl_date is not null then 'R' when d.issue_date is not null then 'I' else 'P' end) as x
    from public.data d
    where upper(btrim(d.pr_no)) like e || '%' escape '\'
       or upper(btrim(coalesce(d.complain_no, ''))) like e || '%' escape '\'
       or upper(coalesce(d.place_of_damage, '')) like '%' || e || '%' escape '\'
    order by d.pr_date desc nulls last
    limit 15
  ) s;
  return jsonb_build_object('rows', (select coalesce(jsonb_agg(v - 'sort'), '[]'::jsonb) from jsonb_array_elements(out) v));
end
$$;
revoke all on function public.pr_find(text) from public;
grant execute on function public.pr_find(text) to anon, authenticated;

-- ################ from supabase-step33-emergency.sql ################
-- TF-Tracker : STEP 33 - EMERGENCY tab + siren.
-- Run ONCE in Supabase > SQL Editor (after steps 1-32).  Safe to run again.  Nothing in your existing data is changed.
--
-- How it works
--   * Anyone who may use the Emergency tab (a user whose "tabs" is empty = all tabs, or contains 'emg') can ADD an emergency:
--     refer by, village, mobile / complaint no., other detail and the workshop it is referred to ("Nodal").
--     To make a Nodal login: Admin tab > create a user, tick only "Emergency" in the tabs.
--   * The JE / Admin (with Can edit) of that workshop types the PR NO and a remark.  Everything else is copied LIVE from the Data Sheet
--     (same workshop + same PR no.), so it follows every change made in the Data Sheet.
--   * Status:  no PR no. / PR not found / issue date empty = RED   |   issue date filled = GREEN   |   replacement date filled = DONE.
--     A DONE line leaves the Emergency tab 2 days after the replacement date (the PR stays in the Data Sheet).
--   * Everything goes through the functions below (the table itself is closed).

create table if not exists public.emergency (
  id          bigint generated always as identity primary key,
  refer_by    text,
  village     text,
  mobile      text,
  detail      text,
  workshop    text not null,
  remark      text,
  pr_no       text,
  created_by  uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists emergency_ws on public.emergency (workshop);
alter table public.emergency enable row level security;
revoke all on public.emergency from anon, authenticated;

-- may this person use the Emergency tab?
create or replace function public.emg_ok() returns boolean language sql stable security definer set search_path = public as
$$ select coalesce((select p.tabs is null or 'emg' = any(p.tabs) from public.profiles p where p.user_id = auth.uid() and p.active), false) $$;

-- the workshops he may refer an emergency to (his own division; DISCOM / creator: all)
create or replace function public.emg_workshops() returns text[] language sql stable security definer set search_path = public as
$$
  select case
    when not public.emg_ok() then '{}'::text[]
    when public.my_role() in ('creator', 'discom') then array(select name from public.workshops order by name)
    else array(select w.name from public.workshops w
                where w.org_division in (select w2.org_division from public.workshops w2 where w2.name = any (coalesce(public.my_workshops(), '{}')))
                order by w.name)
  end
$$;

-- the list (with the Data Sheet columns of the PR)
create or replace function public.emg_json() returns jsonb language plpgsql stable security definer set search_path = public as
$$
declare
  mine  text[]  := coalesce(public.my_workshops(), '{}');
  ed    boolean := public.my_can_edit() and public.my_role() in ('admin', 'je');
  adm   boolean := public.my_role() in ('admin', 'creator');
  me    uuid    := auth.uid();
  today date    := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not public.emg_ok() then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(x order by x->>'sort' desc) from (
      select jsonb_build_object(
        'sort', to_char(e.created_at, 'YYYYMMDDHH24MISS') || lpad(e.id::text, 10, '0'),
        'id', e.id, 'by', e.refer_by, 'village', e.village, 'mobile', e.mobile, 'detail', e.detail, 'ws', e.workshop,
        'remark', e.remark, 'pr', e.pr_no,
        'created', to_char(e.created_at at time zone 'Asia/Kolkata', 'DD.MM.YYYY HH24:MI'),
        'can_edit', ed and e.workshop = any (mine),
        'can_del',  (e.created_by = me) or (adm and e.workshop = any (mine)),
        'found', d.id is not null, 'dup', coalesce(d.dup, false),
        'st', case when d.id is null or coalesce(d.dup, false) then 'R0'
                   when d.repl_date is not null then 'D'
                   when d.issue_date is not null then 'G'
                   else 'R1' end,
        'left', case when d.repl_date is not null then d.repl_date + 2 - today end,
        'pr_date', to_char(d.pr_date, 'DD.MM.YYYY'), 'division', d.division, 'substation', d.substation, 'feeder', d.feeder,
        'place', d.place_of_damage, 'cap', d.capacity, 'complain', d.complain_no,
        'je', d.je_name, 'je_mob', d.je_mobile, 'firm', d.firm,
        'issue', to_char(d.issue_date, 'DD.MM.YYYY'), 'drv', d.driver_name, 'drv_mob', d.driver_mobile,
        'repl', to_char(d.repl_date, 'DD.MM.YYYY')
      ) as x
      from public.emergency e
      left join lateral (
        select d0.* from public.data d0
         where btrim(coalesce(e.pr_no, '')) <> '' and d0.workshop = e.workshop and upper(btrim(d0.pr_no)) = upper(btrim(e.pr_no))
         limit 1) d on true
      where (e.workshop = any (mine) or e.created_by = me)
        and not (d.repl_date is not null and d.repl_date + 2 <= today)
    ) s), '[]'::jsonb);
end
$$;

-- add (Nodal)
create or replace function public.emg_add(p_by text, p_village text, p_mob text, p_detail text, p_ws text) returns bigint
language plpgsql security definer set search_path = public as
$$
declare nid bigint;
begin
  if not public.emg_ok() then raise exception 'You cannot use the Emergency tab.'; end if;
  if not (p_ws = any (public.emg_workshops())) then raise exception 'Choose the workshop this emergency is referred to.'; end if;
  if btrim(coalesce(p_village, '')) = '' and btrim(coalesce(p_mob, '')) = '' and btrim(coalesce(p_detail, '')) = '' then
    raise exception 'Write the village, the mobile / complaint number or some detail.'; end if;
  insert into public.emergency (refer_by, village, mobile, detail, workshop, created_by)
  values (left(btrim(coalesce(p_by, '')), 120), left(btrim(coalesce(p_village, '')), 120), left(btrim(coalesce(p_mob, '')), 60),
          left(btrim(coalesce(p_detail, '')), 400), p_ws, auth.uid())
  returning id into nid;
  return nid;
end
$$;

-- JE / Admin of that workshop: PR no. and remark
create or replace function public.emg_set(p_id bigint, p_remark text, p_pr text) returns boolean
language plpgsql security definer set search_path = public as
$$
declare w text;
begin
  select workshop into w from public.emergency where id = p_id;
  if w is null then raise exception 'This emergency was not found.'; end if;
  if not (public.emg_ok() and public.my_can_edit() and public.my_role() in ('admin', 'je') and w = any (coalesce(public.my_workshops(), '{}'))) then
    raise exception 'Only the JE / Admin of % can fill this.', w; end if;
  update public.emergency set remark = left(btrim(coalesce(p_remark, '')), 400), pr_no = left(btrim(coalesce(p_pr, '')), 40), updated_at = now() where id = p_id;
  return true;
end
$$;

-- delete (the one who added it, or the Admin of the workshop)
create or replace function public.emg_del(p_id bigint) returns boolean
language plpgsql security definer set search_path = public as
$$
declare e public.emergency;
begin
  select * into e from public.emergency where id = p_id;
  if e.id is null then return false; end if;
  if not (public.emg_ok() and (e.created_by = auth.uid() or (public.my_role() in ('admin', 'creator') and e.workshop = any (coalesce(public.my_workshops(), '{}'))))) then
    raise exception 'You cannot delete this.'; end if;
  delete from public.emergency where id = p_id;
  return true;
end
$$;

revoke all on function public.emg_ok(), public.emg_workshops(), public.emg_json(), public.emg_add(text, text, text, text, text), public.emg_set(bigint, text, text), public.emg_del(bigint) from public;
grant execute on function public.emg_ok(), public.emg_workshops(), public.emg_json(), public.emg_add(text, text, text, text, text), public.emg_set(bigint, text, text), public.emg_del(bigint) to authenticated;

-- ################ from supabase-step34-first-admin.sql ################
-- TF-Tracker : STEP 34 - FIRST-TIME ADMIN of a NEW project.  (Only needed on a new project; setup.sql already contains it.)
-- A new project has no profile at all.  The person creates ONE login by hand (Supabase > Authentication > Users > Add user,
-- e-mail = the project owner's own REAL e-mail (reset by mail works), tick "Auto Confirm User"), logs in on the site, and the site offers "First-time setup".
-- It works ONLY while the profiles table is completely empty.  After the first Admin exists, nobody can use it again.
create or replace function public.first_admin_open() returns boolean
language sql stable security definer set search_path = public as
$$ select auth.uid() is not null and not exists (select 1 from public.profiles) $$;

create or replace function public.first_admin(p_name text, p_div text) returns boolean
language plpgsql security definer set search_path = public as
$$
declare u uuid := auth.uid(); em text; nm text := btrim(coalesce(p_name, '')); dv text := upper(btrim(coalesce(p_div, '')));
begin
  if u is null then raise exception 'Please log in first.'; end if;
  lock table public.profiles in share row exclusive mode;
  if exists (select 1 from public.profiles) then raise exception 'The first Admin already exists.'; end if;
  if nm = '' then raise exception 'Please type your name.'; end if;
  if dv = '' then raise exception 'Please type the name of your division (for example EWD AZAMGARH).'; end if;
  select lower(email) into em from auth.users where id = u;
  if em is null or position('@' in em) < 2 then raise exception 'This login has no valid e-mail.'; end if;
  insert into public.profiles (user_id, login_id, display, role, org_division, scope, can_edit, active, must_change)
  values (u, case when em like '%@tf.%' then split_part(em, '@', 1) else em end, nm, 'admin', dv, '{}', true, true, false);   -- a real e-mail stays the login id (no clash with employee IDs)
  return true;
end $$;

revoke all on function public.first_admin_open(), public.first_admin(text, text) from public, anon;
grant execute on function public.first_admin_open(), public.first_admin(text, text) to authenticated;

-- ################ from supabase-step35-purge-full.sql ################
-- TF-Tracker : STEP 35 - NO fixed "2 years" limit any more.  Old data is deleted ONLY when the free storage of Supabase is almost full.
-- Run ONCE in Supabase > SQL Editor.  Safe to run again.  It also SWITCHES OFF the old nightly delete jobs of step 12 / step 15 part C.
--
-- How it works (every SUNDAY):
--   02:00 India time : if the database size is 90% (or more) of the free 500 MB, the OLDEST 10% of the PRs (by PR date) are deleted.
--                      It NEVER deletes a PR that is newer than 3 years (36 months). From 2026-11 it deletes the OLDEST 12 MONTHS at a time (not 10%),
--                      and never a PR that has no PR date.  If the storage is full but everything left is newer than 3 years, nothing is
--                      deleted and a line is written to the table purge_log (you must then upgrade the plan or clean up by hand).
--   03:00 India time : VACUUM FULL of the table "data" gives the freed space back to Supabase (without it the file size does not shrink).
-- !! Deleted PRs can NOT be brought back (there is no backup on the free plan).  Download an Excel backup now and then. !!
-- NOT run on a real Supabase by Claude (only on a local Postgres, without pg_cron): look at purge_log after the first Sunday.
--
-- To see what happened:      select * from public.purge_log order by id desc limit 10;
-- To see the size now:       select pg_size_pretty(pg_database_size(current_database()));
-- To stop it completely:     select cron.unschedule('tf-purge-full');  select cron.unschedule('tf-shrink');

create table if not exists public.purge_log (
  id       bigint generated always as identity primary key,
  ts       timestamptz not null default now(),
  db_mb    numeric,
  limit_mb numeric,
  deleted  bigint,
  note     text
);
alter table public.purge_log enable row level security;
revoke all on public.purge_log from anon, authenticated;

drop function if exists public.purge_if_full(numeric, numeric, int, numeric);   -- the older version (14 months, 10%) is replaced
create or replace function public.purge_if_full(p_limit_mb numeric default 500, p_pct numeric default 90, p_keep_months int default 36, p_step_months int default 12)
returns bigint language plpgsql security definer set search_path = public as
$$
declare sz numeric := pg_database_size(current_database()) / 1048576.0; cut date := (current_date - make_interval(months => p_keep_months))::date; n bigint; k bigint; lo date; hi date;
begin
  if p_keep_months < 36 then raise exception 'Safety: fewer than 36 months (3 years) of R&R data is not allowed.'; end if;
  if p_step_months < 1 then raise exception 'Step must be at least 1 month.'; end if;
  if sz < p_limit_mb * p_pct / 100.0 then return 0; end if;                       -- not full: nothing to do (no log line)
  select count(*), min(pr_date) into k, lo from public.data where pr_date is not null and pr_date < cut;
  if k = 0 then
    insert into public.purge_log (db_mb, limit_mb, deleted, note) values (round(sz, 1), p_limit_mb, 0, 'Storage is ' || p_pct || '% full but R&R is already down to ' || p_keep_months || ' months. Archive the M&R months to Google Drive (Admin tab) or upgrade the plan.');
    return 0;
  end if;
  hi := least(cut, (lo + make_interval(months => p_step_months))::date);            -- the OLDEST 12 months, never a PR newer than the 3 years
  insert into public.cmp_hist (workshop, division, capacity, d, n)       -- keep the daily counts for the Comparison tab BEFORE the PRs go
    select workshop, upper(btrim(regexp_replace(coalesce(division, ''), '\s+', ' ', 'g'))), coalesce(capacity, 0), pr_date, count(*)
      from public.data where pr_date is not null and pr_date < hi and not dup group by 1, 2, 3, 4
    on conflict (workshop, division, capacity, d) do update set n = greatest(public.cmp_hist.n, excluded.n);
  delete from public.data where pr_date is not null and pr_date < hi;
  get diagnostics n = row_count;
  insert into public.purge_log (db_mb, limit_mb, deleted, note) values (round(sz, 1), p_limit_mb, n, 'Deleted ' || n || ' PRs older than ' || to_char(hi, 'DD.MM.YYYY') || ' (storage was at or above ' || p_pct || '%; R&R keeps the last ' || p_keep_months || ' months).');
  return n;
end $$;
revoke all on function public.purge_if_full(numeric, numeric, int, int) from public, anon, authenticated;

-- the fixed-age deleting of step 12 / 15 is switched off
drop function if exists public.purge_old_data(int);

-- the weekly jobs (needs the pg_cron extension; if the next block says so, enable it:  Database > Extensions > pg_cron, then run this file again)
do $$
begin
  create extension if not exists pg_cron;
  begin perform cron.unschedule('tf-purge-old'); exception when others then null; end;
  begin perform cron.unschedule('tf-purge-full'); exception when others then null; end;
  begin perform cron.unschedule('tf-shrink'); exception when others then null; end;
  perform cron.schedule('tf-purge-full', '30 20 * * 6', 'select public.purge_if_full()');   -- Sunday 02:00 India time (Saturday 20:30 UTC)
  perform cron.schedule('tf-shrink',     '30 21 * * 6', 'VACUUM FULL public.data');          -- Sunday 03:00 India time
exception when others then
  raise notice 'pg_cron is not available: the weekly jobs were NOT created (%). Enable pg_cron and run this file again.', sqlerrm;
end $$;

-- ################ from supabase-step36-emergency2.sql ################
-- TF-Tracker : STEP 36 - Emergency tab changes.   Run ONCE in Supabase > SQL Editor (after step 33).  Safe to run again.  No data is lost.
--   * Only an Admin of the workshop (or the App Creator) can DELETE an emergency line. The Nodal who added it can not.
--   * A replaced emergency leaves the Emergency tab 1 DAY after the replacement date (before: 2 days).
--   * New: a From - To date range = the list of emergencies SOLVED (replaced) in that period, even the hidden ones.
--   * The Nodal now has two boxes: Mobile no. and Complaint no.  (new column "complaint").
--   * PR no. can be letters + digits; it is saved in capital letters.

alter table public.emergency add column if not exists complaint text;

drop function if exists public.emg_json();
create or replace function public.emg_json(p_from date default null, p_to date default null) returns jsonb language plpgsql stable security definer set search_path = public as
$$
declare
  mine  text[]  := coalesce(public.my_workshops(), '{}');
  ed    boolean := public.my_can_edit() and public.my_role() in ('admin', 'je');
  adm   boolean := public.my_role() in ('admin', 'creator');
  me    uuid    := auth.uid();
  today date    := (now() at time zone 'Asia/Kolkata')::date;
  hist  boolean := p_from is not null or p_to is not null;
begin
  if not public.emg_ok() then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(x order by x->>'sort' desc) from (
      select jsonb_build_object(
        'sort', case when hist then to_char(d.repl_date, 'YYYYMMDD') || lpad(e.id::text, 10, '0') else to_char(e.created_at, 'YYYYMMDDHH24MISS') || lpad(e.id::text, 10, '0') end,
        'id', e.id, 'by', e.refer_by, 'village', e.village, 'mobile', e.mobile, 'complaint', e.complaint, 'detail', e.detail, 'ws', e.workshop,
        'remark', e.remark, 'pr', e.pr_no,
        'created', to_char(e.created_at at time zone 'Asia/Kolkata', 'DD.MM.YYYY HH24:MI'),
        'can_edit', ed and e.workshop = any (mine),
        'can_del',  adm and e.workshop = any (mine),
        'found', d.id is not null, 'dup', coalesce(d.dup, false),
        'st', case when d.id is null or coalesce(d.dup, false) then 'R0'
                   when d.repl_date is not null then 'D'
                   when d.issue_date is not null then 'G'
                   else 'R1' end,
        'left', case when d.repl_date is not null then d.repl_date + 1 - today end,
        'pr_date', to_char(d.pr_date, 'DD.MM.YYYY'), 'division', d.division, 'substation', d.substation, 'feeder', d.feeder,
        'place', d.place_of_damage, 'cap', d.capacity, 'complain', d.complain_no,
        'je', d.je_name, 'je_mob', d.je_mobile, 'firm', d.firm,
        'issue', to_char(d.issue_date, 'DD.MM.YYYY'), 'drv', d.driver_name, 'drv_mob', d.driver_mobile,
        'repl', to_char(d.repl_date, 'DD.MM.YYYY')
      ) as x
      from public.emergency e
      left join lateral (
        select d0.* from public.data d0
         where btrim(coalesce(e.pr_no, '')) <> '' and d0.workshop = e.workshop and upper(btrim(d0.pr_no)) = upper(btrim(e.pr_no))
         limit 1) d on true
      where (e.workshop = any (mine) or e.created_by = me)
        and case when hist then d.repl_date is not null and not coalesce(d.dup, false)
                            and d.repl_date >= coalesce(p_from, date '0001-01-01') and d.repl_date <= coalesce(p_to, date '9999-12-31')
                 else not (d.repl_date is not null and d.repl_date + 1 <= today) end
    ) s), '[]'::jsonb);
end
$$;

drop function if exists public.emg_add(text, text, text, text, text);
create or replace function public.emg_add(p_by text, p_village text, p_mob text, p_detail text, p_ws text, p_complaint text default '') returns bigint
language plpgsql security definer set search_path = public as
$$
declare nid bigint;
begin
  if not public.emg_ok() then raise exception 'You cannot use the Emergency tab.'; end if;
  if not (p_ws = any (public.emg_workshops())) then raise exception 'Choose the workshop this emergency is referred to.'; end if;
  if btrim(coalesce(p_village, '')) = '' and btrim(coalesce(p_mob, '')) = '' and btrim(coalesce(p_complaint, '')) = '' and btrim(coalesce(p_detail, '')) = '' then
    raise exception 'Write the village, the mobile no., the complaint no. or some detail.'; end if;
  insert into public.emergency (refer_by, village, mobile, complaint, detail, workshop, created_by)
  values (left(btrim(coalesce(p_by, '')), 120), left(btrim(coalesce(p_village, '')), 120), left(btrim(coalesce(p_mob, '')), 60),
          left(btrim(coalesce(p_complaint, '')), 60), left(btrim(coalesce(p_detail, '')), 400), p_ws, auth.uid())
  returning id into nid;
  return nid;
end
$$;

create or replace function public.emg_set(p_id bigint, p_remark text, p_pr text) returns boolean
language plpgsql security definer set search_path = public as
$$
declare w text;
begin
  select workshop into w from public.emergency where id = p_id;
  if w is null then raise exception 'This emergency was not found.'; end if;
  if not (public.emg_ok() and public.my_can_edit() and public.my_role() in ('admin', 'je') and w = any (coalesce(public.my_workshops(), '{}'))) then
    raise exception 'Only the JE / Admin of % can fill this.', w; end if;
  update public.emergency set remark = left(btrim(coalesce(p_remark, '')), 400), pr_no = upper(left(btrim(coalesce(p_pr, '')), 40)), updated_at = now() where id = p_id;
  return true;
end
$$;

create or replace function public.emg_del(p_id bigint) returns boolean
language plpgsql security definer set search_path = public as
$$
declare e public.emergency;
begin
  select * into e from public.emergency where id = p_id;
  if e.id is null then return false; end if;
  if not (public.emg_ok() and public.my_role() in ('admin', 'creator') and e.workshop = any (coalesce(public.my_workshops(), '{}'))) then
    raise exception 'Only an Admin can delete an emergency.'; end if;
  delete from public.emergency where id = p_id;
  return true;
end
$$;

revoke all on function public.emg_json(date, date), public.emg_add(text, text, text, text, text, text), public.emg_set(bigint, text, text), public.emg_del(bigint) from public, anon;
grant execute on function public.emg_json(date, date), public.emg_add(text, text, text, text, text, text), public.emg_set(bigint, text, text), public.emg_del(bigint) to authenticated;

-- ################ from supabase-step37-structure.sql ################
-- TF-Tracker : STEP 37 - STRUCTURE: Workshop > Circle > Division, with short names and your own order.
-- Run ONCE in Supabase > SQL Editor.  Safe to run again.  No PR data is changed by this file.
-- The Admin makes it in  Admin tab > Structure.  The Comparison tab and the Division wise table of the Summary follow it
-- (same circles, same order, short names).  Renaming a division there also renames it in the PRs of the Data Sheet.
-- One row = one division.  "division" is the name exactly as written in the PRs of the Data Sheet.

create table if not exists public.divmap (
  id           bigint generated always as identity primary key,
  workshop     text not null,
  circle       text not null,
  circle_short text,
  circle_sort  int  not null default 0,
  division     text not null,
  short        text,
  sort         int  not null default 0,
  unique (workshop, division)
);
alter table public.divmap enable row level security;
revoke all on public.divmap from anon, authenticated;

-- everybody who is logged in reads the structure (the Comparison is the same for every login)
create or replace function public.struct_json() returns jsonb language sql stable security definer set search_path = public as
$$
  select case when auth.uid() is null or not exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.active) then '[]'::jsonb
    else coalesce((select jsonb_agg(jsonb_build_object('ws', workshop, 'circle', circle, 'cs', circle_short, 'csort', circle_sort, 'div', division, 'short', short, 'sort', sort)
                                    order by workshop, circle_sort, sort, division) from public.divmap), '[]'::jsonb) end
$$;

-- the divisions that exist in the PRs of the Admin's workshops but are not in the structure yet (for the button "Fill from my data")
create or replace function public.struct_found(p_ws text[]) returns jsonb language plpgsql stable security definer set search_path = public as
$$
declare ok text[];
begin
  if public.my_role() not in ('admin', 'creator') then raise exception 'Only an Admin can do this.'; end if;
  ok := array(select name from public.workshops where name = any (coalesce(p_ws, '{}'))
                and (public.my_role() = 'creator' or name = any (coalesce(public.my_workshops(), '{}'))));
  return coalesce((select jsonb_agg(jsonb_build_object('ws', d.workshop, 'div', d.division, 'n', d.n) order by d.workshop, d.division)
                   from (select workshop, btrim(division) as division, count(*) n from public.data
                          where workshop = any (ok) and btrim(coalesce(division, '')) <> ''
                          group by workshop, btrim(division)) d
                   where not exists (select 1 from public.divmap m where m.workshop = d.workshop and upper(regexp_replace(m.division, '[^A-Za-z0-9]', '', 'g')) = upper(regexp_replace(d.division, '[^A-Za-z0-9]', '', 'g')))), '[]'::jsonb);
end $$;

-- save the structure of the given workshops (replaces what was there for those workshops).
-- p_rows = [{ "ws","circle","cs","csort","div","short","sort","old" }]   "old" = the division name before the Admin changed it (then the PRs are renamed too)
create or replace function public.struct_save(p_ws text[], p_rows jsonb) returns jsonb language plpgsql security definer set search_path = public as
$$
declare ok text[]; r jsonb; n int := 0; ren int := 0; k int; seen text[] := '{}'; key text;
begin
  if public.my_role() not in ('admin', 'creator') or not public.my_can_edit() then raise exception 'Only an Admin can change the structure.'; end if;
  ok := array(select name from public.workshops where name = any (coalesce(p_ws, '{}'))
                and (public.my_role() = 'creator' or name = any (coalesce(public.my_workshops(), '{}'))));
  if coalesce(array_length(ok, 1), 0) = 0 then raise exception 'No workshop to save.'; end if;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    if not ((r->>'ws') = any (ok)) then raise exception 'The workshop % is not yours.', r->>'ws'; end if;
    if btrim(coalesce(r->>'div', '')) = '' or btrim(coalesce(r->>'circle', '')) = '' then raise exception 'Every division needs a name and a circle.'; end if;
    key := (r->>'ws') || '|' || upper(regexp_replace(r->>'div', '[^A-Za-z0-9]', '', 'g'));
    if key = any (seen) then raise exception 'The division "%" is written twice in %.', r->>'div', r->>'ws'; end if;
    seen := seen || key;
  end loop;
  -- renamed divisions: change the PRs of the Data Sheet first
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    if btrim(coalesce(r->>'old', '')) <> '' and btrim(r->>'old') <> btrim(r->>'div') then
      update public.data set division = btrim(r->>'div') where workshop = r->>'ws' and btrim(division) = btrim(r->>'old');
      get diagnostics k = row_count; ren := ren + k;
    end if;
  end loop;
  delete from public.divmap where workshop = any (ok);
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    insert into public.divmap (workshop, circle, circle_short, circle_sort, division, short, sort)
    values (r->>'ws', left(btrim(r->>'circle'), 80), nullif(left(btrim(coalesce(r->>'cs', '')), 40), ''), coalesce((r->>'csort')::int, 0),
            left(btrim(r->>'div'), 120), nullif(left(btrim(coalesce(r->>'short', '')), 40), ''), coalesce((r->>'sort')::int, 0));
    n := n + 1;
  end loop;
  return jsonb_build_object('saved', n, 'renamed_prs', ren);
end $$;

revoke all on function public.struct_json(), public.struct_found(text[]), public.struct_save(text[], jsonb) from public, anon;
grant execute on function public.struct_json(), public.struct_found(text[]), public.struct_save(text[], jsonb) to authenticated;

-- DONE.  Next: create the first Admin (see the README), then add workshops in the Admin tab.
-- STEP 40 : M&R DASHBOARD  (Maintenance & Repair)  -- run in the TEST project first.
-- DTC no / DTC date per PR row, and the daily KITTY (stock of repaired transformers) per workshop and capacity.
-- Nothing in the existing tables is changed.  New tables:  dtc, kitty_base, kitty_day.
-- Who: an "M&R user" is a normal user whose tabs list contains 'mr'.  An Admin (and the App Creator for reading) can also use it.

-- 1) DTC no + DTC date, one row per PR row of the Data Sheet ---------------------------------------------
create table if not exists public.dtc (
  data_id   bigint primary key references public.data(id) on delete cascade,
  dtc_no    text,
  dtc_date  date,
  by_login  text,
  at        timestamptz not null default now()
);
create index if not exists dtc_date_i on public.dtc(dtc_date);
alter table public.dtc enable row level security;
revoke all on public.dtc from public, anon;
grant select on public.dtc to authenticated;
drop policy if exists dtc_read on public.dtc;
-- a user can read a DTC row only if the Data Sheet row itself is visible to him (workshop scope)
create policy dtc_read on public.dtc for select to authenticated using (exists (select 1 from public.data d where d.id = data_id));

-- 2) kitty: the starting figures set by an Admin (opening kitty + unrepaired T/F on a start date) -------------
create table if not exists public.kitty_base (
  workshop text not null, day date not null, cap int not null,
  opening int not null default 0 check (opening >= 0), unrep int not null default 0 check (unrep >= 0),
  by_login text, at timestamptz not null default now(),
  primary key (workshop, day, cap)
);
-- 3) kitty: the daily figures typed by the M&R user ---------------------------------------------------------
create table if not exists public.kitty_day (
  workshop text not null, day date not null, cap int not null,
  repair int not null default 0 check (repair >= 0), to_other int not null default 0 check (to_other >= 0), from_other int not null default 0 check (from_other >= 0),
  by_login text, at timestamptz not null default now(),
  primary key (workshop, day, cap)
);
alter table public.kitty_base enable row level security;
alter table public.kitty_day  enable row level security;
revoke all on public.kitty_base, public.kitty_day from public, anon, authenticated;

-- who may use M&R ------------------------------------------------------------------------------------------
create or replace function public.mr_ok() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select p.active and (p.role in ('admin', 'creator') or 'mr' = any (coalesce(p.tabs, '{}'))) from public.profiles p where p.user_id = auth.uid()), false)
$$;
-- may the caller change the M&R figures of this workshop?  (an M&R user: his workshops; an Admin: the workshops of his division; the App Creator: no)
create or replace function public.mr_edit_ok(p_ws text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select p.active and p_ws = any (public.my_workshops())
                           and (p.role = 'admin' or (p.role = 'je' and 'mr' = any (coalesce(p.tabs, '{}')))) from public.profiles p where p.user_id = auth.uid()), false)
$$;
create or replace function public.mr_admin_ok(p_ws text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select p.active and p.role = 'admin' and p_ws = any (public.my_workshops()) from public.profiles p where p.user_id = auth.uid()), false)
$$;

-- 4) M&R SUMMARY ---------------------------------------------------------------------------------------------
-- rows: workshop-wise  [workshop, today_pr, today_dtc, total_pr, total_dtc, pending_dtc]
--       capacity-wise  [workshop, capacity, pr, dtc_done, pending]
--  PR = PR raised (PR date) in the period;  DTC done = of those PR, the ones that have a DTC no;  pending = PR - done.
--  TODAY PR = PR raised on the date;  TODAY DTC = DTC entered with that DTC date.
create or replace function public.mr_summary_json(p_date date, p_from date, p_to date) returns jsonb
language plpgsql stable set search_path = public as $$
declare r jsonb;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  with d as (select x.workshop, x.capacity, x.pr_date, t.dtc_no, t.dtc_date
               from public.data x left join public.dtc t on t.data_id = x.id
              where not x.dup and x.workshop = any (coalesce((select public.my_workshops()), '{}'))),
  w as (select workshop,
               count(*) filter (where pr_date = p_date) today_pr,
               count(*) filter (where dtc_date = p_date and dtc_no is not null) today_dtc,
               count(*) filter (where pr_date between p_from and p_to) tot_pr,
               count(*) filter (where pr_date between p_from and p_to and nullif(btrim(dtc_no), '') is not null) tot_dtc
          from d group by workshop),
  c as (select workshop, coalesce(capacity, 0) cap,
               count(*) filter (where pr_date between p_from and p_to) pr,
               count(*) filter (where pr_date between p_from and p_to and nullif(btrim(dtc_no), '') is not null) done
          from d group by workshop, coalesce(capacity, 0))
  select jsonb_build_object(
    'ws',  coalesce((select jsonb_agg(jsonb_build_array(workshop, today_pr, today_dtc, tot_pr, tot_dtc, tot_pr - tot_dtc) order by workshop) from w), '[]'),
    'cap', coalesce((select jsonb_agg(jsonb_build_array(workshop, cap, pr, done, pr - done) order by workshop, cap) from c where pr > 0), '[]'))
    into r;
  return r;
end $$;

-- 5) DTC SHEET: the rows of one month (by PR date) ----------------------------------------------------------------
create or replace function public.mr_list_json(p_month date, p_ws text default null, p_status text default 'all', p_q text default null, p_limit int default 300, p_offset int default 0) returns jsonb
language plpgsql stable set search_path = public as $$
declare m1 date := date_trunc('month', p_month)::date; m2 date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date; q text := nullif(btrim(coalesce(p_q, '')), ''); r jsonb;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  with b as (select x.*, t.dtc_no, t.dtc_date, (nullif(btrim(t.dtc_no), '') is not null) done
               from public.data x left join public.dtc t on t.data_id = x.id
              where not x.dup and x.workshop = any (coalesce((select public.my_workshops()), '{}')) and x.pr_date between m1 and m2
                and (p_ws is null or x.workshop = p_ws)
                and (q is null or x.pr_no ilike '%' || q || '%' or coalesce(x.complain_no, '') ilike '%' || q || '%' or coalesce(x.place_of_damage, '') ilike '%' || q || '%' or coalesce(t.dtc_no, '') ilike '%' || q || '%')),
  f as (select * from b where p_status = 'all' or (p_status = 'pending' and not done) or (p_status = 'done' and done))
  select jsonb_build_object(
    'all', (select count(*) from b), 'pending', (select count(*) from b where not done), 'done', (select count(*) from b where done), 'shown', (select count(*) from f),
    'rows', coalesce((select jsonb_agg(jsonb_build_array(id, workshop, division, substation, feeder, place_of_damage, capacity, complain_no, pr_no, pr_date, je_name, issue_date, repl_date, return_date, dtc_no, dtc_date,
                        case when public.mr_edit_ok(workshop) then 1 else 0 end) order by pr_date, pr_no collate "C")
                        from (select * from f order by pr_date, pr_no collate "C" limit least(greatest(p_limit, 1), 1000) offset greatest(p_offset, 0)) z), '[]'))
    into r;
  return r;
end $$;

-- set / clear the DTC no + DTC date of one row ------------------------------------------------------------
create or replace function public.mr_dtc_set(p_id bigint, p_no text, p_date date) returns text
language plpgsql security definer set search_path = public as $$
declare ws text; no text := nullif(btrim(coalesce(p_no, '')), ''); c public.profiles := public.tf_caller();
begin
  select workshop into ws from public.data where id = p_id;
  if ws is null then raise exception 'This PR row was not found.'; end if;
  if not public.mr_edit_ok(ws) then raise exception 'You cannot change the DTC of this workshop.'; end if;
  if no is not null and length(no) > 40 then raise exception 'DTC no is too long.'; end if;
  if p_date is not null and (p_date < date '2000-01-01' or p_date > current_date + 2) then raise exception 'DTC date looks wrong.'; end if;
  if no is null and p_date is null then delete from public.dtc where data_id = p_id; return 'cleared'; end if;
  insert into public.dtc(data_id, dtc_no, dtc_date, by_login, at) values (p_id, no, p_date, c.login_id, now())
    on conflict (data_id) do update set dtc_no = excluded.dtc_no, dtc_date = excluded.dtc_date, by_login = excluded.by_login, at = now();
  return 'saved';
end $$;

-- 6) KITTY ----------------------------------------------------------------------------------------------------
-- For one workshop and one day, for each standard capacity:
--   OPENING KITTY  = net kitty of the day before  (on the start day: the figure set by the Admin)
--   UNREPAIRED T/F = unrepaired of the day before - repair of the day before + transformers RETURNED today (Data Sheet return date)
--                    (on the start day: the figure set by the Admin)
--   ISSUE          = transformers issued today (Data Sheet issue date)
--   REPAIR, ISSUE TO OTHER W/S, RECEIVE FROM OTHER W/S = typed by the M&R user
--   NET KITTY      = opening + repair + receive from other - issue - issue to other
create or replace function public.kitty_json(p_ws text, p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb; base_day date;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  if not (p_ws = any (public.my_workshops())) then raise exception 'This workshop is not yours.'; end if;
  select max(day) into base_day from public.kitty_base where workshop = p_ws and day <= p_day;
  if base_day is null then
    return jsonb_build_object('base', null, 'first', (select min(day) from public.kitty_base where workshop = p_ws), 'rows', '[]'::jsonb, 'edit', public.mr_edit_ok(p_ws), 'admin', public.mr_admin_ok(p_ws));
  end if;
  with caps as (select unnest(array[10, 16, 25, 63, 100, 160, 250, 400, 630]) cap),
  b as (select distinct on (k.cap) k.cap, k.day a, k.opening, k.unrep from public.kitty_base k where k.workshop = p_ws and k.day <= p_day order by k.cap, k.day desc),
  days as (select b.cap, b.a, b.opening, b.unrep, g::date d from b, generate_series(b.a, p_day, interval '1 day') g),
  iss as (select issue_date d, capacity cap, count(*) n from public.data where not dup and workshop = p_ws and issue_date between base_day and p_day group by 1, 2),
  ret as (select return_date d, capacity cap, count(*) n from public.data where not dup and workshop = p_ws and return_date between base_day and p_day group by 1, 2),
  x as (select days.cap, days.a, days.opening, days.unrep, days.d,
               coalesce(i.n, 0) issue, coalesce(t.n, 0) ret, coalesce(k.repair, 0) repair, coalesce(k.to_other, 0) to_other, coalesce(k.from_other, 0) from_other
          from days left join iss i on i.d = days.d and i.cap = days.cap
                    left join ret t on t.d = days.d and t.cap = days.cap
                    left join public.kitty_day k on k.workshop = p_ws and k.day = days.d and k.cap = days.cap),
  y as (select x.*,
               sum(repair + from_other - issue - to_other) over (partition by cap order by d rows between unbounded preceding and 1 preceding) prev_delta,
               sum(repair) over (partition by cap order by d rows between unbounded preceding and 1 preceding) prev_repair,
               sum(case when d > a then ret else 0 end) over (partition by cap order by d rows between unbounded preceding and current row) cum_ret
          from x),
  z as (select cap, d, issue, repair, to_other, from_other,
               opening + coalesce(prev_delta, 0) as opening_kitty,
               unrep - coalesce(prev_repair, 0) + cum_ret as unrepaired,
               opening + coalesce(prev_delta, 0) + repair + from_other - issue - to_other as net
          from y where d = p_day)
  select jsonb_build_object('base', base_day, 'first', (select min(day) from public.kitty_base where workshop = p_ws),
    'rows', coalesce((select jsonb_agg(jsonb_build_array(cap, opening_kitty, unrepaired, issue, repair, to_other, from_other, net) order by cap) from z), '[]'),
    'edit', public.mr_edit_ok(p_ws), 'admin', public.mr_admin_ok(p_ws))
    into r;
  return r;
end $$;

-- save the M&R user's daily figures: p_rows = [{cap, repair, to_other, from_other}, ...]
create or replace function public.kitty_save(p_ws text, p_day date, p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb; c public.profiles := public.tf_caller(); bd date; n int := 0;
begin
  if not public.mr_edit_ok(p_ws) then raise exception 'You cannot change the kitty of this workshop.'; end if;
  if p_day is null or p_day > current_date + 1 then raise exception 'Choose today or an earlier date.'; end if;
  select max(day) into bd from public.kitty_base where workshop = p_ws and day <= p_day;
  if bd is null then raise exception 'The Admin must first set the opening kitty and the unrepaired T/F (start date).'; end if;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if (e->>'cap')::int not in (10, 16, 25, 63, 100, 160, 250, 400, 630) then continue; end if;
    if coalesce((e->>'repair')::int, 0) < 0 or coalesce((e->>'to_other')::int, 0) < 0 or coalesce((e->>'from_other')::int, 0) < 0
       or coalesce((e->>'repair')::int, 0) > 100000 or coalesce((e->>'to_other')::int, 0) > 100000 or coalesce((e->>'from_other')::int, 0) > 100000 then raise exception 'Numbers must be 0 or more.'; end if;
    insert into public.kitty_day(workshop, day, cap, repair, to_other, from_other, by_login, at)
      values (p_ws, p_day, (e->>'cap')::int, coalesce((e->>'repair')::int, 0), coalesce((e->>'to_other')::int, 0), coalesce((e->>'from_other')::int, 0), c.login_id, now())
      on conflict (workshop, day, cap) do update set repair = excluded.repair, to_other = excluded.to_other, from_other = excluded.from_other, by_login = excluded.by_login, at = now();
    n := n + 1;
  end loop;
  return 'saved ' || n;
end $$;

-- the Admin sets / changes the start figures: p_rows = [{cap, opening, unrep}, ...]  (a new start date replaces the older ones from that day on)
create or replace function public.kitty_base_set(p_ws text, p_day date, p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb; c public.profiles := public.tf_caller(); n int := 0;
begin
  if not public.mr_admin_ok(p_ws) then raise exception 'Only the Admin of this workshop can set the start figures.'; end if;
  if p_day is null or p_day > current_date + 1 then raise exception 'Choose today or an earlier date.'; end if;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if (e->>'cap')::int not in (10, 16, 25, 63, 100, 160, 250, 400, 630) then continue; end if;
    if coalesce((e->>'opening')::int, 0) < 0 or coalesce((e->>'unrep')::int, 0) < 0 then raise exception 'Numbers must be 0 or more.'; end if;
    insert into public.kitty_base(workshop, day, cap, opening, unrep, by_login, at)
      values (p_ws, p_day, (e->>'cap')::int, coalesce((e->>'opening')::int, 0), coalesce((e->>'unrep')::int, 0), c.login_id, now())
      on conflict (workshop, day, cap) do update set opening = excluded.opening, unrep = excluded.unrep, by_login = excluded.by_login, at = now();
    n := n + 1;
  end loop;
  return 'saved ' || n;
end $$;

revoke all on function public.mr_ok(), public.mr_edit_ok(text), public.mr_admin_ok(text), public.mr_summary_json(date, date, date), public.mr_list_json(date, text, text, text, int, int),
  public.mr_dtc_set(bigint, text, date), public.kitty_json(text, date), public.kitty_save(text, date, jsonb), public.kitty_base_set(text, date, jsonb) from public, anon;
grant execute on function public.mr_ok(), public.mr_edit_ok(text), public.mr_admin_ok(text), public.mr_summary_json(date, date, date), public.mr_list_json(date, text, text, text, int, int),
  public.mr_dtc_set(bigint, text, date), public.kitty_json(text, date), public.kitty_save(text, date, jsonb), public.kitty_base_set(text, date, jsonb) to authenticated;


-- 7) the tab list of a user may now also hold 'emg' (Emergency) and 'mr' (M&R dashboard) -------------------------------------
create or replace function public.admin_set_user(p_login text, p_name text, p_scope text[], p_edit boolean, p_tabs text[], p_active boolean) returns text
language plpgsql security definer set search_path = public as
$$
declare c public.profiles := public.tf_caller(); t public.profiles; sc text[] := coalesce(p_scope, '{}'); tb text[] := p_tabs; ed boolean := coalesce(p_edit,false);
begin
  if c.user_id is null or c.role not in ('admin','creator') then raise exception 'Only an Admin can change users.'; end if;
  select * into t from public.profiles where login_id = lower(btrim(p_login));
  if t.user_id is null then raise exception 'User not found.'; end if;
  if t.role = 'creator' then raise exception 'This user cannot be changed here.'; end if;
  if c.role = 'admin' and not (t.role = 'je' and t.org_division is not distinct from c.org_division) then raise exception 'You can change only the users of your own division.'; end if;
  if t.user_id = c.user_id and not coalesce(p_active, true) then raise exception 'You cannot deactivate your own ID.'; end if;
  if tb is not null then
    if cardinality(tb) = 0 then raise exception 'Choose at least one tab.'; end if;
    if exists (select 1 from unnest(tb) x where x not in ('sum','data','drv','emg','mr')) then raise exception 'Unknown tab.'; end if;
    if not ('data' = any(tb)) then ed := false; end if;
  end if;
  if t.role = 'je' then
    if cardinality(sc) = 0 then raise exception 'Choose at least one workshop.'; end if;
    if exists (select 1 from unnest(sc) x where x not in (select name from public.workshops where org_division = coalesce(t.org_division, c.org_division))) then
      raise exception 'A workshop is not in this division.'; end if;
  else sc := t.scope; end if;
  update public.profiles set display = coalesce(nullif(btrim(p_name),''), display), scope = sc, can_edit = ed, tabs = tb, active = coalesce(p_active, active)
   where user_id = t.user_id;
  return 'OK';
end $$;
-- STEP 41 : M&R  part 2  (run in the TEST project AFTER step 40)
--  * DTC Sheet shows firm + driver name (not issue / replacement date)
--  * "Next month need": last year's same month  ->  repair added to the kitty, PR (+2%) subtracted
--  * last year's repair typed as a MONTH TOTAL per capacity (only while the kitty has no own data of that time)
--  * Kitty compare: net kitty of all your workshops, capacity wise

-- 1) DTC list: columns  [id, workshop, division, substation, feeder, place, cap, complain, pr_no, pr_date, je_name, firm, driver_name, return_date, dtc_no, dtc_date, editable]
create or replace function public.mr_list_json(p_month date, p_ws text default null, p_status text default 'all', p_q text default null, p_limit int default 300, p_offset int default 0) returns jsonb
language plpgsql stable set search_path = public as $$
declare m1 date := date_trunc('month', p_month)::date; m2 date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date; q text := nullif(btrim(coalesce(p_q, '')), ''); r jsonb;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  with b as (select x.*, t.dtc_no, t.dtc_date, (nullif(btrim(t.dtc_no), '') is not null) done
               from public.data x left join public.dtc t on t.data_id = x.id
              where not x.dup and x.workshop = any (coalesce((select public.my_workshops()), '{}')) and x.pr_date between m1 and m2
                and (p_ws is null or x.workshop = p_ws)
                and (q is null or x.pr_no ilike '%' || q || '%' or coalesce(x.complain_no, '') ilike '%' || q || '%' or coalesce(x.place_of_damage, '') ilike '%' || q || '%' or coalesce(t.dtc_no, '') ilike '%' || q || '%')),
  f as (select * from b where p_status = 'all' or (p_status = 'pending' and not done) or (p_status = 'done' and done))
  select jsonb_build_object(
    'all', (select count(*) from b), 'pending', (select count(*) from b where not done), 'done', (select count(*) from b where done), 'shown', (select count(*) from f),
    'rows', coalesce((select jsonb_agg(jsonb_build_array(id, workshop, division, substation, feeder, place_of_damage, capacity, complain_no, pr_no, pr_date, je_name, firm, driver_name, return_date, dtc_no, dtc_date,
                        case when public.mr_edit_ok(workshop) then 1 else 0 end) order by pr_date, pr_no collate "C")
                        from (select * from f order by pr_date, pr_no collate "C" limit least(greatest(p_limit, 1), 1000) offset greatest(p_offset, 0)) z), '[]'))
    into r;
  return r;
end $$;

-- 2) last year's repair, one number per workshop + month + capacity ----------------------------------------------
create table if not exists public.kitty_ly (
  workshop text not null, month date not null, cap int not null,
  repair int not null default 0 check (repair >= 0),
  by_login text, at timestamptz not null default now(),
  primary key (workshop, month, cap)
);
alter table public.kitty_ly enable row level security;
revoke all on public.kitty_ly from public, anon, authenticated;

create or replace function public.kitty_ly_json(p_ws text, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  if not (p_ws = any (public.my_workshops())) then raise exception 'This workshop is not yours.'; end if;
  return jsonb_build_object('month', m, 'edit', public.mr_edit_ok(p_ws),
    'rows', (select jsonb_agg(jsonb_build_array(c.cap, coalesce(k.repair, 0)) order by c.cap)
               from (select unnest(array[10, 16, 25, 63, 100, 160, 250, 400, 630]) cap) c
               left join public.kitty_ly k on k.workshop = p_ws and k.month = m and k.cap = c.cap));
end $$;

create or replace function public.kitty_ly_set(p_ws text, p_month date, p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb; c public.profiles := public.tf_caller(); m date := date_trunc('month', p_month)::date; n int := 0;
begin
  if not public.mr_edit_ok(p_ws) then raise exception 'You cannot change the kitty of this workshop.'; end if;
  if m >= date_trunc('month', current_date)::date then raise exception 'Choose a month of the past.'; end if;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if (e->>'cap')::int not in (10, 16, 25, 63, 100, 160, 250, 400, 630) then continue; end if;
    if coalesce((e->>'repair')::int, 0) < 0 or coalesce((e->>'repair')::int, 0) > 100000 then raise exception 'Numbers must be 0 or more.'; end if;
    insert into public.kitty_ly(workshop, month, cap, repair, by_login, at) values (p_ws, m, (e->>'cap')::int, coalesce((e->>'repair')::int, 0), c.login_id, now())
      on conflict (workshop, month, cap) do update set repair = excluded.repair, by_login = excluded.by_login, at = now();
    n := n + 1;
  end loop;
  return 'saved ' || n;
end $$;

-- 3) NEXT MONTH NEED -------------------------------------------------------------------------------------------
--  kitty        = net kitty of the viewed day
--  window       = the same date LAST YEAR, p_days days long
--  last-year PR = PR of that window (Data Sheet), made 2% more
--  last-year repair = the kitty's own daily repair of that window when the kitty already had data then,
--                     else the month totals typed in kitty_ly (shared by the days of the window)
--  result       = kitty + repair - PR(+2%);  need = the missing part (0 when the kitty is enough)
-- rows: [cap, kitty, repair_ly, pr_ly, pr_plus2, result, need]
create or replace function public.kitty_need_json(p_ws text, p_day date, p_days int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k jsonb; n int := least(greatest(coalesce(p_days, 30), 1), 120); w1 date := (p_day - interval '1 year')::date; w2 date; bmin date; manual boolean; rows jsonb; mons jsonb;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  if not (p_ws = any (public.my_workshops())) then raise exception 'This workshop is not yours.'; end if;
  w2 := w1 + n - 1;
  k := public.kitty_json(p_ws, p_day);
  if k->'base' is null or k->>'base' is null then raise exception 'The Admin must first set the start figures of the kitty (see Start figures).'; end if;
  select min(day) into bmin from public.kitty_base where workshop = p_ws;
  manual := (bmin is null or w1 < bmin);
  with caps as (select unnest(array[10, 16, 25, 63, 100, 160, 250, 400, 630]) cap),
  kit as (select (e->>0)::int cap, (e->>7)::int net from jsonb_array_elements(k->'rows') e),
  pr as (select capacity cap, count(*) n from public.data where not dup and workshop = p_ws and pr_date between w1 and w2 group by 1),
  own as (select cap, sum(repair) n from public.kitty_day where workshop = p_ws and day between w1 and w2 group by 1),
  man as (select l.cap, sum(l.repair::numeric * (least(w2, (l.month + interval '1 month - 1 day')::date) - greatest(w1, l.month) + 1) / extract(day from (l.month + interval '1 month - 1 day'))) n
            from public.kitty_ly l where l.workshop = p_ws and l.month <= w2 and (l.month + interval '1 month - 1 day')::date >= w1 group by 1),
  x as (select caps.cap, coalesce(kit.net, 0) kitty, round(case when manual then coalesce(man.n, 0) else coalesce(own.n, 0) end)::int rep, coalesce(pr.n, 0)::int prn,
               ceil(coalesce(pr.n, 0) * 1.02)::int pr2
          from caps left join kit using (cap) left join pr using (cap) left join own using (cap) left join man using (cap))
  select jsonb_agg(jsonb_build_array(cap, kitty, rep, prn, pr2, kitty + rep - pr2, greatest(0, pr2 - kitty - rep)) order by cap) into rows from x;
  select coalesce(jsonb_agg(m order by m), '[]') into mons from (select distinct date_trunc('month', g)::date m from generate_series(w1, w2, interval '1 day') g) q;
  return jsonb_build_object('rows', rows, 'w1', w1, 'w2', w2, 'days', n, 'manual', manual, 'months', mons, 'edit', public.mr_edit_ok(p_ws));
end $$;

-- 4) KITTY COMPARE : net kitty of the day, capacity wise, one column per workshop of the caller --------------------
-- ws: [names]   rows: [cap, n1, n2, ...]   nobase: workshops whose kitty is not started on that day
create or replace function public.kitty_cmp_json(p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare w text; names jsonb := '[]'; nob jsonb := '[]'; vals jsonb := '{}'; k jsonb; e jsonb; res jsonb := '[]'; cp int;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  for w in select unnest(public.my_workshops()) order by 1 loop
    names := names || to_jsonb(w);
    k := public.kitty_json(w, p_day);
    if k->>'base' is null then nob := nob || to_jsonb(w);
    else for e in select * from jsonb_array_elements(k->'rows') loop vals := jsonb_set(vals, array[w || '|' || (e->>0)], to_jsonb((e->>7)::int), true); end loop;
    end if;
  end loop;
  foreach cp in array array[10, 16, 25, 63, 100, 160, 250, 400, 630] loop
    res := res || jsonb_build_array(jsonb_build_array(cp) || coalesce((select jsonb_agg(coalesce(vals->(n || '|' || cp), 'null'::jsonb) order by ord) from jsonb_array_elements_text(names) with ordinality t(n, ord)), '[]'));
  end loop;
  return jsonb_build_object('ws', names, 'rows', res, 'nobase', nob);
end $$;

grant execute on function public.kitty_ly_json(text, date), public.kitty_ly_set(text, date, jsonb), public.kitty_need_json(text, date, int), public.kitty_cmp_json(date) to authenticated;
-- STEP 42 : M&R part 3  (run in the TEST project AFTER step 41)
-- "Next month need" now sends only the NEED per capacity (all the calculation stays here in the database):
--   need = PR of last year's same days (+2%, rounded up)  -  (kitty of the viewed day + last year's repair of those days), never below 0
-- rows: [cap, need]     ly_any = true when last year's repair of the window has been filled (own daily figures or month totals)
create or replace function public.kitty_need_json(p_ws text, p_day date, p_days int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k jsonb; n int := least(greatest(coalesce(p_days, 30), 1), 120); w1 date := (p_day - interval '1 year')::date; w2 date; bmin date; manual boolean; rows jsonb; any_rep boolean;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  if not (p_ws = any (public.my_workshops())) then raise exception 'This workshop is not yours.'; end if;
  w2 := w1 + n - 1;
  k := public.kitty_json(p_ws, p_day);
  if k->>'base' is null then raise exception 'The Admin must first set the start figures of the kitty (see Start figures).'; end if;
  select min(day) into bmin from public.kitty_base where workshop = p_ws;
  manual := (bmin is null or w1 < bmin);
  with caps as (select unnest(array[10, 16, 25, 63, 100, 160, 250, 400, 630]) cap),
  kit as (select (e->>0)::int cap, (e->>7)::int net from jsonb_array_elements(k->'rows') e),
  pr as (select capacity cap, count(*) n from public.data where not dup and workshop = p_ws and pr_date between w1 and w2 group by 1),
  own as (select cap, sum(repair) n from public.kitty_day where workshop = p_ws and day between w1 and w2 group by 1),
  man as (select l.cap, sum(l.repair::numeric * (least(w2, (l.month + interval '1 month - 1 day')::date) - greatest(w1, l.month) + 1) / extract(day from (l.month + interval '1 month - 1 day'))) n
            from public.kitty_ly l where l.workshop = p_ws and l.month <= w2 and (l.month + interval '1 month - 1 day')::date >= w1 group by 1),
  x as (select caps.cap, coalesce(kit.net, 0) kitty, round(case when manual then coalesce(man.n, 0) else coalesce(own.n, 0) end)::int rep, ceil(coalesce(pr.n, 0) * 1.02)::int pr2
          from caps left join kit using (cap) left join pr using (cap) left join own using (cap) left join man using (cap))
  select jsonb_agg(jsonb_build_array(cap, greatest(0, pr2 - kitty - rep)) order by cap), coalesce(bool_or(rep > 0), false) into rows, any_rep from x;
  return jsonb_build_object('rows', rows, 'w1', w1, 'w2', w2, 'days', n, 'manual', manual, 'ly_any', any_rep);
end $$;
-- STEP 43 : M&R part 4  (run in the TEST project AFTER step 42)
-- "Next month need" again shows the full calculation (kitty, last year repair, last year PR, PR + x%, kitty after, need).
-- PR of last year is made x% more: x is chosen on the screen, 0 to 5 (default 5), rounded up.
-- rows: [cap, kitty, repair_ly, pr_ly, pr_plus, result, need]
drop function if exists public.kitty_need_json(text, date, int);
create or replace function public.kitty_need_json(p_ws text, p_day date, p_days int default 30, p_pct numeric default 5) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k jsonb; n int := least(greatest(coalesce(p_days, 30), 1), 120); pc numeric := least(greatest(coalesce(p_pct, 5), 0), 5); w1 date := (p_day - interval '1 year')::date; w2 date; bmin date; manual boolean; rows jsonb; any_rep boolean;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  if not (p_ws = any (public.my_workshops())) then raise exception 'This workshop is not yours.'; end if;
  w2 := w1 + n - 1;
  k := public.kitty_json(p_ws, p_day);
  if k->>'base' is null then raise exception 'The Admin must first set the start figures of the kitty (see Start figures).'; end if;
  select min(day) into bmin from public.kitty_base where workshop = p_ws;
  manual := (bmin is null or w1 < bmin);
  with caps as (select unnest(array[10, 16, 25, 63, 100, 160, 250, 400, 630]) cap),
  kit as (select (e->>0)::int cap, (e->>7)::int net from jsonb_array_elements(k->'rows') e),
  pr as (select capacity cap, count(*) n from public.data where not dup and workshop = p_ws and pr_date between w1 and w2 group by 1),
  own as (select cap, sum(repair) n from public.kitty_day where workshop = p_ws and day between w1 and w2 group by 1),
  man as (select l.cap, sum(l.repair::numeric * (least(w2, (l.month + interval '1 month - 1 day')::date) - greatest(w1, l.month) + 1) / extract(day from (l.month + interval '1 month - 1 day'))) n
            from public.kitty_ly l where l.workshop = p_ws and l.month <= w2 and (l.month + interval '1 month - 1 day')::date >= w1 group by 1),
  x as (select caps.cap, coalesce(kit.net, 0) kitty, round(case when manual then coalesce(man.n, 0) else coalesce(own.n, 0) end)::int rep, coalesce(pr.n, 0)::int prn,
               ceil(coalesce(pr.n, 0) * (1 + pc / 100))::int pr2
          from caps left join kit using (cap) left join pr using (cap) left join own using (cap) left join man using (cap))
  select jsonb_agg(jsonb_build_array(cap, kitty, rep, prn, pr2, kitty + rep - pr2, greatest(0, pr2 - kitty - rep)) order by cap), coalesce(bool_or(rep > 0), false) into rows, any_rep from x;
  return jsonb_build_object('rows', rows, 'w1', w1, 'w2', w2, 'days', n, 'pct', pc, 'manual', manual, 'ly_any', any_rep);
end $$;
grant execute on function public.kitty_need_json(text, date, int, numeric) to authenticated;
-- STEP 44 : M&R "REPAIR" tab  (REPAIR / ASSEMBLY / OVEN, firm-wise and capacity-wise, typed by the M&R user)  -- TEST project.
-- Run after step 40..43.  One row = workshop + date + block + firm + capacity -> qty.  Nothing existing is changed.
create table if not exists public.rr_entry (
  workshop text not null, day date not null, block text not null check (block in ('REPAIR','ASSEMBLY','OVEN')),
  firm text not null, cap text not null check (cap in ('10','16','25','63','100','160','250AL','250CU','400','630','1000')),
  qty int not null default 0 check (qty >= 0 and qty <= 100000),
  by_login text, at timestamptz not null default now(),
  primary key (workshop, day, block, firm, cap)
);
alter table public.rr_entry enable row level security;
revoke all on public.rr_entry from public, anon, authenticated;

-- read one day:  rows [block, firm, cap, qty];  firms = firm names of the latest earlier day (to pre-fill an empty day)
create or replace function public.rr_json(p_ws text, p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb; pd date;
begin
  if not public.mr_ok() or not (p_ws = any (public.my_workshops())) then raise exception 'You cannot see this workshop.'; end if;
  select max(day) into pd from public.rr_entry where workshop = p_ws and day < p_day;
  select jsonb_build_object(
    'rows', coalesce((select jsonb_agg(jsonb_build_array(block, firm, cap, qty) order by block, firm, cap) from public.rr_entry where workshop = p_ws and day = p_day), '[]'::jsonb),
    'firms', coalesce((select jsonb_agg(jsonb_build_array(block, firm) order by block, firm) from (select distinct block, firm from public.rr_entry where workshop = p_ws and day = pd) f), '[]'::jsonb),
    'edit', public.mr_edit_ok(p_ws)) into r;
  return r;
end $$;

-- save one day (replaces that day): p_rows = [{block, firm, cap, qty}, ...]
create or replace function public.rr_save(p_ws text, p_day date, p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb; c public.profiles := public.tf_caller(); n int := 0; f text;
begin
  if not public.mr_edit_ok(p_ws) then raise exception 'You cannot change the figures of this workshop.'; end if;
  if p_day is null or p_day > current_date + 1 then raise exception 'Choose today or an earlier date.'; end if;
  delete from public.rr_entry where workshop = p_ws and day = p_day;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    f := btrim(coalesce(e->>'firm', ''));
    if f = '' then continue; end if;
    if length(f) > 60 then raise exception 'Firm name is too long.'; end if;
    if coalesce((e->>'qty')::int, 0) < 0 or coalesce((e->>'qty')::int, 0) > 100000 then raise exception 'Numbers must be 0 or more.'; end if;
    insert into public.rr_entry(workshop, day, block, firm, cap, qty, by_login, at)
      values (p_ws, p_day, e->>'block', f, e->>'cap', coalesce((e->>'qty')::int, 0), c.login_id, now())
      on conflict (workshop, day, block, firm, cap) do update set qty = excluded.qty, by_login = excluded.by_login, at = now();
    n := n + 1;
  end loop;
  return 'saved ' || n;
end $$;
revoke all on function public.rr_json(text, date), public.rr_save(text, date, jsonb) from public, anon;
grant execute on function public.rr_json(text, date), public.rr_save(text, date, jsonb) to authenticated;
notify pgrst, 'reload schema';
-- STEP 45 : M&R "CHAMBER ASSEMBLY" report  -- TEST project.  Run after steps 40..44.
-- One report for a date, all your workshops x capacity (10,16,25,63,100,160,250,400,630,1000):
--   UNREPAIRED   = Kitty-tab unrepaired + the repairs the Kitty already deducted (a repaired T/F comes out of the OVEN, not out of unrepaired) - ASSEMBLY entries
--   AVAILABILITY = Kitty-tab net kitty
--   ASSEMBLY     = start figure + ASSEMBLY entries - OVEN entries
--   OVEN         = start figure + OVEN entries - the daily REPAIR of the Kitty tab (a repaired transformer leaves the oven)
--   Total including Oven & Assembly = availability + assembly + oven
-- The start figures (assembly, oven) are typed ONCE by the Admin and are the figures in the MORNING of the start date (entries of the start date itself are counted).
-- The start figures (assembly, oven) are typed ONCE by the Admin.  The Repair tab's 250(AL) and 250(CU) are added together as 250.
create table if not exists public.ch_base (
  workshop text not null, day date not null, cap int not null check (cap in (10,16,25,63,100,160,250,400,630,1000)),
  assembly int not null default 0 check (assembly >= 0), oven int not null default 0 check (oven >= 0),
  by_login text, at timestamptz not null default now(),
  primary key (workshop, day, cap)
);
alter table public.ch_base enable row level security;
revoke all on public.ch_base from public, anon, authenticated;

create or replace function public.ch_report_json(p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare w text; k jsonb; bd date; out jsonb := '[]'; rj jsonb; nob text[] := '{}'; nok text[] := '{}';
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  for w in select unnest(public.my_workshops()) loop
    k := public.kitty_json(w, p_day);
    if (k->>'base') is null then nok := nok || w; end if;
    select max(day) into bd from public.ch_base where workshop = w and day <= p_day;
    if bd is null then nob := nob || w; end if;
    with caps as (select unnest(array[10,16,25,63,100,160,250,400,630,1000]) cap),
    kr as (select (e->>0)::int cap, (e->>2)::int unrep, (e->>7)::int net from jsonb_array_elements(coalesce(k->'rows', '[]'::jsonb)) e),
    bs as (select cap, assembly, oven from public.ch_base where workshop = w and day = bd),
    kp as (select cap, sum(repair)::int q from public.kitty_day where workshop = w and day < p_day and day >= coalesce((k->>'base')::date, p_day) group by cap),
    ko as (select cap, sum(repair)::int q from public.kitty_day where workshop = w and day <= p_day and (bd is null or day >= bd) group by cap),
    en as (select case when cap in ('250AL','250CU') then 250 else cap::int end cap, block, sum(qty)::int q
             from public.rr_entry where workshop = w and day <= p_day and (bd is null or day >= bd) and block in ('ASSEMBLY','OVEN') group by 1, 2)
    select jsonb_agg(jsonb_build_array(w, caps.cap, coalesce(kr.unrep, 0) + coalesce(kp.q, 0) - coalesce(a.q, 0), coalesce(kr.net, 0),
                                        coalesce(bs.assembly, 0) + coalesce(a.q, 0) - coalesce(o.q, 0), coalesce(bs.oven, 0) + coalesce(o.q, 0) - coalesce(ko.q, 0)) order by caps.cap)
      into rj
      from caps left join kr on kr.cap = caps.cap left join bs on bs.cap = caps.cap left join kp on kp.cap = caps.cap left join ko on ko.cap = caps.cap
                left join en a on a.cap = caps.cap and a.block = 'ASSEMBLY' left join en o on o.cap = caps.cap and o.block = 'OVEN';
    out := out || coalesce(rj, '[]'::jsonb);
  end loop;
  return jsonb_build_object('rows', out, 'nobase', to_jsonb(nob), 'nokitty', to_jsonb(nok));
end $$;

-- the start figures in force on a date: {day, rows [[cap, assembly, oven]]}
create or replace function public.ch_base_json(p_ws text, p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare bd date;
begin
  if not public.mr_ok() or not (p_ws = any (public.my_workshops())) then raise exception 'You cannot see this workshop.'; end if;
  select max(day) into bd from public.ch_base where workshop = p_ws and day <= p_day;
  return jsonb_build_object('day', bd, 'rows', coalesce((select jsonb_agg(jsonb_build_array(cap, assembly, oven) order by cap) from public.ch_base where workshop = p_ws and day = bd), '[]'::jsonb));
end $$;

-- the Admin types the start figures once: p_rows = [{cap, assembly, oven}, ...]
create or replace function public.ch_base_set(p_ws text, p_day date, p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb; c public.profiles := public.tf_caller(); n int := 0;
begin
  if not public.mr_admin_ok(p_ws) then raise exception 'Only the Admin of this workshop can set the start figures.'; end if;
  if p_day is null or p_day > current_date + 1 then raise exception 'Choose today or an earlier date.'; end if;
  delete from public.ch_base where workshop = p_ws and day = p_day;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if (e->>'cap')::int not in (10,16,25,63,100,160,250,400,630,1000) then continue; end if;
    if coalesce((e->>'assembly')::int, 0) < 0 or coalesce((e->>'oven')::int, 0) < 0 or coalesce((e->>'assembly')::int, 0) > 100000 or coalesce((e->>'oven')::int, 0) > 100000 then raise exception 'Numbers must be 0 or more.'; end if;
    insert into public.ch_base(workshop, day, cap, assembly, oven, by_login, at) values (p_ws, p_day, (e->>'cap')::int, coalesce((e->>'assembly')::int, 0), coalesce((e->>'oven')::int, 0), c.login_id, now());
    n := n + 1;
  end loop;
  return 'saved ' || n;
end $$;
revoke all on function public.ch_report_json(date), public.ch_base_json(text, date), public.ch_base_set(text, date, jsonb) from public, anon;
grant execute on function public.ch_report_json(date), public.ch_base_json(text, date), public.ch_base_set(text, date, jsonb) to authenticated;
notify pgrst, 'reload schema';
-- STEP 46 : date check allows 'today' also for users whose day has already turned (India is ahead of the database clock, UTC).
-- Re-creates 4 functions only (no data is touched).  Safe to run again.

create or replace function public.kitty_save(p_ws text, p_day date, p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb; c public.profiles := public.tf_caller(); bd date; n int := 0;
begin
  if not public.mr_edit_ok(p_ws) then raise exception 'You cannot change the kitty of this workshop.'; end if;
  if p_day is null or p_day > current_date + 1 then raise exception 'Choose today or an earlier date.'; end if;
  select max(day) into bd from public.kitty_base where workshop = p_ws and day <= p_day;
  if bd is null then raise exception 'The Admin must first set the opening kitty and the unrepaired T/F (start date).'; end if;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if (e->>'cap')::int not in (10, 16, 25, 63, 100, 160, 250, 400, 630) then continue; end if;
    if coalesce((e->>'repair')::int, 0) < 0 or coalesce((e->>'to_other')::int, 0) < 0 or coalesce((e->>'from_other')::int, 0) < 0
       or coalesce((e->>'repair')::int, 0) > 100000 or coalesce((e->>'to_other')::int, 0) > 100000 or coalesce((e->>'from_other')::int, 0) > 100000 then raise exception 'Numbers must be 0 or more.'; end if;
    insert into public.kitty_day(workshop, day, cap, repair, to_other, from_other, by_login, at)
      values (p_ws, p_day, (e->>'cap')::int, coalesce((e->>'repair')::int, 0), coalesce((e->>'to_other')::int, 0), coalesce((e->>'from_other')::int, 0), c.login_id, now())
      on conflict (workshop, day, cap) do update set repair = excluded.repair, to_other = excluded.to_other, from_other = excluded.from_other, by_login = excluded.by_login, at = now();
    n := n + 1;
  end loop;
  return 'saved ' || n;
end $$;

create or replace function public.kitty_base_set(p_ws text, p_day date, p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb; c public.profiles := public.tf_caller(); n int := 0;
begin
  if not public.mr_admin_ok(p_ws) then raise exception 'Only the Admin of this workshop can set the start figures.'; end if;
  if p_day is null or p_day > current_date + 1 then raise exception 'Choose today or an earlier date.'; end if;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if (e->>'cap')::int not in (10, 16, 25, 63, 100, 160, 250, 400, 630) then continue; end if;
    if coalesce((e->>'opening')::int, 0) < 0 or coalesce((e->>'unrep')::int, 0) < 0 then raise exception 'Numbers must be 0 or more.'; end if;
    insert into public.kitty_base(workshop, day, cap, opening, unrep, by_login, at)
      values (p_ws, p_day, (e->>'cap')::int, coalesce((e->>'opening')::int, 0), coalesce((e->>'unrep')::int, 0), c.login_id, now())
      on conflict (workshop, day, cap) do update set opening = excluded.opening, unrep = excluded.unrep, by_login = excluded.by_login, at = now();
    n := n + 1;
  end loop;
  return 'saved ' || n;
end $$;

create or replace function public.rr_save(p_ws text, p_day date, p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb; c public.profiles := public.tf_caller(); n int := 0; f text;
begin
  if not public.mr_edit_ok(p_ws) then raise exception 'You cannot change the figures of this workshop.'; end if;
  if p_day is null or p_day > current_date + 1 then raise exception 'Choose today or an earlier date.'; end if;
  delete from public.rr_entry where workshop = p_ws and day = p_day;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    f := btrim(coalesce(e->>'firm', ''));
    if f = '' then continue; end if;
    if length(f) > 60 then raise exception 'Firm name is too long.'; end if;
    if coalesce((e->>'qty')::int, 0) < 0 or coalesce((e->>'qty')::int, 0) > 100000 then raise exception 'Numbers must be 0 or more.'; end if;
    insert into public.rr_entry(workshop, day, block, firm, cap, qty, by_login, at)
      values (p_ws, p_day, e->>'block', f, e->>'cap', coalesce((e->>'qty')::int, 0), c.login_id, now())
      on conflict (workshop, day, block, firm, cap) do update set qty = excluded.qty, by_login = excluded.by_login, at = now();
    n := n + 1;
  end loop;
  return 'saved ' || n;
end $$;

create or replace function public.ch_base_set(p_ws text, p_day date, p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb; c public.profiles := public.tf_caller(); n int := 0;
begin
  if not public.mr_admin_ok(p_ws) then raise exception 'Only the Admin of this workshop can set the start figures.'; end if;
  if p_day is null or p_day > current_date + 1 then raise exception 'Choose today or an earlier date.'; end if;
  delete from public.ch_base where workshop = p_ws and day = p_day;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if (e->>'cap')::int not in (10,16,25,63,100,160,250,400,630,1000) then continue; end if;
    if coalesce((e->>'assembly')::int, 0) < 0 or coalesce((e->>'oven')::int, 0) < 0 or coalesce((e->>'assembly')::int, 0) > 100000 or coalesce((e->>'oven')::int, 0) > 100000 then raise exception 'Numbers must be 0 or more.'; end if;
    insert into public.ch_base(workshop, day, cap, assembly, oven, by_login, at) values (p_ws, p_day, (e->>'cap')::int, coalesce((e->>'assembly')::int, 0), coalesce((e->>'oven')::int, 0), c.login_id, now());
    n := n + 1;
  end loop;
  return 'saved ' || n;
end $$;

notify pgrst, 'reload schema';

-- STEP 47 : SIR (Site Inspection Report) - link the Google Sheet where the SIR form saves its data.
-- Run after the earlier steps.  The Admin of a division stores ONE link (a Google Sheet "Publish to web" CSV link) and the heading of the column
-- that holds the Indent / PR number.  The app reads that sheet in the browser and counts a 100 KVA & above PR as "SIR done" when its number is found.
-- Nothing existing is changed.
create table if not exists public.sir_cfg (
  org_division text primary key,
  url text not null check (url ~ '^https://docs\.google\.com/spreadsheets/' and length(url) <= 700),
  col text not null default 'INDENT NO' check (length(btrim(col)) between 1 and 60),
  by_login text, at timestamptz not null default now()
);
alter table public.sir_cfg enable row level security;
revoke all on public.sir_cfg from public, anon, authenticated;

-- the link(s) of the divisions the caller works in: [{division, url, col}]
create or replace function public.sir_cfg_get() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('division', c.org_division, 'url', c.url, 'col', c.col)), '[]'::jsonb)
    from public.sir_cfg c
   where c.org_division in (select w.org_division from public.workshops w where w.name = any (coalesce(public.my_workshops(), '{}')))
$$;

-- the Admin saves / removes the link of his division (empty url = remove)
create or replace function public.sir_cfg_set(p_url text, p_col text) returns text
language plpgsql security definer set search_path = public as $$
declare c public.profiles := public.tf_caller(); u text := btrim(coalesce(p_url, '')); k text := btrim(coalesce(p_col, ''));
begin
  if c.user_id is null or c.role <> 'admin' or not c.active or c.org_division is null then raise exception 'Only the Admin of the division can link the SIR sheet.'; end if;
  if u = '' then delete from public.sir_cfg where org_division = c.org_division; return 'removed'; end if;
  if u !~ '^https://docs\.google\.com/spreadsheets/' then raise exception 'This is not a Google Sheet link. Use the link you get from File > Share > Publish to web.'; end if;
  if length(u) > 700 then raise exception 'The link is too long.'; end if;
  if k = '' then k := 'INDENT NO'; end if;
  if length(k) > 60 then raise exception 'The column heading is too long.'; end if;
  insert into public.sir_cfg(org_division, url, col, by_login, at) values (c.org_division, u, k, c.login_id, now())
    on conflict (org_division) do update set url = excluded.url, col = excluded.col, by_login = excluded.by_login, at = now();
  return 'saved';
end $$;

-- the 100 KVA & above PRs of the caller's workshops raised between two dates: [workshop, division, capacity, pr_no, pr_date]
-- (wrong / duplicate PRs and rows without a PR date are not counted, like the Summary)
create or replace function public.sir_prs_json(p_from date, p_to date) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_array(d.workshop, w.org_division, d.capacity, d.pr_no, to_char(d.pr_date, 'YYYY-MM-DD')) order by d.pr_date, d.pr_no), '[]'::jsonb)
    from (select * from public.data
           where workshop = any (coalesce((select public.my_workshops()), '{}')) and capacity >= 100 and pr_date between p_from and p_to
             and not public.is_dup(firm) limit 20000) d
    join public.workshops w on w.name = d.workshop
$$;
revoke all on function public.sir_cfg_get(), public.sir_cfg_set(text, text), public.sir_prs_json(date, date) from public, anon;
grant execute on function public.sir_cfg_get(), public.sir_cfg_set(text, text), public.sir_prs_json(date, date) to authenticated;
notify pgrst, 'reload schema';

-- STEP 48 : (a) a division name with two spaces inside ("EWD  AZAMGARH") is the SAME division as "EWD AZAMGARH" - everywhere
--           (b) the Pending SIR numbers open the list of those PRs
-- Run after step 47.  Safe to run again.

-- (a) one spelling of every division name: spaces trimmed and a run of spaces / tabs becomes a single space
create or replace function public.tf_sp(t text) returns text language sql immutable as
  $$ select nullif(btrim(regexp_replace(coalesce(t, ''), '\s+', ' ', 'g')), '') $$;

create or replace function public.tf_trg_div_org() returns trigger language plpgsql as
$$ begin new.org_division := public.tf_sp(new.org_division); return new; end $$;
create or replace function public.tf_trg_div_data() returns trigger language plpgsql as
$$ begin if new.division is not null then new.division := coalesce(public.tf_sp(new.division), ''); end if; return new; end $$;
create or replace function public.tf_trg_div_map() returns trigger language plpgsql as
$$ begin new.division := coalesce(public.tf_sp(new.division), new.division); new.circle := coalesce(public.tf_sp(new.circle), new.circle); return new; end $$;

drop trigger if exists tf_div_ws on public.workshops;
create trigger tf_div_ws before insert or update of org_division on public.workshops for each row execute function public.tf_trg_div_org();
drop trigger if exists tf_div_pr on public.profiles;
create trigger tf_div_pr before insert or update of org_division on public.profiles for each row execute function public.tf_trg_div_org();
drop trigger if exists tf_div_data on public.data;
create trigger tf_div_data before insert or update of division on public.data for each row execute function public.tf_trg_div_data();
drop trigger if exists tf_div_map on public.divmap;
create trigger tf_div_map before insert or update of division, circle on public.divmap for each row execute function public.tf_trg_div_map();

-- clean what is already there (only rows that really change)
update public.workshops set org_division = public.tf_sp(org_division) where org_division is distinct from public.tf_sp(org_division);
update public.profiles  set org_division = public.tf_sp(org_division) where org_division is distinct from public.tf_sp(org_division);
update public.divmap    set division = public.tf_sp(division), circle = public.tf_sp(circle)
 where division is distinct from public.tf_sp(division) or circle is distinct from public.tf_sp(circle);
update public.data      set division = coalesce(public.tf_sp(division), '')
 where division is not null and division is distinct from coalesce(public.tf_sp(division), '');
-- (the SIR link and the installed-count tables use the division name as a key: merge the ones that were written with extra spaces)
update public.installed i set org_division = public.tf_sp(i.org_division)
 where i.org_division is distinct from public.tf_sp(i.org_division)
   and not exists (select 1 from public.installed j where j.org_division = public.tf_sp(i.org_division) and j.div_key = i.div_key and j.yr = i.yr);
delete from public.installed where org_division is distinct from public.tf_sp(org_division);
update public.sir_cfg s set org_division = public.tf_sp(s.org_division)
 where s.org_division is distinct from public.tf_sp(s.org_division) and not exists (select 1 from public.sir_cfg x where x.org_division = public.tf_sp(s.org_division));
delete from public.sir_cfg where org_division is distinct from public.tf_sp(org_division);

-- (b) the PRs behind a SIR PENDING number: same row shape as the other lists
create or replace function public.sir_rows_json(p_ws text, p_caps int[], p_prs text[], p_limit int default 300, p_offset int default 0)
returns jsonb language sql stable security invoker set search_path = public as
$$
  with h as (
    select d.* from public.data d
     where (p_ws is null or d.workshop = p_ws) and (p_caps is null or coalesce(d.capacity, 0) = any (p_caps))
       and d.pr_no = any (coalesce(p_prs, '{}')) and not public.is_dup(d.firm)
  ), top as (
    select * from h order by coalesce(pr_date, date '1900-01-01'), pr_no collate "C" limit least(greatest(p_limit, 1), 2000) offset greatest(p_offset, 0)
  )
  select jsonb_build_object('total', (select count(*) from h),
    'rows', coalesce((select jsonb_agg(public.row20(t) || to_jsonb((select case when public.can_edit_rows() then 1 else 0 end)) order by coalesce(t.pr_date, date '1900-01-01'), t.pr_no collate "C") from top t), '[]'::jsonb))
$$;
revoke all on function public.sir_rows_json(text, int[], text[], int, int) from public, anon;
grant execute on function public.sir_rows_json(text, int[], text[], int, int) to authenticated;
notify pgrst, 'reload schema';

-- STEP 49 : (a) the Kitty REPAIR column comes from the Repair tab, day by day   (b) M&R "SCRAP" tab
-- Run after steps 40..48.  Safe to run again.

-- (a) KITTY REPAIR = the REPAIR block of the Repair tab (all firms added), per capacity; 250(AL) + 250(CU) = 250 ----------
create or replace function public.rr_cap_n(p_ws text, p_day date, p_cap int) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(sum(qty), 0)::int from public.rr_entry
   where workshop = p_ws and day = p_day and block = 'REPAIR' and (cap = p_cap::text or (p_cap = 250 and cap in ('250AL', '250CU')))
$$;
revoke all on function public.rr_cap_n(text, date, int) from public, anon, authenticated;

create or replace function public.kitty_sync_repair(p_ws text, p_day date) returns void
language sql security definer set search_path = public as $$
  insert into public.kitty_day(workshop, day, cap, repair, by_login, at)
  select p_ws, p_day, c, public.rr_cap_n(p_ws, p_day, c), 'repair-tab', now() from unnest(array[10, 16, 25, 63, 100, 160, 250, 400, 630]) c
  on conflict (workshop, day, cap) do update set repair = excluded.repair
$$;
revoke all on function public.kitty_sync_repair(text, date) from public, anon, authenticated;

-- the kitty save no longer takes the repair figure (it is read from the Repair tab)
create or replace function public.kitty_save(p_ws text, p_day date, p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb; c public.profiles := public.tf_caller(); bd date; n int := 0;
begin
  if not public.mr_edit_ok(p_ws) then raise exception 'You cannot change the kitty of this workshop.'; end if;
  if p_day is null or p_day > current_date + 1 then raise exception 'Choose today or an earlier date.'; end if;
  select max(day) into bd from public.kitty_base where workshop = p_ws and day <= p_day;
  if bd is null then raise exception 'The Admin must first set the opening kitty and the unrepaired T/F (start date).'; end if;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if (e->>'cap')::int not in (10, 16, 25, 63, 100, 160, 250, 400, 630) then continue; end if;
    if coalesce((e->>'to_other')::int, 0) < 0 or coalesce((e->>'from_other')::int, 0) < 0
       or coalesce((e->>'to_other')::int, 0) > 100000 or coalesce((e->>'from_other')::int, 0) > 100000 then raise exception 'Numbers must be 0 or more.'; end if;
    insert into public.kitty_day(workshop, day, cap, repair, to_other, from_other, by_login, at)
      values (p_ws, p_day, (e->>'cap')::int, public.rr_cap_n(p_ws, p_day, (e->>'cap')::int), coalesce((e->>'to_other')::int, 0), coalesce((e->>'from_other')::int, 0), c.login_id, now())
      on conflict (workshop, day, cap) do update set to_other = excluded.to_other, from_other = excluded.from_other, by_login = excluded.by_login, at = now();
    n := n + 1;
  end loop;
  return 'saved ' || n;
end $$;

-- the Repair tab save also writes the kitty repair of that day
create or replace function public.rr_save(p_ws text, p_day date, p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb; c public.profiles := public.tf_caller(); n int := 0; f text;
begin
  if not public.mr_edit_ok(p_ws) then raise exception 'You cannot change the figures of this workshop.'; end if;
  if p_day is null or p_day > current_date + 1 then raise exception 'Choose today or an earlier date.'; end if;
  delete from public.rr_entry where workshop = p_ws and day = p_day;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    f := btrim(coalesce(e->>'firm', ''));
    if f = '' then continue; end if;
    if length(f) > 60 then raise exception 'Firm name is too long.'; end if;
    if coalesce((e->>'qty')::int, 0) < 0 or coalesce((e->>'qty')::int, 0) > 100000 then raise exception 'Numbers must be 0 or more.'; end if;
    insert into public.rr_entry(workshop, day, block, firm, cap, qty, by_login, at)
      values (p_ws, p_day, e->>'block', f, e->>'cap', coalesce((e->>'qty')::int, 0), c.login_id, now())
      on conflict (workshop, day, block, firm, cap) do update set qty = excluded.qty, by_login = excluded.by_login, at = now();
    n := n + 1;
  end loop;
  perform public.kitty_sync_repair(p_ws, p_day);
  return 'saved ' || n;
end $$;

-- days already typed in the Repair tab: copy their repair to the kitty now
do $$ declare r record; begin
  for r in select distinct workshop, day from public.rr_entry where block = 'REPAIR' loop perform public.kitty_sync_repair(r.workshop, r.day); end loop;
end $$;

-- (b) SCRAP ----------------------------------------------------------------------------------------------------------
-- scrap received (kg) of a day = Repair-tab REPAIR quantity (10..250 aluminium only) x standard qty x recovery %.
-- opening scrap = the Admin types it once (a start date); after that: opening of a day = remaining of the day before.
-- remaining = opening + receive - issue for reconditioning - auctioned.
create table if not exists public.scrap_cfg (id int primary key default 1 check (id = 1), pct numeric not null default 97 check (pct > 0 and pct <= 100));
insert into public.scrap_cfg(id) values (1) on conflict do nothing;
create table if not exists public.scrap_std (cap text primary key, qty numeric not null check (qty >= 0 and qty < 100000), ord int not null);
insert into public.scrap_std(cap, qty, ord) values ('10', 11, 1), ('16', 20, 2), ('25', 25, 3), ('63', 50, 4), ('100', 69, 5), ('160', 90, 6), ('250AL', 115, 7) on conflict do nothing;
create table if not exists public.scrap_base (workshop text not null, day date not null, opening numeric not null default 0 check (opening >= 0), by_login text, at timestamptz not null default now(), primary key (workshop, day));
create table if not exists public.scrap_day (workshop text not null, day date not null, issue numeric not null default 0 check (issue >= 0), auction numeric not null default 0 check (auction >= 0), by_login text, at timestamptz not null default now(), primary key (workshop, day));
alter table public.scrap_cfg enable row level security; alter table public.scrap_std enable row level security;
alter table public.scrap_base enable row level security; alter table public.scrap_day enable row level security;
revoke all on public.scrap_cfg, public.scrap_std, public.scrap_base, public.scrap_day from public, anon, authenticated;

create or replace function public.scrap_rcv(p_ws text, p_d1 date, p_d2 date) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(e.qty * s.qty * (select pct from public.scrap_cfg) / 100), 0)
    from public.rr_entry e join public.scrap_std s on s.cap = e.cap
   where e.workshop = p_ws and e.block = 'REPAIR' and e.day between p_d1 and p_d2
$$;
revoke all on function public.scrap_rcv(text, date, date) from public, anon, authenticated;

-- one workshop, one day -> {nobase, opening, receive, issue, auction, remaining}
create or replace function public.scrap_calc(p_ws text, p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare bd date; op numeric := 0; o numeric; rc numeric; i numeric := 0; a numeric := 0;
begin
  select max(day) into bd from public.scrap_base where workshop = p_ws and day <= p_day;
  if bd is not null then select opening into op from public.scrap_base where workshop = p_ws and day = bd; else bd := date '2000-01-01'; end if;
  o := op + public.scrap_rcv(p_ws, bd, p_day - 1) - coalesce((select sum(issue + auction) from public.scrap_day where workshop = p_ws and day between bd and p_day - 1), 0);
  rc := public.scrap_rcv(p_ws, p_day, p_day);
  select coalesce(issue, 0), coalesce(auction, 0) into i, a from public.scrap_day where workshop = p_ws and day = p_day;
  i := coalesce(i, 0); a := coalesce(a, 0);
  return jsonb_build_object('nobase', not exists (select 1 from public.scrap_base where workshop = p_ws and day <= p_day),
    'opening', round(o, 2), 'receive', round(rc, 2), 'issue', round(i, 2), 'auction', round(a, 2), 'remaining', round(o + rc - i - a, 2));
end $$;
revoke all on function public.scrap_calc(text, date) from public, anon, authenticated;

-- the SCRAP SUMMARY of a date: rows [workshop, opening, receive, issue, auction, remaining, can_edit, is_admin]
create or replace function public.scrap_json(p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare w text; k jsonb; rows jsonb := '[]'; nob text[] := '{}';
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  for w in select unnest(public.my_workshops()) order by 1 loop
    k := public.scrap_calc(w, p_day);
    if (k->>'nobase')::boolean then nob := nob || w; end if;
    rows := rows || jsonb_build_array(jsonb_build_array(w, k->'opening', k->'receive', k->'issue', k->'auction', k->'remaining', public.mr_edit_ok(w), public.mr_admin_ok(w)));
  end loop;
  return jsonb_build_object('rows', rows, 'nobase', to_jsonb(nob), 'pct', (select pct from public.scrap_cfg));
end $$;

-- capacity-wise scrap receive of one workshop and day: rows [cap, repaired qty, std qty, kg per T/F, scrap kg]  +  the standard list
create or replace function public.scrap_cap_json(p_ws text, p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pct numeric;
begin
  if not public.mr_ok() or not (p_ws = any (public.my_workshops())) then raise exception 'You cannot see this workshop.'; end if;
  select c.pct into pct from public.scrap_cfg c;
  return jsonb_build_object('pct', pct, 'admin', public.mr_admin_ok(p_ws),
    'rows', coalesce((select jsonb_agg(jsonb_build_array(s.cap, q.n, s.qty, round(s.qty * pct / 100, 2), round(q.n * s.qty * pct / 100, 2)) order by s.ord)
      from public.scrap_std s, lateral (select coalesce(sum(e.qty), 0)::int n from public.rr_entry e where e.workshop = p_ws and e.day = p_day and e.block = 'REPAIR' and e.cap = s.cap) q), '[]'::jsonb),
    'base', (select jsonb_build_object('day', day, 'opening', opening) from public.scrap_base where workshop = p_ws and day <= p_day order by day desc limit 1));
end $$;

-- the M&R user types the day's "issue for reconditioning" and "scrap auctioned" (kg)
create or replace function public.scrap_save(p_ws text, p_day date, p_issue numeric, p_auction numeric) returns text
language plpgsql security definer set search_path = public as $$
declare c public.profiles := public.tf_caller(); k jsonb;
begin
  if not public.mr_edit_ok(p_ws) then raise exception 'You cannot change the scrap of this workshop.'; end if;
  if p_day is null or p_day > current_date + 1 then raise exception 'Choose today or an earlier date.'; end if;
  if coalesce(p_issue, 0) < 0 or coalesce(p_auction, 0) < 0 or coalesce(p_issue, 0) > 100000000 or coalesce(p_auction, 0) > 100000000 then raise exception 'Numbers must be 0 or more.'; end if;
  insert into public.scrap_day(workshop, day, issue, auction, by_login, at) values (p_ws, p_day, round(coalesce(p_issue, 0), 2), round(coalesce(p_auction, 0), 2), c.login_id, now())
    on conflict (workshop, day) do update set issue = excluded.issue, auction = excluded.auction, by_login = excluded.by_login, at = now();
  k := public.scrap_calc(p_ws, p_day);
  if (k->>'remaining')::numeric < 0 then raise exception 'Issue + auctioned is more than the scrap available (% kg).', round((k->>'opening')::numeric + (k->>'receive')::numeric, 2); end if;
  return 'saved';
end $$;

-- Admin: opening scrap on a start date, standard qty per capacity, recovery %
create or replace function public.scrap_base_set(p_ws text, p_day date, p_opening numeric) returns text
language plpgsql security definer set search_path = public as $$
declare c public.profiles := public.tf_caller();
begin
  if not public.mr_admin_ok(p_ws) then raise exception 'Only the Admin of this workshop can set the opening scrap.'; end if;
  if p_day is null or p_day > current_date + 1 then raise exception 'Choose today or an earlier date.'; end if;
  if coalesce(p_opening, 0) < 0 or coalesce(p_opening, 0) > 100000000 then raise exception 'Numbers must be 0 or more.'; end if;
  insert into public.scrap_base(workshop, day, opening, by_login, at) values (p_ws, p_day, round(coalesce(p_opening, 0), 2), c.login_id, now())
    on conflict (workshop, day) do update set opening = excluded.opening, by_login = excluded.by_login, at = now();
  return 'saved';
end $$;

create or replace function public.scrap_std_set(p_pct numeric, p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb; c public.profiles := public.tf_caller();
begin
  if c.user_id is null or c.role <> 'admin' or not c.active then raise exception 'Only an Admin can change the standard.'; end if;
  if p_pct is null or p_pct <= 0 or p_pct > 100 then raise exception 'Recovery %% must be between 1 and 100.'; end if;
  update public.scrap_cfg set pct = p_pct;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if coalesce((e->>'qty')::numeric, -1) < 0 or (e->>'qty')::numeric >= 100000 then raise exception 'Standard qty must be 0 or more.'; end if;
    update public.scrap_std set qty = (e->>'qty')::numeric where cap = e->>'cap';
  end loop;
  return 'saved';
end $$;

revoke all on function public.scrap_json(date), public.scrap_cap_json(text, date), public.scrap_save(text, date, numeric, numeric), public.scrap_base_set(text, date, numeric), public.scrap_std_set(numeric, jsonb) from public, anon;
grant execute on function public.scrap_json(date), public.scrap_cap_json(text, date), public.scrap_save(text, date, numeric, numeric), public.scrap_base_set(text, date, numeric), public.scrap_std_set(numeric, jsonb) to authenticated;
notify pgrst, 'reload schema';

-- ================================================================================================================
-- STEP 80 : (1) Data Sheet shows DTC NO + DTC DATE   (2) Scrap summary from date to date   (3) Kitty gets 1000 KVA
-- Safe to run again. No data is deleted.
-- ================================================================================================================

-- (1) DTC no / date of the rows shown in the Data Sheet.  p_keys = [[workshop, pr_no], ...]  ->  rows [workshop, pr_no, id, dtc_no, dtc_date DD.MM.YYYY, can_edit]
create or replace function public.dtc_map_json(p_keys jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare mine text[] := public.my_workshops(); ed text[];
begin
  if not public.mr_ok() then return jsonb_build_object('ok', false, 'rows', '[]'::jsonb); end if;
  select coalesce(array_agg(w), '{}') into ed from unnest(mine) w where public.mr_edit_ok(w);
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_array(x.workshop, x.pr_no, x.id, coalesce(t.dtc_no, ''), coalesce(to_char(t.dtc_date, 'DD.MM.YYYY'), ''), x.workshop = any (ed)))
      from jsonb_array_elements(coalesce(p_keys, '[]'::jsonb)) k
      join public.data x on x.workshop = k->>0 and x.pr_no = k->>1 and x.workshop = any (mine)
      left join public.dtc t on t.data_id = x.id), '[]'::jsonb));
end $$;

-- (2) Scrap summary of a period: totals + the dates on which scrap was issued for reconditioning / auctioned
create or replace function public.scrap_range_json(p_from date, p_to date, p_ws text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ws text[]; rc numeric := 0; w text;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Choose the From and To dates (From must not be after To).'; end if;
  if p_to - p_from > 1100 then raise exception 'Choose a period of up to 3 years.'; end if;
  if coalesce(p_ws, '') <> '' then
    if not (p_ws = any (public.my_workshops())) then raise exception 'This workshop is not yours.'; end if;
    ws := array[p_ws];
  else ws := public.my_workshops(); end if;
  foreach w in array ws loop rc := rc + public.scrap_rcv(w, p_from, p_to); end loop;
  return jsonb_build_object('receive', round(rc, 2),
    'issue', round(coalesce((select sum(issue) from public.scrap_day where workshop = any (ws) and day between p_from and p_to), 0), 2),
    'auction', round(coalesce((select sum(auction) from public.scrap_day where workshop = any (ws) and day between p_from and p_to), 0), 2),
    'rows', coalesce((select jsonb_agg(jsonb_build_array(day, workshop, issue, auction) order by day desc, workshop)
                        from public.scrap_day where workshop = any (ws) and day between p_from and p_to and (issue > 0 or auction > 0)), '[]'::jsonb));
end $$;

revoke all on function public.dtc_map_json(jsonb), public.scrap_range_json(date, date, text) from public, anon;
grant execute on function public.dtc_map_json(jsonb), public.scrap_range_json(date, date, text) to authenticated;

-- (3) Kitty: add 1000 KVA to every kitty function (the capacity lists inside the function texts are rewritten)
do $$
declare f record; d text; n text;
begin
  for f in select p.oid from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.proname in ('kitty_json', 'kitty_save', 'kitty_base_set', 'kitty_ly_json', 'kitty_ly_set', 'kitty_need_json', 'kitty_cmp_json', 'rr_save') loop
    d := pg_get_functiondef(f.oid);
    n := replace(replace(d, 'array[10, 16, 25, 63, 100, 160, 250, 400, 630]', 'array[10, 16, 25, 63, 100, 160, 250, 400, 630, 1000]'),
                            '(10, 16, 25, 63, 100, 160, 250, 400, 630)', '(10, 16, 25, 63, 100, 160, 250, 400, 630, 1000)');
    if n <> d then execute n; end if;
  end loop;
end $$;
notify pgrst, 'reload schema';

-- ================================================================================================================
-- STEP 81 : Kitty compared with last year (kitty of the same date last year)
-- If the app already counted the kitty on that date last year it is used automatically; otherwise it is typed once
-- (per workshop and date) and saved in kitty_lyk. Safe to run again.
-- ================================================================================================================
create table if not exists public.kitty_lyk (
  workshop text not null, day date not null, cap int not null,
  qty int not null default 0 check (qty >= 0),
  by_login text, at timestamptz not null default now(),
  primary key (workshop, day, cap)
);
alter table public.kitty_lyk enable row level security;
revoke all on public.kitty_lyk from public, anon, authenticated;

create or replace function public.kitty_lyk_json(p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ly date := (p_day - interval '1 year')::date; w text; a jsonb; b jsonb; auto boolean; rows jsonb; outj jsonb := '[]'::jsonb;
        caps int[] := array[10, 16, 25, 63, 100, 160, 250, 400, 630, 1000];
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  foreach w in array public.my_workshops() loop
    a := public.kitty_json(w, p_day);
    if (a->>'base') is null then continue; end if;
    b := public.kitty_json(w, ly);
    auto := (b->>'base') is not null;
    select jsonb_agg(jsonb_build_array(c,
             coalesce((select (x->>7)::int from jsonb_array_elements(a->'rows') x where (x->>0)::int = c), 0),
             case when auto then coalesce((select (x->>7)::int from jsonb_array_elements(b->'rows') x where (x->>0)::int = c), 0)
                  else coalesce((select k.qty from public.kitty_lyk k where k.workshop = w and k.day = ly and k.cap = c), 0) end) order by c)
      into rows from unnest(caps) c;
    outj := outj || jsonb_build_array(jsonb_build_object('ws', w, 'auto', auto, 'edit', public.mr_edit_ok(w), 'rows', rows));
  end loop;
  return jsonb_build_object('ly', ly, 'ws', outj);
end $$;

create or replace function public.kitty_lyk_set(p_ws text, p_day date, p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb; c public.profiles := public.tf_caller(); n int := 0;
begin
  if not public.mr_edit_ok(p_ws) then raise exception 'You cannot change the kitty of this workshop.'; end if;
  if p_day is null or p_day >= current_date then raise exception 'Choose a day of the past.'; end if;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if (e->>'cap')::int not in (10, 16, 25, 63, 100, 160, 250, 400, 630, 1000) then continue; end if;
    if coalesce((e->>'qty')::int, 0) < 0 or coalesce((e->>'qty')::int, 0) > 100000 then raise exception 'Numbers must be 0 or more.'; end if;
    insert into public.kitty_lyk(workshop, day, cap, qty, by_login, at) values (p_ws, p_day, (e->>'cap')::int, coalesce((e->>'qty')::int, 0), c.login_id, now())
      on conflict (workshop, day, cap) do update set qty = excluded.qty, by_login = excluded.by_login, at = now();
    n := n + 1;
  end loop;
  return 'saved ' || n;
end $$;

revoke all on function public.kitty_lyk_json(date), public.kitty_lyk_set(text, date, jsonb) from public, anon;
grant execute on function public.kitty_lyk_json(date), public.kitty_lyk_set(text, date, jsonb) to authenticated;
notify pgrst, 'reload schema';

-- ================================================================================================================
-- STEP 83 : Comparison - day-wise PR and Repair (selected dates against the same dates of last year)
-- PR = PRs of the Data Sheet by PR date (duplicates not counted, like the Comparison). Repair = the REPAIR block of the Repair tab.
-- Safe to run again.
-- ================================================================================================================
create or replace function public.daywise_json(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.profiles := public.tf_caller(); pf date := (p_from - interval '1 year')::date; pt date := (p_to - interval '1 year')::date; ws text[]; a jsonb; b jsonb;
begin
  if c.user_id is null or not c.active or c.role not in ('admin', 'je', 'discom', 'creator') then raise exception 'Not allowed.'; end if;
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Choose the From and To dates.'; end if;
  if p_to - p_from > 400 then raise exception 'Choose a period of up to 13 months.'; end if;
  select coalesce(array_agg(w.name), '{}') into ws from public.workshops w
   where c.role in ('discom', 'creator') or c.org_division is null or w.org_division = c.org_division;
  select coalesce(jsonb_agg(jsonb_build_array(q.per, q.wsn, q.dy, q.n)), '[]'::jsonb) into a from (
    select 'c'::text as per, d.workshop as wsn, d.pr_date as dy, count(*) as n from public.data d
     where not d.dup and d.workshop = any (ws) and d.pr_date between p_from and p_to group by d.workshop, d.pr_date
    union all
    select 'p'::text as per, d.workshop as wsn, d.pr_date as dy, count(*) as n from public.data d
     where not d.dup and d.workshop = any (ws) and d.pr_date between pf and pt group by d.workshop, d.pr_date) q;
  select coalesce(jsonb_agg(jsonb_build_array(q.per, q.wsn, q.dy, q.n)), '[]'::jsonb) into b from (
    select 'c'::text as per, e.workshop as wsn, e.day as dy, sum(e.qty)::int as n from public.rr_entry e
     where e.block = 'REPAIR' and e.workshop = any (ws) and e.day between p_from and p_to group by e.workshop, e.day
    union all
    select 'p'::text as per, e.workshop as wsn, e.day as dy, sum(e.qty)::int as n from public.rr_entry e
     where e.block = 'REPAIR' and e.workshop = any (ws) and e.day between pf and pt group by e.workshop, e.day) q;
  return jsonb_build_object('pr', a, 'rp', b);
end $$;
revoke all on function public.daywise_json(date, date) from public, anon;
grant execute on function public.daywise_json(date, date) to authenticated;
notify pgrst, 'reload schema';

-- ================================================================================================================
-- STEP 85 : M&R - click on "Pending for DTC" opens the list of those PRs (same columns as the old DTC sheet)
-- p_from / p_to = PR date range of the M&R Summary, p_ws = one workshop (or null = all), p_cap = one capacity (or null = all)
-- Safe to run again.
-- ================================================================================================================
create or replace function public.mr_pending_json(p_from date, p_to date, p_ws text default null, p_cap int default null) returns jsonb
language plpgsql stable set search_path = public as $$
declare r jsonb;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  with b as (select x.*, t.dtc_no, t.dtc_date
               from public.data x left join public.dtc t on t.data_id = x.id
              where not x.dup and x.workshop = any (coalesce((select public.my_workshops()), '{}')) and x.pr_date between p_from and p_to
                and nullif(btrim(t.dtc_no), '') is null
                and (p_ws is null or x.workshop = p_ws) and (p_cap is null or coalesce(x.capacity, 0) = p_cap))
  select jsonb_build_object('total', (select count(*) from b),
    'rows', coalesce((select jsonb_agg(jsonb_build_array(z.id, z.workshop, z.division, z.substation, z.feeder, z.place_of_damage, z.capacity, z.complain_no, z.pr_no, z.pr_date, z.je_name, z.firm, z.driver_name, z.return_date, z.dtc_no, z.dtc_date,
                        case when public.mr_edit_ok(z.workshop) then 1 else 0 end) order by z.pr_date, z.pr_no collate "C")
                        from (select * from b order by pr_date, pr_no collate "C" limit 500) z), '[]'::jsonb))
    into r;
  return r;
end $$;
revoke all on function public.mr_pending_json(date, date, text, int) from public, anon;
grant execute on function public.mr_pending_json(date, date, text, int) to authenticated;
notify pgrst, 'reload schema';

-- ================================================================================================================
-- STEP 86 : Repair summary from date to date (firm and capacity wise)
-- p_block = 'REPAIR' (transformers repaired) / 'ASSEMBLY' / 'OVEN'. Rows come back as [workshop, firm, cap, qty].
-- Safe to run again.
-- ================================================================================================================
create or replace function public.rr_summary_json(p_from date, p_to date, p_ws text default null, p_block text default 'REPAIR') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Choose the From and To dates (From must not be after To).'; end if;
  if p_to - p_from > 1100 then raise exception 'Choose a period of up to 3 years.'; end if;
  if coalesce(p_ws, '') <> '' and not (p_ws = any (public.my_workshops())) then raise exception 'This workshop is not yours.'; end if;
  if p_block not in ('REPAIR', 'ASSEMBLY', 'OVEN') then raise exception 'Unknown block.'; end if;
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(jsonb_build_array(q.workshop, q.firm, q.cap, q.qty) order by q.firm, q.workshop, q.cap)
      from (select e.workshop, e.firm, e.cap, sum(e.qty)::int as qty
              from public.rr_entry e
             where e.block = p_block and e.day between p_from and p_to
               and e.workshop = any (coalesce((select public.my_workshops()), '{}'))
               and (coalesce(p_ws, '') = '' or e.workshop = p_ws)
             group by e.workshop, e.firm, e.cap having sum(e.qty) > 0) q), '[]'::jsonb));
end $$;
revoke all on function public.rr_summary_json(date, date, text, text) from public, anon;
grant execute on function public.rr_summary_json(date, date, text, text) to authenticated;
notify pgrst, 'reload schema';

-- ================================================================================================================
-- STEP 88 : Kitty vs last year - if the same date last year is missing, the nearest typed date within 5 days (before or after) is used
-- Safe to run again.
-- ================================================================================================================
create or replace function public.kitty_lyk_json(p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ly date := (p_day - interval '1 year')::date; w text; a jsonb; b jsonb; auto boolean; src date; rws jsonb; outj jsonb := '[]'::jsonb;
        caps int[] := array[10, 16, 25, 63, 100, 160, 250, 400, 630, 1000];
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  foreach w in array public.my_workshops() loop
    a := public.kitty_json(w, p_day);
    if (a->>'base') is null then continue; end if;
    b := public.kitty_json(w, ly);
    auto := (b->>'base') is not null;
    src := ly;
    if not auto then
      src := null;
      select k.day into src from public.kitty_lyk k
       where k.workshop = w and k.day between ly - 5 and ly + 5
       group by k.day order by abs(k.day - ly), k.day limit 1;
      if src is null then src := ly; end if;
    end if;
    select jsonb_agg(jsonb_build_array(c,
             coalesce((select (x->>7)::int from jsonb_array_elements(a->'rows') x where (x->>0)::int = c), 0),
             case when auto then coalesce((select (x->>7)::int from jsonb_array_elements(b->'rows') x where (x->>0)::int = c), 0)
                  else coalesce((select k.qty from public.kitty_lyk k where k.workshop = w and k.day = src and k.cap = c), 0) end) order by c)
      into rws from unnest(caps) c;
    outj := outj || jsonb_build_array(jsonb_build_object('ws', w, 'auto', auto, 'edit', public.mr_edit_ok(w), 'src', src, 'rows', rws));
  end loop;
  return jsonb_build_object('ly', ly, 'ws', outj);
end $$;
revoke all on function public.kitty_lyk_json(date) from public, anon;
grant execute on function public.kitty_lyk_json(date) to authenticated;
notify pgrst, 'reload schema';

-- ================================================================================================================
-- STEP 92 : Testing Register (M&R) + STD (IS losses) + delete only with an OTP + storage figures for the Admin
-- Safe to run again. Nothing is deleted.
-- ================================================================================================================

-- ---- STD: the standard full load loss of a capacity (the "IS LOSSES" sheet) ----
create table if not exists public.test_std (cap int primary key, no_load numeric, load_loss numeric);
insert into public.test_std (cap, no_load, load_loss) values
  (10, null, null), (16, null, null), (25, null, null), (63, null, null),
  (100, null, 1650), (160, null, 1950), (250, null, 2930), (400, null, 3450), (630, null, 5300), (1000, null, 7700)
  on conflict (cap) do nothing;
alter table public.test_std enable row level security;
revoke all on public.test_std from public, anon, authenticated;

-- ---- the register itself (one row = one tested transformer) ----
create table if not exists public.test_reg (
  id bigint generated always as identity primary key,
  workshop text not null, firm text, cap int, job_no text, test_date date,
  tr_r text, tr_y text, tr_b text,                 -- turn ratio R Y B
  meg_hve text, meg_lve text, meg_hvlv text,       -- megger HV/E LV/E HV/LV
  dvdf text, hv text,                              -- DVDF, high voltage
  nll numeric, fll numeric,                        -- no load loss (W), full load loss (W)
  remark text, by_login text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
drop index if exists public.test_reg_job;   -- a job no may now be entered again and again (re-test); the register colours it by how many times
create index if not exists test_reg_job_n on public.test_reg (workshop, upper(job_no)) where coalesce(job_no, '') <> '';
create index if not exists test_reg_date on public.test_reg (workshop, test_date);
alter table public.test_reg enable row level security;
revoke all on public.test_reg from public, anon, authenticated;

-- ---- OTP for deleting: the person who wants to delete asks, the Admin sees the 6 digit code in the app, tells it, the person types it ----
create table if not exists public.del_req (
  id uuid primary key default gen_random_uuid(),
  requester uuid not null, login text, division text, detail text,
  code text not null, tries int not null default 0,
  expires timestamptz not null default (now() + interval '10 minutes'),
  verified boolean not null default false, permit_until timestamptz
);
alter table public.del_req enable row level security;
revoke all on public.del_req from public, anon, authenticated;

create or replace function public.del_request(p_detail text) returns uuid
language plpgsql security definer set search_path = public as $$
declare c public.profiles := public.tf_caller(); rid uuid;
begin
  if c.user_id is null or c.role not in ('admin', 'je', 'creator') then raise exception 'You cannot delete data.'; end if;
  delete from public.del_req where expires < now() - interval '1 day';
  insert into public.del_req (requester, login, division, detail, code)
  values (c.user_id, c.login_id, c.org_division, left(coalesce(p_detail, ''), 200),
          lpad(((('x' || substr(md5(gen_random_uuid()::text), 1, 6))::bit(24)::int) % 1000000)::text, 6, '0'))
  returning id into rid;
  return rid;
end $$;

-- what an Admin sees: the open requests of his division with the code
create or replace function public.del_pending_json() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.profiles := public.tf_caller();
begin
  if c.user_id is null or c.role not in ('admin', 'creator') then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'who', r.login, 'detail', r.detail, 'code', r.code, 'left', greatest(0, extract(epoch from (r.expires - now()))::int)) order by r.expires desc)
                     from public.del_req r
                    where r.expires > now() and not r.verified and (c.role = 'creator' or r.division is not distinct from c.org_division)), '[]'::jsonb);
end $$;

create or replace function public.del_verify(p_id uuid, p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.del_req;
begin
  select * into r from public.del_req where id = p_id and requester = auth.uid();
  if r.id is null then raise exception 'This request was not found. Ask for a new OTP.'; end if;
  if r.expires < now() then raise exception 'The OTP has expired. Ask for a new one.'; end if;
  if r.tries >= 5 then raise exception 'Too many wrong tries. Ask for a new OTP.'; end if;
  if btrim(coalesce(p_code, '')) <> r.code then
    update public.del_req set tries = tries + 1 where id = p_id;
    raise exception 'Wrong OTP.';
  end if;
  update public.del_req set verified = true, permit_until = now() + interval '10 minutes' where id = p_id;
  return jsonb_build_object('permit', p_id);
end $$;

create or replace function public.del_ok(p_permit uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.del_req r where r.id = p_permit and r.requester = auth.uid() and r.verified and r.permit_until > now())
$$;

-- delete a PR of the Data Sheet: only with a valid OTP permit (the old direct delete is switched off)
create or replace function public.delete_pr_otp(p_ws text, p_pr text, p_permit uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare c int;
begin
  if not public.del_ok(p_permit) then raise exception 'Delete needs the Admin OTP.'; end if;
  if not (public.my_can_edit() and public.my_role() in ('admin', 'je') and p_ws = any (coalesce(public.my_workshops(), '{}'))) then raise exception 'You do not have permission to delete this PR.'; end if;
  delete from public.data where workshop = p_ws and pr_no = btrim(p_pr);
  get diagnostics c = row_count;
  if c = 0 then raise exception 'PR % not found.', p_pr; end if;
  return true;
end $$;
revoke execute on function public.delete_pr(text, text) from authenticated;

-- ---- Testing register functions ----
create or replace function public.test_std_json() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  return jsonb_build_object('rows', coalesce((select jsonb_agg(jsonb_build_array(cap, no_load, load_loss) order by cap) from public.test_std), '[]'::jsonb),
                            'edit', public.my_role() in ('admin', 'creator'));
end $$;

create or replace function public.test_std_set(p_rows jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare e jsonb;
begin
  if public.my_role() not in ('admin', 'creator') then raise exception 'Only an Admin can change the STD.'; end if;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if (e->>'cap')::int not in (10, 16, 25, 63, 100, 160, 250, 400, 630, 1000) then continue; end if;
    insert into public.test_std (cap, no_load, load_loss) values ((e->>'cap')::int, nullif(e->>'no_load', '')::numeric, nullif(e->>'load_loss', '')::numeric)
      on conflict (cap) do update set no_load = excluded.no_load, load_loss = excluded.load_loss;
  end loop;
  return 'saved';
end $$;

-- firms of a workshop = the firms typed in the Repair tab (and the firms already used in the register)
create or replace function public.test_firms_json(p_ws text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  if not (p_ws = any (public.my_workshops())) then raise exception 'This workshop is not yours.'; end if;
  return coalesce((select jsonb_agg(f order by f) from (
            select distinct upper(btrim(e.firm)) f from public.rr_entry e where e.workshop = p_ws and coalesce(btrim(e.firm), '') <> ''
            union select distinct upper(btrim(t.firm)) from public.test_reg t where t.workshop = p_ws and coalesce(btrim(t.firm), '') <> '') q), '[]'::jsonb);
end $$;

create or replace function public.test_list_json(p_from date, p_to date, p_ws text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ed text[]; tot int;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Choose the From and To dates.'; end if;
  select coalesce(array_agg(w), '{}') into ed from unnest(public.my_workshops()) w where public.mr_edit_ok(w);
  select count(*) into tot from public.test_reg t where t.workshop = any (coalesce((select public.my_workshops()), '{}')) and t.test_date between p_from and p_to and (coalesce(p_ws, '') = '' or t.workshop = p_ws);
  return jsonb_build_object('total', tot, 'rows', coalesce((
    select jsonb_agg(jsonb_build_array(z.id, z.workshop, z.firm, z.cap, z.job_no, to_char(z.test_date, 'DD.MM.YYYY'), z.tr_r, z.tr_y, z.tr_b, z.meg_hve, z.meg_lve, z.meg_hvlv, z.dvdf, z.hv, z.nll, z.fll, z.remark,
                                         case when z.workshop = any (ed) then 1 else 0 end,
                                         (select count(*) from public.test_reg q where q.workshop = z.workshop and upper(q.job_no) = upper(z.job_no))) order by z.test_date, z.id)
      from (select t.* from public.test_reg t where t.workshop = any (coalesce((select public.my_workshops()), '{}')) and t.test_date between p_from and p_to and (coalesce(p_ws, '') = '' or t.workshop = p_ws)
             order by t.test_date, t.id limit 3000) z), '[]'::jsonb));
end $$;

-- save one or more rows. A row is {id?, workshop, firm, cap, job_no, test_date (YYYY-MM-DD), tr_r, tr_y, tr_b, meg_hve, meg_lve, meg_hvlv, dvdf, hv, nll, fll, remark}
-- ONE turn ratio and ONE megger value per test (stored in all three columns). If left empty, one value is picked at random between 43.5-44.5 (turn ratio) and 2000-5000 (megger).
-- Returns [{i, id, tr, mg, cnt}] for every saved row (cnt = how many times this job no is now in the register of the workshop).
create or replace function public.test_save(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e jsonb; i int := 0; rid bigint; outj jsonb := '[]'::jsonb; c public.profiles := public.tf_caller(); w text; trv text; mgv text; jn text; cn int;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    w := e->>'workshop'; jn := btrim(e->>'job_no');
    if not public.mr_edit_ok(w) then raise exception 'You cannot change the register of %.', w; end if;
    if coalesce(jn, '') = '' then raise exception 'Job no / unique no is needed.'; end if;
    if (e->>'cap')::int not in (10, 16, 25, 63, 100, 160, 250, 400, 630, 1000) then raise exception 'Choose the capacity.'; end if;
    trv := coalesce(nullif(btrim(e->>'tr_r'), ''), nullif(btrim(e->>'tr_y'), ''), nullif(btrim(e->>'tr_b'), ''), round((43.5 + random())::numeric, 1)::text);
    mgv := coalesce(nullif(btrim(e->>'meg_hve'), ''), nullif(btrim(e->>'meg_lve'), ''), nullif(btrim(e->>'meg_hvlv'), ''), (round((2000 + random() * 3000)::numeric, -1)::bigint)::text || 'M-ohm');
    if nullif(e->>'id', '') is not null then
      update public.test_reg set workshop = w, firm = nullif(upper(btrim(e->>'firm')), ''), cap = (e->>'cap')::int, job_no = jn, test_date = nullif(e->>'test_date', '')::date,
             tr_r = trv, tr_y = trv, tr_b = trv, meg_hve = mgv, meg_lve = mgv, meg_hvlv = mgv,
             dvdf = nullif(btrim(e->>'dvdf'), ''), hv = nullif(btrim(e->>'hv'), ''), nll = nullif(e->>'nll', '')::numeric, fll = nullif(e->>'fll', '')::numeric,
             remark = nullif(btrim(e->>'remark'), ''), by_login = c.login_id, updated_at = now()
       where id = (e->>'id')::bigint and workshop = any (public.my_workshops()) returning id into rid;
      if rid is null then raise exception 'This row was not found.'; end if;
    else
      insert into public.test_reg (workshop, firm, cap, job_no, test_date, tr_r, tr_y, tr_b, meg_hve, meg_lve, meg_hvlv, dvdf, hv, nll, fll, remark, by_login)
      values (w, nullif(upper(btrim(e->>'firm')), ''), (e->>'cap')::int, jn, nullif(e->>'test_date', '')::date, trv, trv, trv, mgv, mgv, mgv,
              nullif(btrim(e->>'dvdf'), ''), nullif(btrim(e->>'hv'), ''), nullif(e->>'nll', '')::numeric, nullif(e->>'fll', '')::numeric, nullif(btrim(e->>'remark'), ''), c.login_id)
      returning id into rid;
    end if;
    select count(*) into cn from public.test_reg q where q.workshop = w and upper(q.job_no) = upper(jn);
    outj := outj || jsonb_build_array(jsonb_build_object('i', i, 'id', rid, 'tr', trv, 'mg', mgv, 'cnt', cn));
    i := i + 1;
  end loop;
  return outj;
end $$;

create or replace function public.test_delete(p_id bigint, p_permit uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare w text;
begin
  if not public.del_ok(p_permit) then raise exception 'Delete needs the Admin OTP.'; end if;
  select workshop into w from public.test_reg where id = p_id;
  if w is null or not public.mr_edit_ok(w) then raise exception 'You cannot delete this row.'; end if;
  delete from public.test_reg where id = p_id;
  return true;
end $$;

-- report of a period: counts by % loss slab, per workshop and capacity.  Slabs like the Excel: <=100, <=115, <=120, <=125, <=130, <=135, <=140, <=145, <=150, above 150.
-- rows [workshop, cap, slab (0..9, or -1 = % not known: no full load loss typed or no STD), count]
create or replace function public.test_report_json(p_from date, p_to date, p_ws text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Choose the From and To dates.'; end if;
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(jsonb_build_array(q.workshop, q.cap, q.slab, q.n))
      from (select t.workshop, t.cap,
                   case when t.fll is null or coalesce(s.load_loss, 0) = 0 then -1
                        else (select case when p <= 100 then 0 when p <= 115 then 1 when p <= 120 then 2 when p <= 125 then 3 when p <= 130 then 4
                                          when p <= 135 then 5 when p <= 140 then 6 when p <= 145 then 7 when p <= 150 then 8 else 9 end
                                from (select round(t.fll * 100 / s.load_loss) as p) pp) end as slab,
                   count(*) as n
              from public.test_reg t left join public.test_std s on s.cap = t.cap
             where t.workshop = any (coalesce((select public.my_workshops()), '{}')) and t.test_date between p_from and p_to and (coalesce(p_ws, '') = '' or t.workshop = p_ws)
             group by 1, 2, 3) q), '[]'::jsonb));
end $$;

-- storage figures (Admin): database size and the oldest PR year
create or replace function public.db_usage_json() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare sz numeric := pg_database_size(current_database()) / 1048576.0;
begin
  if public.my_role() not in ('admin', 'creator') then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true, 'mb', round(sz, 1), 'limit_mb', 500, 'pct', round(sz * 100 / 500, 0),
    'oldest', (select min(extract(year from pr_date))::int from public.data where pr_date is not null),
    'rows', (select count(*) from public.data), 'tests', (select count(*) from public.test_reg));
end $$;

revoke all on function public.del_request(text), public.del_pending_json(), public.del_verify(uuid, text), public.del_ok(uuid), public.delete_pr_otp(text, text, uuid),
  public.test_std_json(), public.test_std_set(jsonb), public.test_firms_json(text), public.test_list_json(date, date, text), public.test_save(jsonb),
  public.test_delete(bigint, uuid), public.test_report_json(date, date, text), public.db_usage_json() from public, anon;
grant execute on function public.del_request(text), public.del_pending_json(), public.del_verify(uuid, text), public.del_ok(uuid), public.delete_pr_otp(text, text, uuid),
  public.test_std_json(), public.test_std_set(jsonb), public.test_firms_json(text), public.test_list_json(date, date, text), public.test_save(jsonb),
  public.test_delete(bigint, uuid), public.test_report_json(date, date, text), public.db_usage_json() to authenticated;
notify pgrst, 'reload schema';

-- ################ STEP 51 : R&R keeps 3 years + M&R (Repair, Testing Register) archive to Google Drive ################
-- Run ONCE in Supabase > SQL Editor (it is already inside setup.sql).  Safe to run again.
--  * R&R (table "data"): when the storage is 90% full, the OLDEST 12 months of PRs are deleted every Sunday - but NEVER a PR newer than 3 years.
--  * M&R Repair (rr_entry) and Testing Register (test_reg) are NOT touched by that job.  When R&R is down to 3 years and the storage is still full,
--    the Admin tab has the box "Google Drive archive": it saves the OLDEST month to Google Drive, and only after Drive confirms every row, deletes it here.
create table if not exists public.arch_cfg (id int primary key default 1 check (id = 1), url text, token text, updated_at timestamptz not null default now());
alter table public.arch_cfg enable row level security;
revoke all on public.arch_cfg from public, anon, authenticated;
create table if not exists public.arch_log (id bigserial primary key, at timestamptz not null default now(), month text, rr_rows int, tr_rows int, by_login text, note text);
alter table public.arch_log enable row level security;
revoke all on public.arch_log from public, anon, authenticated;

create or replace function public.arch_ok() returns boolean language sql stable security definer set search_path = public as
$$ select coalesce((select p.active and p.role in ('admin', 'creator') from public.profiles p where p.user_id = auth.uid()), false) $$;

create or replace function public.arch_cfg_get() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c record;
begin
  if not public.arch_ok() then raise exception 'Only an Admin can do this.'; end if;
  select * into c from public.arch_cfg where id = 1;
  return jsonb_build_object('url', coalesce(c.url, ''), 'token', coalesce(c.token, ''));
end $$;

create or replace function public.arch_cfg_set(p_url text, p_token text) returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not public.arch_ok() then raise exception 'Only an Admin can do this.'; end if;
  p_url := btrim(coalesce(p_url, '')); p_token := btrim(coalesce(p_token, ''));
  if p_url !~ '^https://script\.google\.com/macros/s/[A-Za-z0-9_-]+/exec$' then raise exception 'The link must look like https://script.google.com/macros/s/.../exec'; end if;
  if length(p_token) < 8 or length(p_token) > 100 then raise exception 'The secret code must be 8 to 100 characters.'; end if;
  insert into public.arch_cfg (id, url, token) values (1, p_url, p_token)
    on conflict (id) do update set url = excluded.url, token = excluded.token, updated_at = now();
  return true;
end $$;

-- the months that may be archived: older than 12 months.  R&R floor = no PR older than 3 years is left
create or replace function public.arch_status_json() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare sz numeric := pg_database_size(current_database()) / 1048576.0; lim date := date_trunc('month', current_date - interval '12 months')::date; mw text[] := coalesce(public.my_workshops(), '{}');
begin
  if not public.arch_ok() then raise exception 'Only an Admin can do this.'; end if;
  return jsonb_build_object('mb', round(sz, 1), 'limit_mb', 500, 'pct', round(sz * 100 / 500, 0),
    'rr_old', (select count(*) from public.data where pr_date is not null and pr_date < (current_date - interval '36 months')::date),
    'months', coalesce((select jsonb_agg(jsonb_build_object('m', m, 'rr', rr, 'tr', tr) order by m) from (
        select m, sum(rr)::int rr, sum(tr)::int tr from (
          select to_char(day, 'YYYY-MM') m, count(*) rr, 0 tr from public.rr_entry where day < lim and workshop = any (mw) group by 1
          union all
          select to_char(coalesce(test_date, created_at::date), 'YYYY-MM'), 0, count(*) from public.test_reg
            where coalesce(test_date, created_at::date) < lim and workshop = any (mw) group by 1) u
        group by m order by m limit 40) z), '[]'::jsonb),
    'log', coalesce((select jsonb_agg(jsonb_build_object('at', to_char(at at time zone 'Asia/Kolkata', 'DD.MM.YYYY HH24:MI'), 'month', month, 'rr', rr_rows, 'tr', tr_rows) order by id desc) from (select * from public.arch_log order by id desc limit 5) l), '[]'::jsonb));
end $$;

-- every Repair and Testing Register row of one month (to be saved to Drive)
create or replace function public.arch_month_json(p_month text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d0 date; d1 date; lim date := date_trunc('month', current_date - interval '12 months')::date; mw text[] := coalesce(public.my_workshops(), '{}');
begin
  if not public.arch_ok() then raise exception 'Only an Admin can do this.'; end if;
  if p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Wrong month.'; end if;
  d0 := (p_month || '-01')::date; d1 := (d0 + interval '1 month')::date;
  if d1 > lim then raise exception 'Only a month older than 12 months can be archived.'; end if;
  return jsonb_build_object('month', p_month,
    'rr', coalesce((select jsonb_agg(jsonb_build_array(workshop, day, block, firm, cap, qty, by_login, to_char(at at time zone 'Asia/Kolkata', 'YYYY-MM-DD HH24:MI')) order by workshop, day, block, firm, cap)
                    from public.rr_entry where day >= d0 and day < d1 and workshop = any (mw)), '[]'::jsonb),
    'tr', coalesce((select jsonb_agg(jsonb_build_array(id, workshop, firm, cap, job_no, test_date, tr_r, tr_y, tr_b, meg_hve, meg_lve, meg_hvlv, dvdf, hv, nll, fll, remark, by_login, to_char(created_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD HH24:MI')) order by workshop, test_date, id)
                    from public.test_reg where coalesce(test_date, created_at::date) >= d0 and coalesce(test_date, created_at::date) < d1 and workshop = any (mw)), '[]'::jsonb));
end $$;

-- delete EXACTLY the rows that Drive has confirmed (the app sends their keys), nothing else
create or replace function public.arch_delete(p_month text, p_rr jsonb, p_tr jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare d0 date; d1 date; lim date := date_trunc('month', current_date - interval '12 months')::date; mw text[] := coalesce(public.my_workshops(), '{}'); a int; b int; me text;
begin
  if not public.arch_ok() then raise exception 'Only an Admin can do this.'; end if;
  if p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Wrong month.'; end if;
  d0 := (p_month || '-01')::date; d1 := (d0 + interval '1 month')::date;
  if d1 > lim then raise exception 'Only a month older than 12 months can be archived.'; end if;
  delete from public.rr_entry e using jsonb_array_elements(coalesce(p_rr, '[]'::jsonb)) x(v)
   where e.workshop = x.v->>0 and e.day = (x.v->>1)::date and e.block = x.v->>2 and e.firm = x.v->>3 and e.cap = x.v->>4
     and e.day >= d0 and e.day < d1 and e.workshop = any (mw);
  get diagnostics a = row_count;
  delete from public.test_reg t where t.id in (select (jsonb_array_elements_text(coalesce(p_tr, '[]'::jsonb)))::bigint)
     and coalesce(t.test_date, t.created_at::date) >= d0 and coalesce(t.test_date, t.created_at::date) < d1 and t.workshop = any (mw);
  get diagnostics b = row_count;
  select login_id into me from public.profiles where user_id = auth.uid();
  insert into public.arch_log (month, rr_rows, tr_rows, by_login, note) values (p_month, a, b, me, 'Saved to Google Drive, then deleted here.');
  return jsonb_build_object('rr', a, 'tr', b);
end $$;

revoke all on function public.arch_ok(), public.arch_cfg_get(), public.arch_cfg_set(text, text), public.arch_status_json(), public.arch_month_json(text), public.arch_delete(text, jsonb, jsonb) from public, anon;
grant execute on function public.arch_ok(), public.arch_cfg_get(), public.arch_cfg_set(text, text), public.arch_status_json(), public.arch_month_json(text), public.arch_delete(text, jsonb, jsonb) to authenticated;

-- give the space of the M&R tables back after a delete (Sunday, after the R&R job)
do $$
begin
  begin perform cron.unschedule('tf-shrink-rr'); exception when others then null; end;
  begin perform cron.unschedule('tf-shrink-test'); exception when others then null; end;
  perform cron.schedule('tf-shrink-rr',   '40 21 * * 6', 'VACUUM FULL public.rr_entry');
  perform cron.schedule('tf-shrink-test', '50 21 * * 6', 'VACUUM FULL public.test_reg');
exception when others then
  raise notice 'pg_cron is not available: the shrink jobs of the M&R tables were NOT created (%).', sqlerrm;
end $$;
create or replace function public.arch_cfg_clear() returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not public.arch_ok() then raise exception 'Only an Admin can do this.'; end if;
  delete from public.arch_cfg where id = 1;
  return true;
end $$;
revoke all on function public.arch_cfg_clear() from public, anon;
grant execute on function public.arch_cfg_clear() to authenticated;
notify pgrst, 'reload schema';

-- ################ STEP 52 : M&R Summary also shows REPAIR (Repair tab, REPAIR block; 250 AL + 250 CU = 250) ################
-- today, till date (From-To) and capacity wise.  Run ONCE (already inside setup.sql).  Safe to run again.
create or replace function public.mr_repair_json(p_date date, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare mw text[] := coalesce(public.my_workshops(), '{}'); r jsonb;
begin
  if not public.mr_ok() then raise exception 'No access to the M&R dashboard.'; end if;
  with e as (select workshop, day, nullif(regexp_replace(cap, '\D', '', 'g'), '')::int cap, qty from public.rr_entry
              where block = 'REPAIR' and workshop = any (mw) and (day = p_date or day between p_from and p_to))
  select jsonb_build_object(
    'ws',  coalesce((select jsonb_agg(jsonb_build_array(workshop, today, tot) order by workshop)
                       from (select workshop, coalesce(sum(qty) filter (where day = p_date), 0)::int today, coalesce(sum(qty) filter (where day between p_from and p_to), 0)::int tot from e group by workshop) a), '[]'::jsonb),
    'cap', coalesce((select jsonb_agg(jsonb_build_array(workshop, cap, n) order by workshop, cap)
                       from (select workshop, coalesce(cap, 0) cap, sum(qty)::int n from e where day between p_from and p_to group by workshop, coalesce(cap, 0) having sum(qty) > 0) b), '[]'::jsonb))
    into r;
  return r;
end $$;
revoke all on function public.mr_repair_json(date, date, date) from public, anon;
grant execute on function public.mr_repair_json(date, date, date) to authenticated;
notify pgrst, 'reload schema';

-- ################ STEP 53 : LOGIN WITH ONLY ID + PASSWORD (a directory in the DEFAULT project) ################
-- The DEFAULT project (the one in config.js, the App Creator's) keeps a directory: which login ID belongs to which Admin's project.
-- Every Admin publishes his IDs from Admin > "Login without code".  The App Creator approves the Admin once (Admin > "Admin directory").
-- The login page then finds the project by the ID, so nobody needs the workshop code.  An ID found in two approved projects cannot log in.
-- Run this file in EVERY project (it is inside setup.sql); only the DEFAULT project uses the directory tables.  Safe to run again.
create table if not exists public.ud_project (
  pid uuid primary key default gen_random_uuid(), url text not null unique, key text not null, label text not null default '',
  token_hash text not null, status text not null default 'pending' check (status in ('pending', 'approved', 'blocked')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table if not exists public.ud_login (
  login text not null, pid uuid not null references public.ud_project (pid) on delete cascade, primary key (login, pid));
create index if not exists ud_login_pid on public.ud_login (pid);
alter table public.ud_project enable row level security; alter table public.ud_login enable row level security;
revoke all on public.ud_project, public.ud_login from public, anon, authenticated;

-- (own project) the Admin's directory token, kept in his own database
create table if not exists public.ud_cfg (id int primary key default 1 check (id = 1), token text, updated_at timestamptz not null default now());
alter table public.ud_cfg enable row level security;
revoke all on public.ud_cfg from public, anon, authenticated;

create or replace function public.ud_ok() returns boolean language sql stable security definer set search_path = public as
$$ select coalesce((select p.active and p.role in ('admin', 'creator') from public.profiles p where p.user_id = auth.uid()), false) $$;
create or replace function public.ud_creator() returns boolean language sql stable security definer set search_path = public as
$$ select coalesce((select p.active and p.role = 'creator' from public.profiles p where p.user_id = auth.uid()), false) $$;

-- (own project) the login IDs of this project, and the saved token
create or replace function public.ud_logins_json() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ud_ok() then raise exception 'Only an Admin can do this.'; end if;
  return coalesce((select jsonb_agg(distinct lower(btrim(login_id))) from public.profiles where active and coalesce(btrim(login_id), '') <> ''), '[]'::jsonb);
end $$;
create or replace function public.ud_cfg_get() returns text language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ud_ok() then raise exception 'Only an Admin can do this.'; end if;
  return (select token from public.ud_cfg where id = 1);
end $$;
create or replace function public.ud_cfg_set(p_token text) returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not public.ud_ok() then raise exception 'Only an Admin can do this.'; end if;
  if p_token is null or p_token = '' then delete from public.ud_cfg where id = 1; return true; end if;
  if length(p_token) < 20 or length(p_token) > 100 then raise exception 'Wrong token.'; end if;
  insert into public.ud_cfg (id, token) values (1, p_token) on conflict (id) do update set token = excluded.token, updated_at = now();
  return true;
end $$;

-- (default project) an Admin publishes his IDs.  First call: p_token is null -> the project is added (status pending) and a token is returned ONCE.
create or replace function public.ud_register(p_url text, p_key text, p_label text, p_logins jsonb, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr public.ud_project; v_tok text; v_role text; v_pl text; a text[]; l text; n int := 0; conf jsonb;
begin
  p_url := lower(btrim(coalesce(p_url, ''))); p_key := btrim(coalesce(p_key, ''));
  if p_url !~ '^https://[a-z0-9-]+\.supabase\.co$' then raise exception 'Wrong project address.'; end if;
  if length(p_key) < 20 or p_key ~* 'service_role' or p_key ~ '^sb_secret_' then raise exception 'Wrong key (only the publishable / anon key is allowed).'; end if;
  if position('.' in p_key) > 0 then
    begin
      v_pl := translate(split_part(p_key, '.', 2), '-_', '+/'); v_pl := v_pl || repeat('=', (4 - length(v_pl) % 4) % 4);
      v_role := convert_from(decode(v_pl, 'base64'), 'utf8')::jsonb ->> 'role';
    exception when others then v_role := null; end;
    if v_role is distinct from 'anon' then raise exception 'Wrong key (only the publishable / anon key is allowed).'; end if;
  end if;
  if jsonb_typeof(coalesce(p_logins, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_logins, '[]'::jsonb)) > 3000 then raise exception 'Too many IDs.'; end if;
  select * into pr from public.ud_project where url = p_url;
  if pr.pid is null then
    v_tok := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    insert into public.ud_project (url, key, label, token_hash) values (p_url, p_key, left(btrim(coalesce(p_label, '')), 120), encode(sha256(convert_to(v_tok, 'utf8')), 'hex')) returning * into pr;
  else
    if p_token is null or pr.token_hash <> encode(sha256(convert_to(p_token, 'utf8')), 'hex') then raise exception 'This project is already in the directory. Use the saved token, or ask the App Creator to remove it and publish again.'; end if;
    update public.ud_project set key = p_key, label = coalesce(nullif(left(btrim(coalesce(p_label, '')), 120), ''), label), updated_at = now() where pid = pr.pid;
  end if;
  delete from public.ud_login where pid = pr.pid;
  for l in select lower(btrim(x)) from jsonb_array_elements_text(coalesce(p_logins, '[]'::jsonb)) x loop
    if l ~ '^[a-z0-9._@+-]{2,80}$' then insert into public.ud_login (login, pid) values (l, pr.pid) on conflict do nothing; n := n + 1; end if;
  end loop;
  select coalesce(jsonb_agg(distinct a.login), '[]'::jsonb) into conf from public.ud_login a join public.ud_login b on b.login = a.login and b.pid <> a.pid where a.pid = pr.pid;
  return jsonb_build_object('token', v_tok, 'status', (select status from public.ud_project where pid = pr.pid), 'count', n, 'conflicts', conf);
end $$;

-- (default project) the login page / the create-user check: which approved project has this ID?
create or replace function public.ud_find(p_login text, p_url text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l text := lower(btrim(coalesce(p_login, ''))); n int; m int; ru text; rk text;
begin
  if l !~ '^[a-z0-9._@+-]{2,80}$' then return jsonb_build_object('n', 0, 'other', 0); end if;
  select count(*) into n from public.ud_login x join public.ud_project p on p.pid = x.pid and p.status = 'approved' where x.login = l;
  select count(*) into m from public.ud_login x join public.ud_project p on p.pid = x.pid and p.status = 'approved' where x.login = l and (p_url is null or p.url <> lower(btrim(p_url)));
  if n = 1 then select p.url, p.key into ru, rk from public.ud_login x join public.ud_project p on p.pid = x.pid and p.status = 'approved' where x.login = l; end if;
  return jsonb_build_object('n', n, 'other', m, 'u', ru, 'k', rk);
end $$;

-- (default project, App Creator) the Admin directory
create or replace function public.ud_admin_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ud_creator() then raise exception 'Only the App Creator can do this.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'label', p.label, 'url', p.url, 'status', p.status, 'ids', (select count(*) from public.ud_login x where x.pid = p.pid),
            'conf', (select count(distinct a.login) from public.ud_login a join public.ud_login b on b.login = a.login and b.pid <> a.pid where a.pid = p.pid),
            'at', to_char(p.created_at at time zone 'Asia/Kolkata', 'DD.MM.YYYY')) order by p.created_at) from public.ud_project p), '[]'::jsonb);
end $$;
create or replace function public.ud_admin_set(p_pid uuid, p_action text) returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not public.ud_creator() then raise exception 'Only the App Creator can do this.'; end if;
  if p_action = 'remove' then delete from public.ud_project where pid = p_pid;
  elsif p_action in ('approved', 'blocked', 'pending') then update public.ud_project set status = p_action, updated_at = now() where pid = p_pid;
  else raise exception 'Wrong action.'; end if;
  return true;
end $$;

revoke all on function public.ud_ok(), public.ud_creator(), public.ud_logins_json(), public.ud_cfg_get(), public.ud_cfg_set(text), public.ud_register(text, text, text, jsonb, text), public.ud_find(text, text), public.ud_admin_list(), public.ud_admin_set(uuid, text) from public, anon, authenticated;
grant execute on function public.ud_register(text, text, text, jsonb, text), public.ud_find(text, text) to anon, authenticated;
grant execute on function public.ud_logins_json(), public.ud_cfg_get(), public.ud_cfg_set(text), public.ud_admin_list(), public.ud_admin_set(uuid, text) to authenticated;
-- (default project) the Admin asks how his project stands (needs his token)
create or replace function public.ud_status(p_url text, p_token text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pr public.ud_project; conf jsonb;
begin
  select * into pr from public.ud_project where url = lower(btrim(coalesce(p_url, '')));
  if pr.pid is null or p_token is null or pr.token_hash <> encode(sha256(convert_to(p_token, 'utf8')), 'hex') then return jsonb_build_object('status', 'none'); end if;
  select coalesce(jsonb_agg(distinct a.login), '[]'::jsonb) into conf from public.ud_login a join public.ud_login b on b.login = a.login and b.pid <> a.pid where a.pid = pr.pid;
  return jsonb_build_object('status', pr.status, 'count', (select count(*) from public.ud_login where pid = pr.pid), 'conflicts', conf);
end $$;
revoke all on function public.ud_status(text, text) from public, anon, authenticated;
grant execute on function public.ud_status(text, text) to anon, authenticated;
notify pgrst, 'reload schema';

-- ################ STEP 39 : WORKSHOP CODE (registry).  Only needed in the DEFAULT project; it is created only if it is not there yet ################
do $reg$
begin
  if to_regprocedure('public.registry_lookup(text)') is null then
    create table if not exists public.registry (code text primary key, url text not null unique, key text not null, created_at timestamptz not null default now());
    alter table public.registry enable row level security;
    revoke all on public.registry from public, anon, authenticated;
    execute $f$
      create function public.registry_lookup(p_code text) returns jsonb language sql stable security definer set search_path = public as
      $b$ select (select jsonb_build_object('u', r.url, 'k', r.key) from public.registry r where r.code = lower(btrim(coalesce(p_code, '')))) $b$ $f$;
    execute $f$
      create function public.registry_add(p_name text, p_url text, p_key text) returns text language plpgsql security definer set search_path = public as
      $b$
      declare c text; n text := lower(regexp_replace(coalesce(p_name, ''), '[^a-zA-Z0-9]', '', 'g')); v_role text; v_pl text;
      begin
        p_url := lower(btrim(coalesce(p_url, ''))); p_key := btrim(coalesce(p_key, ''));
        if length(n) < 3 then raise exception 'Write a short name of 3 or more letters.'; end if;
        n := left(n, 20);
        if p_url !~ '^https://[a-z0-9-]+\.supabase\.co$' then raise exception 'Wrong project address.'; end if;
        if length(p_key) < 20 or p_key ~* 'service_role' or p_key ~ '^sb_secret_' then raise exception 'Wrong key (only the publishable / anon key is allowed).'; end if;
        if position('.' in p_key) > 0 then
          begin v_pl := translate(split_part(p_key, '.', 2), '-_', '+/'); v_pl := v_pl || repeat('=', (4 - length(v_pl) % 4) % 4); v_role := convert_from(decode(v_pl, 'base64'), 'utf8')::jsonb ->> 'role';
          exception when others then v_role := null; end;
          if v_role is distinct from 'anon' then raise exception 'Wrong key (only the publishable / anon key is allowed).'; end if;
        end if;
        select code into c from public.registry where url = p_url;
        if c is not null then return c; end if;
        c := n || '-' || substr(md5(gen_random_uuid()::text), 1, 6);
        insert into public.registry (code, url, key) values (c, p_url, p_key);
        return c;
      end $b$ $f$;
    revoke all on function public.registry_lookup(text), public.registry_add(text, text, text) from public;
    grant execute on function public.registry_lookup(text), public.registry_add(text, text, text) to anon, authenticated;
  end if;
end $reg$;
notify pgrst, 'reload schema';
