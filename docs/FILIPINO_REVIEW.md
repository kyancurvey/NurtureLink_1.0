# Filipino wording review

**Status: DRAFT, pending review by the midwife or medical officer.**
Last generated: 2026-10-17, from `src/locales/en.json` and `src/locales/fil.json` (137 strings).

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

## 5. Provider tabs (step 2.3)

Phones show five of the seven provider tabs; Validation and Reports are laptop-only for now.

| # | Key | English | Filipino | Flag | Notes for the reviewer | Reviewer: OK or better wording |
|---|---|---|---|---|---|---|
| 1 | `provider:tabs.overview` | Overview | Buod | HEALTH TERM | Provider tab. Short word so it fits a phone tab bar. Alternative: "Pangkalahatang-tanaw" (too long). | |
| 2 | `provider:tabs.patients` | Patients | Pasyente | HEALTH TERM | Provider tab. "Pasyente" = patients. | |
| 3 | `provider:tabs.alerts` | Alerts | Abiso | ALERT TERM | Must match the word chosen for patient alerts (section 1, row 6). | |
| 4 | `provider:tabs.consults` | Consults | Konsulta | HEALTH TERM | Must match the word chosen for patient "Care" (section 1, row 7). | |
| 5 | `provider:tabs.validation` | Validation | Beripikasyon | HEALTH TERM | Laptop-only tab for now. "Beripikasyon" = verification. Alternative: "Pagpapatunay". | |
| 6 | `provider:tabs.reports` | Reports | Ulat | HEALTH TERM | Laptop-only tab for now. "Ulat" = report. | |
| 7 | `provider:tabs.settings` | Settings | Setting | HEALTH TERM | Provider tab. Kept as "Setting" (common usage). | |

## 6. Sign-in screens (step 2.3)

Log in, sign up, forgot and reset password, provider invite, admin notice. Low risk, except the two lines flagged LEGAL TEXT.

