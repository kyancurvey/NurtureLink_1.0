# LEGAL_ALIGNMENT_PH.md

**Status: DRAFT, pending ethics/legal review. Not legal advice.**

A checklist that maps each Philippine rule named in `PLAN.md` (Step 2.4 plan) to the document section and the app feature that covers it. The author of this file is not a lawyer. The reviewing lawyer or the Data Protection Officer fills the last column, confirms each rule is current, and replaces the draft texts (`supabase/migrations/006_consent_documents_seed.sql`) with approved ones as a new version (`docs/ADMIN_SQL.md`, snippet 8).

Document abbreviations: TOU = Terms of Use, PN = Privacy Notice, IC = Informed Consent to Monitoring, MD = Medical Disclaimer, GA = Guardian Assent, SD = Study data (optional), PC = Provider Confidentiality.

| # | Rule (as understood, reviewer to confirm) | Where the draft covers it | App feature | Reviewer sign-off (name, date, OK or change) |
|---|---|---|---|---|
| 1 | RA 10173 (Data Privacy Act), Sec. 13: health data is sensitive personal information | PN s.2 (what we collect), s.4 (basis) | Privacy Notice is its own required checkbox | |
| 2 | Consent is freely given, specific, informed, evidenced and withdrawable (Sec. 3(b), IRR) | IC s.1 to 6; PN s.4, s.8 | One checkbox per document, nothing ticked for the person, no "accept all"; `consent_records` stores user, document, version, language and time; Profile > Privacy to withdraw | |
| 3 | Declared, specific, legitimate purpose; proportionate collection (Sec. 11, 12) | PN s.2 and s.3 | Only the data listed is collected; study use is a separate optional item | |
| 4 | Data subject rights: informed, access, object, correct, erase or block, portability, damages, complain to the NPC (Sec. 16 to 19) | PN s.8 | Profile > Privacy: view what was accepted, download a copy, withdraw, "Request data deletion"; correction and objection through the DPO contact (in-app form later) | |
| 5 | Data Protection Officer and accountability (Sec. 20, 21); processors | PN s.1, s.5 (Supabase named as processor) | Placeholders `[CONTROLLER NAME]`, `[DPO NAME AND EMAIL]`, `[NPC REGISTRATION STATUS]` | |
| 6 | Personal data breach: notify NPC and affected people within 72 hours when notifiable | PN s.9; PC item 6 | Open item: a written breach procedure | |
| 7 | Cross-border storage must be disclosed and adequately protected | PN s.6 | Placeholder `[SUPABASE REGION COUNTRY]`; the owner confirms the real region | |
| 8 | Minors: parental or guardian consent; age of majority is 18 | GA; TOU s.2 | Guardian Assent appears only when the date of birth shows under 18 (or is missing); the minor cannot continue until it is ticked. Decision for the reviewer: is a tick enough, or is a guardian signature or verification needed? | |
| 9 | Telemedicine (DOH-DILG-PHIC JAO 2021-0001; status of any Telemedicine Act to be checked): informed consent covering purpose, participants, records, confidentiality, rights, risks and benefits | IC s.7 (video and chat are excluded and get a separate consent); MD | The Care tab (Phase 6) gets its own telemedicine consent | |
| 10 | Research and study data: ethics-board approval, specific optional consent | SD s.1 to 4 | Optional, unticked, never required; can be given or withdrawn later in Profile > Privacy; placeholder `[ETHICS BOARD AND PROTOCOL NUMBER]` | |
| 11 | Electronic consent and records (E-Commerce Act, RA 8792) | n/a | Consent is recorded electronically with a server timestamp (the browser clock is never trusted: migration 007) | |
| 12 | Health software or devices may fall under FDA device rules (RA 9711) | TOU s.1 and s.9; MD s.1 | Wording says monitoring and screening, not diagnosis; the lawyer decides whether registration or exemption wording is needed | |
| 13 | Professional and provider confidentiality | PC | Providers must accept PC before the dashboard opens; every provider login is written to `audit_log` (Phase 4 adds an entry whenever a patient record is opened) | |
| 14 | Retention and erasure | PN s.7, s.8 | Deletion request is filed in the app and handled by the admin (`docs/ADMIN_SQL.md`, snippet 10); retention period is for the reviewer to set | |

## Assumptions the reviewer confirms or changes

1. A minor ticks Guardian Assent with a guardian present; the app does not verify the guardian.
2. A user with **no date of birth on file** is asked for Guardian Assent (the cautious choice).
3. Withdrawing a required consent returns the person to the consent screen and stops monitoring and data sharing until they agree again. Withdrawing the optional study item only stops study use.
4. Enforcement is by the app screen only; the database records consent but does not refuse data access without it (open item).
5. If a document exists in only one language at the newest version, the other language shows it in English with a notice, and the stored record shows that language.
6. A person who withdrew everything can still reach "Request data deletion" from the consent screen.
7. The emergency number "911" in the drafts is the Philippine national emergency hotline (confirm).

## Placeholders that must be filled before any real user

`[CONTROLLER NAME]`, `[DPO NAME AND EMAIL]`, `[NPC REGISTRATION STATUS]`, `[REVIEWING LAWYER OR OFFICE]`, `[ETHICS BOARD AND PROTOCOL NUMBER]`, `[SUPABASE REGION COUNTRY]`, `[X DAYS]`.
