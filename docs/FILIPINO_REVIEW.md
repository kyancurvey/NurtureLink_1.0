# Filipino wording review

**Status: DRAFT, pending review by the midwife or medical officer.**
Last generated: 2026-10-17, from `src/locales/en.json` and `src/locales/fil.json` (56 strings).

NurtureLink is a monitoring and screening prototype, not a diagnostic device. The Filipino text was written in plain, calm wording. It has **not** been checked by a clinician yet.

## How to review

1. Start with section 1. These are the health and alert words patients will rely on.
2. In the last column, write **OK**, or write the wording you would use instead.
3. If a word could worry or confuse a pregnant patient, say so, even if it is correct.
4. Send the table back. We change `fil.json` only; the English and the app logic do not change.

Please do not change the "Key" column. It is how the app finds the text.

Strings that are the same in both languages on purpose: `NurtureLink` (product name), `EN` and `FIL` (language codes), `English` and `Filipino` (language names), and `Monitor`.

## 1. Health and alert terms (review first)

| # | Key | English | Filipino | Flag | Notes for the reviewer | Reviewer: OK or better wording |
|---|---|---|---|---|---|---|
| 1 | `common:disclaimer` | NurtureLink is for monitoring and screening, not diagnosis. | Ang NurtureLink ay para sa pagsubaybay at screening lamang, hindi para sa diyagnosis. | HEALTH TERM (priority) | Must keep the meaning of the required line "monitoring and screening, not diagnosis". "Screening" is kept in English because that is how it is said in clinics; alternative: "pagsusuri". Please confirm "screening" and "diyagnosis". | |
| 2 | `common:status.success` | Normal | Maayos | ALERT TERM (priority) | "Maayos" = in good order. English "Normal" may sound like a clinical finding. Alternatives: "Normal" (used as is in clinics), "Nasa saklaw" (within range). Which do patients understand best? | |
| 3 | `common:status.warning` | Needs attention | Kailangang bantayan | ALERT TERM (priority) | "Kailangang bantayan" = needs to be watched. Alternatives: "Dapat subaybayan", "Mag-ingat". Is this calm enough without causing alarm? | |
| 4 | `common:status.danger` | Urgent | Agarang atensyon | ALERT TERM (priority) | "Agarang atensyon" = immediate attention. Alternatives: "Kailangang tingnan agad", "Madalian". Should it also say what to do (for example contact the midwife)? That is a later design question. | |
| 5 | `patient:tabs.monitor` | Monitor | Monitor | HEALTH TERM | Kept as "Monitor" (said as is in Filipino health settings). The Filipino word "Subaybay" is too wide for the phone tab bar. Tell us your preferred word for monitoring when it appears in sentences. | |
| 6 | `patient:tabs.alerts` | Alerts | Abiso | ALERT TERM (priority) | "Abiso" = notice. Alternatives: "Alerto", "Babala" (warning). Which word do patients recognise for a health alert? Whatever you choose is used for alerts across the app. | |
| 7 | `patient:tabs.care` | Care | Konsulta | HEALTH TERM | "Konsulta" = consultation. English "Care" is broader (appointments, telemedicine, consult history). Longer "Pangangalaga" does not fit the phone tab bar. Confirm "Konsulta" reads right for this tab. | |

## 2. Brand decision

| # | Key | English | Filipino | Flag | Notes for the reviewer | Reviewer: OK or better wording |
|---|---|---|---|---|---|---|
| 1 | `common:brand.name` | NurtureLink | NurtureLink | BRAND | Product name. Stays "NurtureLink" in both languages. | |
| 2 | `common:brand.tagline` | Nurture Lives, Linking Hearts | Alagaan ang Buhay, Ugnayin ang mga Puso | BRAND DECISION | Translation of the English tagline. Decide: use this Filipino line, or keep the English tagline in both languages. Not a health term. | |

## 3. General interface wording

Low risk. A quick read by any Filipino speaker is enough.

| # | Key | English | Filipino | Flag | Notes for the reviewer | Reviewer: OK or better wording |
|---|---|---|---|---|---|---|
| 1 | `common:language.label` | Language | Wika | - |  | |
| 2 | `common:language.name.en` | English | English | - |  | |
| 3 | `common:language.name.fil` | Filipino | Filipino | - |  | |
| 4 | `common:language.short.en` | EN | EN | - |  | |
| 5 | `common:language.short.fil` | FIL | FIL | - |  | |
| 6 | `common:ui.back` | Back | Bumalik | - |  | |
| 7 | `common:ui.close` | Close | Isara | - |  | |
| 8 | `common:ui.dismiss` | Dismiss | Alisin | - | Closes a message. | |
| 9 | `common:ui.on` | On | Naka-on | - | "Naka-on" = switched on (common usage). Alternative: "Bukas". | |
| 10 | `common:ui.off` | Off | Naka-off | - | "Naka-off" = switched off. Alternative: "Sarado". | |
| 11 | `common:nav.main` | Main navigation | Pangunahing menu | - | Label read aloud by screen readers for the main menu. | |
| 12 | `patient:tabs.home` | Home | Tahanan | - | "Tahanan" = home. Alternative: keep "Home". | |
| 13 | `patient:tabs.profile` | Profile | Ako | - | "Ako" = me (short, fits the tab bar). Alternative: "Profile". | |