| # | Key | English | Filipino | Flag | Notes for the reviewer | Reviewer: OK or better wording |
|---|---|---|---|---|---|---|
| 1 | `auth:working` | Please wait… | Sandali lang… | - |  | |
| 2 | `auth:logout` | Log out | Mag-log out | - |  | |
| 3 | `auth:backToLogin` | Back to log in | Bumalik sa log in | - |  | |
| 4 | `auth:field.email` | Email address | Email address | - |  | |
| 5 | `auth:field.password` | Password | Password | - |  | |
| 6 | `auth:field.newPassword` | New password | Bagong password | - |  | |
| 7 | `auth:field.passwordHint` | At least 8 characters. | Hindi bababa sa 8 karakter. | - |  | |
| 8 | `auth:field.dob` | Date of birth | Petsa ng kapanganakan | - |  | |
| 9 | `auth:field.dobHint` | We use this to check whether a parent or guardian also needs to agree. | Ginagamit namin ito para malaman kung kailangan ding sumang-ayon ng magulang o tagapag-alaga. | LEGAL TEXT (draft) | Explains why the date of birth is asked. DRAFT, pending ethics/legal review. | |
| 10 | `auth:field.code` | Invite code | Code ng imbitasyon | - |  | |
| 11 | `auth:login.title` | Welcome back | Maligayang pagbabalik | - |  | |
| 12 | `auth:login.subtitle` | Log in to your NurtureLink account. | Mag-log in sa iyong NurtureLink account. | - |  | |
| 13 | `auth:login.submit` | Log in | Mag-log in | - |  | |
| 14 | `auth:login.forgot` | Forgot your password? | Nakalimutan ang password? | - |  | |
| 15 | `auth:login.createAccount` | Create a patient account | Gumawa ng account ng pasyente | - |  | |
| 16 | `auth:login.haveInvite` | Have a provider invite code? | May code ng imbitasyon bilang provider? | - |  | |
| 17 | `auth:signup.title` | Create your account | Gawin ang iyong account | - |  | |
| 18 | `auth:signup.subtitle` | For pregnant patients. Healthcare providers need an invite code instead. | Para sa mga buntis na pasyente. Ang mga healthcare provider ay kailangan ng code ng imbitasyon. | - |  | |
| 19 | `auth:signup.submit` | Create account | Gumawa ng account | - |  | |
| 20 | `auth:signup.haveAccount` | Already have an account? Log in | May account na? Mag-log in | - |  | |
| 21 | `auth:signup.minorNote` | You are under 18, so a parent or guardian will also be asked to agree. You can still create your account. | Wala ka pang 18 taong gulang, kaya hihilingin ding sumang-ayon ang magulang o tagapag-alaga mo. Maaari ka pa ring gumawa ng account. | LEGAL TEXT (draft) | Shown when the date of birth makes the person under 18. DRAFT, pending ethics/legal review: the real guardian assent text comes in step 2.4. Please check that "magulang o tagapag-alaga" (parent or guardian) is the right pair of words. | |
| 22 | `auth:signup.checkEmail.title` | Check your email | Tingnan ang iyong email | - |  | |
| 23 | `auth:signup.checkEmail.body` | If {{email}} can be used for a new account, we have sent it a link. Open the link to confirm your account, then log in. | Kung magagamit ang {{email}} para sa bagong account, nagpadala kami ng link dito. Buksan ang link para kumpirmahin ang account, pagkatapos ay mag-log in. | - | Written so it does not confirm whether an email already has an account. | |
| 24 | `auth:signup.checkEmail.sameBrowser` | Please open the link in this same browser. It may take a few minutes to arrive. Check your spam folder too. | Pakibuksan ang link sa browser na ito. Maaaring abutin ng ilang minuto bago dumating. Tingnan din ang spam folder. | - |  | |
| 25 | `auth:forgot.title` | Reset your password | I-reset ang iyong password | - |  | |
| 26 | `auth:forgot.subtitle` | Enter your email address and we will send you a link to choose a new password. | Ilagay ang iyong email address at magpapadala kami ng link para pumili ng bagong password. | - |  | |
| 27 | `auth:forgot.submit` | Send reset link | Ipadala ang link | - |  | |
| 28 | `auth:forgot.sent.title` | Check your email | Tingnan ang iyong email | - |  | |
| 29 | `auth:forgot.sent.body` | If there is an account for {{email}}, a reset link is on its way. | Kung may account para sa {{email}}, papunta na ang link sa pag-reset. | - | Same reason: does not confirm whether an account exists. | |
| 30 | `auth:reset.title` | Choose a new password | Pumili ng bagong password | - |  | |
| 31 | `auth:reset.subtitle` | Your link worked. Enter a new password below. | Gumana ang iyong link. Ilagay sa ibaba ang bagong password. | - |  | |
| 32 | `auth:reset.submit` | Save new password | I-save ang bagong password | - |  | |
| 33 | `auth:reset.invalid` | This reset link is not valid any more. It may have expired, been used already, or been opened in a different browser. Please ask for a new one. | Hindi na valid ang link na ito sa pag-reset. Maaaring nag-expire na ito, nagamit na, o binuksan sa ibang browser. Humingi ng bagong link. | - |  | |
| 34 | `auth:reset.requestNew` | Send me a new link | Magpadala ng bagong link | - |  | |
| 35 | `auth:invite.title` | Provider invite | Imbitasyon para sa provider | - |  | |
| 36 | `auth:invite.subtitle` | Enter the code you were given to turn this account into a provider account. | Ilagay ang code na ibinigay sa iyo para gawing provider account ang account na ito. | - |  | |
| 37 | `auth:invite.submit` | Use this code | Gamitin ang code | - |  | |
| 38 | `auth:invite.needAccount` | To use an invite code, first create an account or log in. Then enter your code. | Para magamit ang code ng imbitasyon, gumawa muna ng account o mag-log in. Pagkatapos, ilagay ang iyong code. | - |  | |
| 39 | `auth:invite.notNow` | Not now | Hindi muna | - |  | |
| 40 | `auth:admin.title` | Project owner account | Account ng may-ari ng proyekto | - |  | |
| 41 | `auth:admin.body` | This is the admin account. Admin tasks are done in the Supabase SQL Editor, not in this app. Use a patient or provider account to try the app. | Ito ang admin account. Ginagawa ang mga gawain ng admin sa Supabase SQL Editor, hindi sa app na ito. Gumamit ng account ng pasyente o provider para subukan ang app. | - |  | |

## 7. Error and empty-state messages (step 2.3)

Calm wording on purpose. Please read each as a worried person would.

