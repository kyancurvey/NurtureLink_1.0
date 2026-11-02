# CLAUDE.md

This file has two parts.

- **Part 1: Behavioral guidelines** to reduce common LLM coding mistakes. These apply to every task.
- **Part 2: NurtureLink project specifications.** The stack, rules, workflow and security model for this project.

Read `PLAN.md` at the start of every session. It holds the full plan, current phase, environment state and progress log.

If Part 1 and Part 2 ever seem to conflict, Part 2 wins for security, delivery format and project rules, and Part 1 wins for how much code to write and how much to change. Section "How the two parts fit together" explains the common cases.

---

# PART 1: Behavioral Guidelines

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

# PART 2: NurtureLink Project Specifications

**Project:** NurtureLink, a responsive, installable PWA for pregnant patients and healthcare providers. Tagline: "Nurture Lives, Linking Hearts."

This is a monitoring and screening prototype. It is **not** a diagnostic device.

## Project facts

- GitHub repo: `NurtureLink_1.0` (owner `kyancurvey`). Vite `base` is `/NurtureLink_1.0/`. Expected site URL: `https://kyancurvey.github.io/NurtureLink_1.0/`.
- Supabase project: **NurtureLink**, free tier, Asia-Pacific region. The Data API is enabled.
- Supabase API keys use the new format. The value in `VITE_SUPABASE_ANON_KEY` is the **publishable key** (`sb_publishable_...`). The variable name stays `VITE_SUPABASE_ANON_KEY` so the code is simple. `sb_secret_...` and legacy `service_role` keys never appear anywhere.
- The two build variables (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`) are GitHub **repository variables** already added by the user.

## Stack

- React + Vite, PWA (vite-plugin-pwa)
- react-i18next (English `en`, Filipino `fil`)
- Supabase: Auth, Postgres with row-level security (RLS), Realtime
- GitHub Pages, deployed by GitHub Actions (workflow uses `npm install`, no lockfile required)
- Charts: Recharts
- Device: simulator first, then Web Bluetooth (Chrome/Edge on Android and laptops only; not iPhone)

## How you work with this user

- You have **no access** to the user's GitHub repo or Supabase project. The user uploads your files to GitHub and runs your SQL in the Supabase SQL Editor themselves.
- Never assume what is in the repo or database. If you need the current contents of a file or the state of a table, ask for it. Check Environment State in `PLAN.md` first.
- When changing an existing file, output the **complete updated file**, not a diff or a partial snippet, so the user can replace it directly. Keep the change itself surgical (Part 1, section 3).
- Give every file its exact repo path as a heading, for example `src/components/ui/Button.jsx`.
- Deliver files in the sandbox output folder with the same folder structure as the repo, grouped so each upload is manageable (the GitHub web uploader handles about 100 files at a time and cannot unzip). Say which folders to drag in. Mention hidden folders such as `.github`, which the web uploader may skip.
- After the files, always give a numbered **Manual Steps** list: what to upload where, what to run in the SQL Editor and in what order, what to change in the GitHub or Supabase dashboard, and how to test it.
- If you have a sandbox, build and test the front end there before delivering. State plainly what you verified and what the user must verify (anything involving the live Supabase project).
- Do not tell the user to paste secrets into chat or files. If the user reports an error, ask for the exact error text and the relevant file. Explain the cause first, then give the fixed complete file.

## Never do

- Never include real patient data in files, seeds, tests, screenshots or examples. Synthetic data only.
- Never put secrets in any file. Only the publishable key is ever used in the front end.
- Never let the client choose or send its own role. Roles are assigned server-side.
- Never rely on front-end checks for access control. GitHub Pages cannot protect anything. RLS plus grants are the real protection; route guards are for usability only.
- Never hard-code UI text. Every string uses an i18n key with entries in both `en.json` and `fil.json`.
- Never show a reading screen without the disclaimer: "monitoring and screening, not diagnosis."
- Never `GRANT ALL`. Never grant any table privilege to `anon` unless explicitly justified in a comment and approved by the user.
- Never tell the user to run SQL you have not explained. Each SQL file starts with a comment describing what it does, what it depends on, and how to undo it.

## Supabase access model (grants plus RLS)

The project is set up so tables are **not** exposed automatically. Treat access as two locks, and both must be right:

1. **Grants:** a role can only touch a table if it has been granted privileges on it. Every migration that creates a table or function must also grant the minimum privileges needed to `authenticated` (and to `anon` only if justified). Without a grant, the app gets "permission denied" even when policies are correct.
2. **RLS policies:** decide which rows the granted role may see or change.

Rules:

- Enable RLS on every table. Default deny.
- `REVOKE` default privileges from `anon` and `authenticated` for new tables, sequences and functions in `public`, so nothing is open by accident (see migration `000_project_hardening.sql`).
- For every `SECURITY DEFINER` function: fixed `search_path`, `REVOKE EXECUTE` from `PUBLIC` and `anon`, then `GRANT EXECUTE` only to the roles that need it. Add a comment explaining why it needs `SECURITY DEFINER`.
- Prefer views or functions over broad table grants where a role should see only some columns.
- Include a test that `anon` gets "permission denied" on every table and function.
- Do not assume the "Automatically expose new tables" or "Enable automatic RLS" project options are set a particular way. Migration `000` makes the database safe either way.

## Roles

- **Patient:** reads and writes only their own data.
- **Provider:** reads only patients assigned to them. Only providers reach validation, reports and the audit log. Accounts are created by invite code or admin, never by self-signup.
- **Admin:** the project owner. Creates provider invites and manages consent documents by running SQL in the Supabase SQL Editor, never from the client.

## Always do

- Write SQL as numbered files (`supabase/migrations/000_...sql`, `001_...sql`), idempotent where possible (`create ... if not exists`, `drop policy if exists`), so a re-run does not break anything.
- Provide RLS and access tests the user can run in the SQL Editor, simulating a user by setting the role and JWT claims inside a transaction that ends in `rollback`.
- Keep provider-only data (validation, reports, audit log) unreachable for patients at the database level.
- Write an audit log entry whenever a provider opens a patient record.
- Use mobile-first layouts. Phone uses bottom tabs; laptop uses a sidebar, and providers get a split view (list left, detail right).
- Show status with icon and text, never color alone.
- Keep alert colors (red, amber, green) separate from the brand coral.
- Use CSS variables from `src/styles/tokens.css` for all colors, spacing and type.
- Use large touch targets (minimum 44px).
- Run `npm run i18n:check` (in the sandbox if possible) before delivering anything that touches text.

## Conventions

- Folders: `src/components/ui` (shared kit), `src/features/patient`, `src/features/provider`, `src/lib` (supabase client, helpers), `src/locales`, `src/styles`, `supabase/migrations`, `supabase/tests`, `supabase/seed`, `docs`, `.github/workflows`.
- Hash routing (`HashRouter`) so deep links work on GitHub Pages.
- Keep dependencies minimal. Ask before adding a new one.
- Alert thresholds (default fetal heart rate 110-160 bpm) are **pending medical officer confirmation**. Store them in a table, never hard-code them, and mark them as defaults.
- Provider notes stay in the language they were written in.
- Draft legal text is labeled "DRAFT, pending ethics/legal review" and never claims to be legal advice.

## How the two parts fit together

| Situation | What to do |
|---|---|
| Part 1 says "state assumptions and ask" | Do it, especially for anything touching security, consent, alerts, or health wording. Ask before guessing. |
| Part 1 says "simplicity first" | Keep code minimal. Security rules in Part 2 (RLS, grants, i18n, disclaimers) are requirements, not "extra features", so they are never cut for brevity. |
| Part 1 says "surgical changes" | Change only what the request needs, but still deliver the **complete updated file** (the user cannot apply diffs). Tell the user which lines changed. |
| Part 1 says "write tests, then make them pass" | For database work, the tests are the SQL access tests in `supabase/tests/`. For front-end work, build in the sandbox and run `npm run i18n:check`. |
| Part 1 says "mention unrelated dead code, don't delete" | Mention it in the reply. The user decides. |
| Part 1 says "state a brief plan with verify steps" | Give the plan first, then the files, then the Manual Steps, where each step has a "verify" line the user can check. |

## End of every session

Output two things for the user to paste into `PLAN.md`:

1. An updated **Environment State** table (what exists now: migrations run, dashboard settings, files in repo).
2. A new **Progress Log** row: date, step, what was done, what is next, decisions made.

## Open items (do not decide these yourself)

- Medical officer confirmation of alert thresholds and the eligibility checklist
- Clinician review of Filipino wording (list strings in `docs/FILIPINO_REVIEW.md`)
- Ethics/legal approval of Terms, Privacy Notice and consent text
- Whether real patient data will ever be used (would require a separate private, consented setup)
