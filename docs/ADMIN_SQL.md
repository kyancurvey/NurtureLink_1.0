# ADMIN_SQL.md

Copy-paste snippets for the project owner. **Run them only in the Supabase SQL Editor** (role `postgres`, the default). Never from the app, and never with a service-role key.

Replace every placeholder in `ALL_CAPS_WITH_UNDERSCORES` or in `<angle brackets>` before running. Do not paste real emails, codes or results into chats, screenshots or the repo.

Depends on migrations 000 to 003 having been run.

---

## 1. Promote my own account to admin

Do this **after** you have signed up in the app (or created the user under Authentication > Users). Roles can only be changed here, never by the client.

```sql
insert into public.profiles (id, role)
select id, 'admin'
from auth.users
where lower(email) = lower('YOUR_EMAIL@example.com')
on conflict (id) do update set role = 'admin'
returning id, role;
```

Success: exactly **one row** comes back with `role = admin`. Zero rows means no account with that email exists yet (check the spelling, or sign up first).

Check afterwards:

```sql
select p.id, p.role, u.email
from public.profiles p
join auth.users u on u.id = p.id
where p.role = 'admin';
```

To turn an account back into a normal patient:

```sql
update public.profiles
set role = 'patient'
where id = (select id from auth.users where lower(email) = lower('YOUR_EMAIL@example.com'));
```

---

## 2. Create a provider invite code

The code is single use, random and uppercase, and expires after 7 days (change the interval if you like). A signed-in patient account redeems it inside the app; that is the only way an account becomes a provider.

**A. Tied to one email** (recommended: only a confirmed account with that email can use it):

```sql
insert into public.provider_invites (code, email, expires_at)
values (
  upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 16)),
  lower('PROVIDER_EMAIL@example.com'),
  now() + interval '7 days'
)
returning code, email, expires_at;
```

**B. Open code** (anyone who is signed in and holds the code can use it; share it only privately):

```sql
insert into public.provider_invites (code, email, expires_at)
values (
  upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 16)),
  null,
  now() + interval '7 days'
)
returning code, email, expires_at;
```

Send the returned `code` to the provider through a private channel. The provider must first sign up as a normal user, then enter the code.

---

## 3. List invites and their status

```sql
select
  code,
  email,
  case
    when used then 'used'
    when expires_at <= now() then 'expired'
    else 'active'
  end as status,
  expires_at,
  used_at,
  used_by
from public.provider_invites
order by created_at desc;
```

To see who a used code turned into (replace the id with a `used_by` value from above):

```sql
select p.id, p.role, u.email
from public.profiles p
join auth.users u on u.id = p.id
where p.id = '<USED_BY_UUID>';
```

---

## 4. Turn demo_mode on and off

Show the current value:

```sql
select key, value, updated_at from public.app_settings where key = 'demo_mode';
```

Turn **on**:

```sql
update public.app_settings set value = 'on' where key = 'demo_mode' returning key, value;
```

Turn **off**:

```sql
update public.app_settings set value = 'off' where key = 'demo_mode' returning key, value;
```

Only `on` and `off` are accepted; anything else is rejected by the database. Remember that the provider access lock fully applies only in Live Mode (`off`), and the demo says so.

---

## 5. Assign a patient to a provider (and un-assign)

A provider sees a patient only after you do this. Patients and providers cannot do it themselves (by design). Both people must have signed up first; the provider must already have the role `provider` (invite code or snippet 1 style).

Assign (replace both emails; expect **1 row** back):

```sql
insert into public.pregnancy_profiles (patient_id, assigned_provider_id)
select pat.id, prov.id
from auth.users pat, auth.users prov
where pat.email = 'PATIENT_EMAIL'
  and prov.email = 'PROVIDER_EMAIL'
  and exists (select 1 from public.profiles where id = prov.id and role = 'provider')
on conflict (patient_id) do update set assigned_provider_id = excluded.assigned_provider_id
returning patient_id, assigned_provider_id;
```

0 rows means an email is wrong or the second person is not a provider yet.

Un-assign (the provider immediately loses access; expect 1 row):

```sql
update public.pregnancy_profiles
set assigned_provider_id = null
where patient_id = (select id from auth.users where email = 'PATIENT_EMAIL')
returning patient_id, assigned_provider_id;
```

---

## 6. Confirm the alert thresholds (medical officer sign-off)

Thresholds start as `is_confirmed = false` ("DEFAULT, pending medical officer confirmation"). Any change a provider makes in the app also resets them to false and is written to the audit log. Confirm only after the medical officer has approved the values.

Look first:

```sql
select alert_type, min_value, max_value, sustained_count, severity, enabled, is_confirmed, updated_by, updated_at
from public.alert_thresholds order by alert_type;
```

Confirm all (or add `where alert_type = 'fever'` for one):

```sql
update public.alert_thresholds set is_confirmed = true returning alert_type, is_confirmed;
```

Read the audit trail of threshold changes:

```sql
select created_at, actor_id, details from public.audit_log where action = 'alert_threshold_updated' order by created_at desc;
```