| # | Key | English | Filipino | Flag | Notes for the reviewer | Reviewer: OK or better wording |
|---|---|---|---|---|---|---|
| 1 | `errors:email_required` | Please enter your email address. | Pakilagay ang iyong email address. | - |  | |
| 2 | `errors:email_invalid` | That does not look like an email address. Please check it. | Mukhang hindi ito email address. Pakisuri. | - |  | |
| 3 | `errors:password_required` | Please enter your password. | Pakilagay ang iyong password. | - |  | |
| 4 | `errors:password_short` | Please use at least 8 characters. | Gumamit ng hindi bababa sa 8 karakter. | - |  | |
| 5 | `errors:dob_required` | Please enter your date of birth. | Pakilagay ang iyong petsa ng kapanganakan. | - |  | |
| 6 | `errors:dob_invalid` | Please enter a real date of birth. | Pakilagay ang tamang petsa ng kapanganakan. | - |  | |
| 7 | `errors:code_required` | Please enter your invite code. | Pakilagay ang iyong code ng imbitasyon. | - |  | |
| 8 | `errors:invalid_credentials` | That email or password is not right. Please try again. | Mali ang email o password. Pakisubukan muli. | - | One message on purpose: it must not say whether the email exists. | |
| 9 | `errors:email_not_confirmed` | Please confirm your email first. Check your inbox for our message. | Kumpirmahin muna ang iyong email. Tingnan ang inbox para sa mensahe namin. | - |  | |
| 10 | `errors:account_exists` | We could not create that account. If you already have one, try logging in or resetting your password. | Hindi namin magawa ang account na iyon. Kung mayroon ka nang account, subukang mag-log in o i-reset ang password. | - |  | |
| 11 | `errors:weak_password` | That password is too easy to guess. Please try a longer one with more variety. | Masyadong madaling hulaan ang password. Gumamit ng mas mahaba at mas iba-iba. | - |  | |
| 12 | `errors:same_password` | Please choose a password that is different from your old one. | Pumili ng password na iba sa dati mong password. | - |  | |
| 13 | `errors:rate_limit` | Too many tries just now. Please wait a few minutes and try again. | Masyadong maraming pagsubok. Maghintay ng ilang minuto bago subukan muli. | - |  | |
| 14 | `errors:email_rate_limit` | Only a few emails can be sent each hour. Please wait a while and try again. | Kaunti lang ang email na maipapadala kada oras. Maghintay muna bago subukan muli. | - |  | |
| 15 | `errors:offline` | We cannot reach the server. Please check your internet connection and try again. | Hindi makakonekta sa server. Pakisuri ang iyong internet at subukan muli. | - |  | |
| 16 | `errors:not_signed_in` | Your session has ended. Please log in again. | Natapos na ang iyong session. Mag-log in muli. | - |  | |
| 17 | `errors:no_profile` | We could not find your profile. Please log out and create your account again, or tell the project owner. | Hindi namin makita ang iyong profile. Mag-log out at gumawa muli ng account, o sabihin sa may-ari ng proyekto. | - |  | |
| 18 | `errors:not_eligible` | This account already has a provider or admin role, so a code is not needed. | May tungkulin nang provider o admin ang account na ito, kaya hindi na kailangan ng code. | - |  | |
| 19 | `errors:invalid_invite` | That code did not work. It may be wrong, already used, expired, or meant for a different email. Please check it, or ask for a new one. | Hindi gumana ang code. Maaaring mali ito, nagamit na, nag-expire na, o para sa ibang email. Pakisuri, o humingi ng bagong code. | - | One message on purpose: it must not say which part was wrong. | |
| 20 | `errors:invalid_language` | That language is not available. | Hindi available ang wikang iyon. | - |  | |
| 21 | `errors:role_change_not_allowed` | Account roles cannot be changed from the app. | Hindi mapapalitan ang tungkulin ng account mula sa app. | - |  | |
| 22 | `errors:permission_denied` | This account is not allowed to do that. If you think it should be, this is a setup problem, not something you did wrong. Please tell the project owner. | Hindi pinapayagan ang account na ito na gawin iyon. Kung sa tingin mo ay dapat, problema ito sa setup at hindi ikaw ang nagkamali. Pakisabi sa may-ari ng proyekto. | ERROR WORDING | Shown when the database refuses access. Meant to be calm and to say it is not the person's fault. | |
| 23 | `errors:technical_detail` | Technical detail: {{detail}} | Teknikal na detalye: {{detail}} | - |  | |
| 24 | `errors:not_configured` | The app is not connected to its database yet. Please tell the project owner. | Hindi pa nakakonekta ang app sa database nito. Pakisabi sa may-ari ng proyekto. | - |  | |
| 25 | `errors:unknown` | Something went wrong. Please try again. If it keeps happening, tell the project owner. | May nangyaring problema. Pakisubukan muli. Kung patuloy itong mangyari, sabihin sa may-ari ng proyekto. | - |  | |
| 26 | `errors:link_expired` | The link in the email has expired or was already used. Please log in, or ask for a new link. | Nag-expire na o nagamit na ang link sa email. Mag-log in, o humiling ng bagong link. | - |  | |
| 27 | `errors:link_invalid` | The link in the email did not work. Please log in, or ask for a new link. | Hindi gumana ang link sa email. Mag-log in, o humiling ng bagong link. | - |  | |
| 28 | `errors:profile_title` | We could not load your account | Hindi namin ma-load ang iyong account | - |  | |
| 29 | `errors:retry` | Try again | Subukan muli | - |  | |
| 30 | `errors:language_not_saved` | Your language choice could not be saved to your account. It still works on this device. | Hindi nai-save sa iyong account ang napili mong wika. Gumagana pa rin ito sa device na ito. | - |  | |
| 31 | `common:emptyState.title` | Nothing here yet | Wala pa rito | - |  | |
| 32 | `common:emptyState.body` | This part of NurtureLink is still being built. Please check back soon. | Ginagawa pa ang bahaging ito ng NurtureLink. Bumalik muli sa lalong madaling panahon. | - |  | |
| 33 | `errors:email_not_authorized` | Our email service cannot send to this address yet. Please tell the project owner. | Hindi pa makapagpadala ng email ang aming serbisyo sa address na ito. Pakisabi sa may-ari ng proyekto. | - | Shown when Supabase's built-in email refuses an address (project owner must set up custom email). | |

## Not yet written (later steps)

Terms and consent, Privacy Notice, guardian assent text, alerts text, patient and provider screen content. Each will be added here as it is written. Consent and legal text also needs ethics/legal review (see `PLAN.md`, open items).