## 4. Developer page only

These texts are on the `/#/design` developer page, which is removed before release. No review needed, but note that "Babala" (warning) and "Panganib" (danger) here should be replaced with the words chosen for the alert terms above, so they stay consistent.

| # | Key | English | Filipino | Flag | Notes for the reviewer | Reviewer: OK or better wording |
|---|---|---|---|---|---|---|
| 1 | `common:design.title` | Design system | Sistema ng disenyo | DEV ONLY |  | |
| 2 | `common:design.subtitle` | A visual check of the shared components. For developers only. | Tingnan dito ang hitsura ng mga bahagi ng app. Para sa mga developer lamang. | DEV ONLY |  | |
| 3 | `common:design.header.action` | Header action | Aksyon sa header | DEV ONLY |  | |
| 4 | `common:design.section.colors` | Colors | Mga kulay | DEV ONLY |  | |
| 5 | `common:design.section.buttons` | Buttons | Mga button | DEV ONLY |  | |
| 6 | `common:design.section.status` | Status badges | Mga badge ng katayuan | DEV ONLY |  | |
| 7 | `common:design.section.form` | Form fields | Mga field ng form | DEV ONLY |  | |
| 8 | `common:design.section.overlays` | Dialogs and messages | Mga dialog at mensahe | DEV ONLY |  | |
| 9 | `common:design.section.split` | Split view (list and detail) | Split view (listahan at detalye) | DEV ONLY |  | |
| 10 | `common:design.button.primary` | Primary | Pangunahin | DEV ONLY |  | |
| 11 | `common:design.button.secondary` | Secondary | Pangalawa | DEV ONLY |  | |
| 12 | `common:design.button.danger` | Danger | Mapanganib | DEV ONLY |  | |
| 13 | `common:design.button.disabled` | Disabled | Naka-disable | DEV ONLY |  | |
| 14 | `common:design.button.full` | Full width | Buong lapad | DEV ONLY |  | |
| 15 | `common:design.field.label` | Sample field | Halimbawang field | DEV ONLY |  | |
| 16 | `common:design.field.hint` | A short hint appears here. | Isang maikling gabay ang lalabas dito. | DEV ONLY |  | |
| 17 | `common:design.field.placeholder` | Type here | Mag-type dito | DEV ONLY |  | |
| 18 | `common:design.field.error` | This field is required. | Kailangang punan ang field na ito. | DEV ONLY |  | |
| 19 | `common:design.checkbox.label` | I agree to this sample item | Sumasang-ayon ako sa halimbawang ito | DEV ONLY |  | |
| 20 | `common:design.toggle.label` | Sample setting | Halimbawang setting | DEV ONLY |  | |
| 21 | `common:design.modal.open` | Open dialog | Buksan ang dialog | DEV ONLY |  | |
| 22 | `common:design.modal.title` | Sample dialog | Halimbawang dialog | DEV ONLY |  | |
| 23 | `common:design.modal.body` | This is how a confirmation dialog looks. | Ganito ang hitsura ng dialog ng kumpirmasyon. | DEV ONLY |  | |
| 24 | `common:design.modal.cancel` | Cancel | Kanselahin | DEV ONLY |  | |
| 25 | `common:design.modal.confirm` | Confirm | Kumpirmahin | DEV ONLY |  | |
| 26 | `common:design.toast.info` | Info | Impormasyon | DEV ONLY |  | |
| 27 | `common:design.toast.success` | Success | Matagumpay | DEV ONLY |  | |
| 28 | `common:design.toast.warning` | Warning | Babala | DEV ONLY |  | |
| 29 | `common:design.toast.danger` | Danger | Panganib | DEV ONLY |  | |
| 30 | `common:design.toast.message` | This is a sample message. | Ito ay halimbawang mensahe. | DEV ONLY |  | |
| 31 | `common:design.split.empty` | Select one to see its detail. | Pumili ng isa upang makita ang detalye. | DEV ONLY |  | |
| 32 | `common:design.split.item` | Sample {{n}} | Halimbawa {{n}} | DEV ONLY |  | |
| 33 | `common:design.split.detail` | Detail {{n}} | Detalye {{n}} | DEV ONLY |  | |
| 34 | `common:design.split.body` | Detail content goes here. | Dito ilalagay ang nilalaman ng detalye. | DEV ONLY |  | |

## Not yet written (later steps)

Terms and consent, Privacy Notice, login, alerts text, error messages, patient and provider screens. Each will be added here as it is written. Consent and legal text also needs ethics/legal review (see `PLAN.md`, open items).
