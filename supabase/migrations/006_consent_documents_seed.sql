-- =====================================================================
-- 006_consent_documents_seed.sql
-- NurtureLink: DRAFT placeholder text for the seven consent documents, in
-- English and Filipino, version 1.
--
-- WHAT IT DOES
--   Inserts 14 rows into public.consent_documents (7 document types x 2
--   languages), all version 1, all UNPUBLISHED (is_published = false):
--     terms_of_use, privacy_notice (Data Privacy Act, RA 10173),
--     informed_consent, medical_disclaimer, guardian_assent,
--     study_data_use (the optional study item), provider_confidentiality.
--   Every text starts with "DRAFT, pending ethics/legal review", says it is
--   not legal advice, and keeps the square-bracket placeholders from PLAN.md
--   ([CONTROLLER NAME], [DPO NAME AND EMAIL], [NPC REGISTRATION STATUS],
--   [REVIEWING LAWYER OR OFFICE], [ETHICS BOARD AND PROTOCOL NUMBER],
--   [SUPABASE REGION COUNTRY], [X DAYS]).
--
-- THE APP SHOWS NOTHING UNTIL YOU PUBLISH. The app reads only published rows.
-- Until you publish, every patient and provider is stopped at the consent
-- screen, which says the documents are not available yet. To publish version 1
-- for testing, use docs/ADMIN_SQL.md snippet 7.
--
-- NOT LEGAL ADVICE. These texts were drafted to follow the Philippine rules
-- listed in PLAN.md (see docs/LEGAL_ALIGNMENT_PH.md). A Philippine lawyer or
-- the Data Protection Officer must review and replace them before any real
-- user sees them. Never give the app to real users while a [placeholder]
-- is still in the text.
--
-- DEPENDS ON: 001 (the consent_documents table). Grants and RLS from 004 and
-- 005 are unchanged; nothing here touches them.
--
-- SAFE TO RE-RUN: yes. A re-run refreshes the text of rows that are still
-- UNPUBLISHED (so you can edit this file while drafting). It never changes a
-- row that is already published: a published text is evidence of what people
-- agreed to, so changes go into a NEW version (docs/ADMIN_SQL.md snippet 8).
--
-- HOW TO UNDO (only while nothing has been accepted; consent_records points
-- at these rows and blocks deletion once someone has accepted):
--   delete from public.consent_documents where version = 1 and not is_published;
-- =====================================================================

insert into public.consent_documents (doc_type, version, language, title, body, is_published)
values

-- =====================================================================
-- terms_of_use
-- =====================================================================
('terms_of_use', 1, 'en', 'Terms of Use', $nl$DRAFT, pending ethics/legal review.
This is placeholder text for a student prototype. It is not legal advice. It has not been checked by a lawyer, the Data Protection Officer or an ethics board. Items in [square brackets] are not filled in yet.

1. What NurtureLink is
NurtureLink is a prototype app for monitoring and screening during pregnancy. It is not a medical device approved for diagnosis. It does not diagnose, treat or prevent any condition.

2. Who can use it
Pregnant patients taking part in the pilot can make a patient account. If you are under 18, a parent or guardian must also agree (see the Guardian Assent). Healthcare providers can only join with an invite code from the project team.

3. What the app can and cannot do
Readings and alerts are estimates. They can be wrong or missing, for example when the belt is not worn well, the battery is low, or there is no internet. NurtureLink does not replace your check-ups, your midwife or doctor, or emergency care. In an emergency, do not wait for the app. Call your local emergency number (911 in the Philippines) or go to the nearest health facility.

4. Your account
Keep your password private and do not share your account. Tell us if you think someone else used it. Give true information when you sign up.

5. Using the app properly
Do not try to break the app, copy it, or look at anyone else's information.

6. Prototype limits
This is a prototype. It may change, stop working or be switched off without notice. We cannot promise that it will always be available or free of errors.

7. Who runs this prototype
[CONTROLLER NAME] runs this prototype. For questions, contact [DPO NAME AND EMAIL].

8. Changes
If these terms change, we will ask you to read and accept the new version before you continue.

9. Law, responsibility and device rules
[REVIEWING LAWYER OR OFFICE] will write this section: the law that applies, the limits of our responsibility, and whether any rules for health software or medical devices apply to this prototype.$nl$, false),

('terms_of_use', 1, 'fil', 'Mga Tuntunin sa Paggamit', $nl$DRAFT, pending ethics/legal review.
(Draft pa lamang. Naghihintay ng pagsusuri ng ethics at legal.)
Ito ay pansamantalang teksto para sa isang prototype ng mga mag-aaral. Hindi ito legal advice. Hindi pa ito nasusuri ng abogado, ng Data Protection Officer, o ng ethics board. Ang mga nasa [square brackets] ay hindi pa napupunan.

1. Ano ang NurtureLink
Ang NurtureLink ay isang prototype na app para sa pagsubaybay at screening habang buntis. Hindi ito aprubadong medical device para sa diyagnosis. Hindi ito nagdidiyagnos, hindi ito gumagamot, at hindi ito pumipigil sa anumang kondisyon.

2. Sino ang puwedeng gumamit
Ang mga buntis na kasali sa pilot ay puwedeng gumawa ng patient account. Kung wala ka pang 18 taong gulang, kailangan ding sumang-ayon ang magulang o tagapag-alaga mo (tingnan ang Pagsang-ayon ng Magulang o Tagapag-alaga). Ang mga healthcare provider ay makakasali lamang gamit ang invite code mula sa project team.

3. Ang kaya at hindi kayang gawin ng app
Tantiya lamang ang mga reading at abiso. Maaari itong mali o wala, halimbawa kapag hindi maayos ang pagkakasuot ng belt, mahina ang baterya, o walang internet. Hindi napapalitan ng NurtureLink ang iyong mga check-up, ang iyong midwife o doktor, o ang emergency care. Kapag emergency, huwag nang hintayin ang app. Tumawag sa lokal na emergency number (911 sa Pilipinas) o pumunta sa pinakamalapit na pasilidad pangkalusugan.

4. Ang iyong account
Ingatan ang iyong password at huwag ipagamit ang iyong account. Sabihin sa amin kung sa tingin mo ay may ibang gumamit nito. Magbigay ng totoong impormasyon kapag nag-sign up.

5. Wastong paggamit ng app
Huwag subukang sirain o kopyahin ang app, o silipin ang impormasyon ng ibang tao.

6. Mga limitasyon ng prototype
Prototype ito. Maaari itong magbago, tumigil gumana, o patayin nang walang paunang abiso. Hindi namin maipapangako na laging available ito o walang mali.

7. Sino ang nagpapatakbo ng prototype na ito
Ang [CONTROLLER NAME] ang nagpapatakbo ng prototype na ito. Para sa mga tanong, makipag-ugnayan sa [DPO NAME AND EMAIL].

8. Mga pagbabago
Kung magbago ang mga tuntuning ito, hihilingin namin na basahin at tanggapin mo ang bagong bersyon bago ka magpatuloy.

9. Batas, pananagutan at mga patakaran sa device
Isusulat ng [REVIEWING LAWYER OR OFFICE] ang bahaging ito: ang batas na umiiral, ang mga limitasyon ng aming pananagutan, at kung may mga patakaran para sa health software o medical device na sakop ang prototype na ito.$nl$, false),

-- =====================================================================
-- privacy_notice (Data Privacy Act of 2012, RA 10173)
-- =====================================================================
('privacy_notice', 1, 'en', 'Privacy Notice (Data Privacy Act, RA 10173)', $nl$DRAFT, pending ethics/legal review.
This is placeholder text for a student prototype. It is not legal advice. It has not been checked by a lawyer, the Data Protection Officer or an ethics board. Items in [square brackets] are not filled in yet.

1. Who we are
[CONTROLLER NAME] decides how your personal data is used (the "controller"). Our Data Protection Officer is [DPO NAME AND EMAIL]. Registration with the National Privacy Commission (NPC): [NPC REGISTRATION STATUS].

2. What we collect
- Account: your email address, date of birth, language, and a display name if you give one.
- Pregnancy details that you enter, such as due date, history and conditions.
- Readings from the belt and wristband: your baby's heart rate, signal quality, your heart rate, oxygen level (SpO2) and temperature, each with date and time. Also readings you type in by hand.
- Alerts, SOS requests, appointments, and notes written by your provider.
- Your consent records: what you agreed to, which version, in which language, and when.
- A log of when a provider opens your record.
Health information is sensitive personal information under the Data Privacy Act of 2012 (RA 10173).

3. Why we use it
To show you your readings, to raise alerts for you and your assigned provider, to arrange appointments and consults, and to keep the app safe and working. We do not sell your data and we do not use it for advertising. We use it for the study only if you tick the optional study item.

4. Our basis
We use your health information because you agree to it (your consent). You can withdraw your consent at any time (see section 8).

5. Who can see it
You. Your assigned provider (only the provider assigned to you). The project team, only as needed to run and fix the system. Supabase, the company that hosts our database, which handles data for us as a processor. We do not share your data with anyone else unless the law requires it.

6. Where it is stored
In a Supabase database in [SUPABASE REGION COUNTRY]. This may be outside the Philippines. Access rules make sure each person sees only what they should, and data travels over encrypted connections. No system is perfectly secure.

7. How long we keep it
For as long as needed for the purposes above while your account is active. [REVIEWING LAWYER OR OFFICE] will set the exact period before real use. After that it is deleted or made anonymous.

8. Your rights
Under RA 10173 you have the right to be informed, to access your data, to object, to correct it, to ask for it to be erased or blocked, to receive a copy (data portability), to claim damages if you were harmed, and to complain to the National Privacy Commission (NPC).
In the app, go to Profile > Privacy to see what you agreed to, download a copy, withdraw a consent, or ask for your data to be deleted. To correct your data or object to its use, contact [DPO NAME AND EMAIL]. We aim to reply within [X DAYS].
If you withdraw a required consent, monitoring and data sharing stop until you agree again.

9. If something goes wrong
If a personal data breach could harm you, we will tell you and the NPC as the law requires (within 72 hours when it applies).

10. Changes
If this notice changes, we will ask you to read and accept the new version.$nl$, false),

('privacy_notice', 1, 'fil', 'Paunawa sa Privacy (Data Privacy Act, RA 10173)', $nl$DRAFT, pending ethics/legal review.
(Draft pa lamang. Naghihintay ng pagsusuri ng ethics at legal.)
Ito ay pansamantalang teksto para sa isang prototype ng mga mag-aaral. Hindi ito legal advice. Hindi pa ito nasusuri ng abogado, ng Data Protection Officer, o ng ethics board. Ang mga nasa [square brackets] ay hindi pa napupunan.

1. Sino kami
Ang [CONTROLLER NAME] ang nagpapasya kung paano gagamitin ang iyong personal na datos (ang "controller"). Ang aming Data Protection Officer ay si [DPO NAME AND EMAIL]. Rehistro sa National Privacy Commission (NPC): [NPC REGISTRATION STATUS].

2. Ano ang aming kinokolekta
- Account: ang iyong email address, petsa ng kapanganakan, wika, at display name kung magbibigay ka nito.
- Mga detalye ng pagbubuntis na ilalagay mo, tulad ng due date, kasaysayan at mga kondisyon.
- Mga reading mula sa belt at wristband: ang heart rate ng iyong sanggol, kalidad ng signal, ang iyong heart rate, antas ng oxygen (SpO2) at temperatura, bawat isa ay may petsa at oras. Pati ang mga reading na manu-mano mong inilagay.
- Mga abiso, SOS, appointment, at mga tala na isinulat ng iyong provider.
- Ang iyong mga consent record: ang sinang-ayunan mo, anong bersyon, sa anong wika, at kailan.
- Isang talaan kung kailan binuksan ng provider ang iyong record.
Ang impormasyon tungkol sa kalusugan ay sensitibong personal na impormasyon sa ilalim ng Data Privacy Act of 2012 (RA 10173).

3. Bakit namin ito ginagamit
Upang ipakita sa iyo ang iyong mga reading, magpadala ng abiso sa iyo at sa nakatalaga mong provider, mag-ayos ng appointment at konsulta, at panatilihing ligtas at gumagana ang app. Hindi namin ibinebenta ang iyong datos at hindi namin ito ginagamit sa advertising. Gagamitin lamang namin ito para sa pag-aaral kung lalagyan mo ng tsek ang opsyonal na aytem para sa pag-aaral.

4. Ang aming batayan
Ginagamit namin ang impormasyon tungkol sa iyong kalusugan dahil pumapayag ka (iyong pahintulot). Maaari mong bawiin ang pahintulot na ito anumang oras (tingnan ang bahagi 8).

5. Sino ang makakakita
Ikaw. Ang nakatalaga mong provider (ang provider lamang na nakatalaga sa iyo). Ang project team, kung kailangan lamang para patakbuhin at ayusin ang sistema. Ang Supabase, ang kumpanyang nagho-host ng aming database, na humahawak ng datos para sa amin bilang processor. Hindi namin ibabahagi ang iyong datos sa iba maliban kung hinihingi ng batas.

6. Saan ito iniimbak
Sa isang Supabase database sa [SUPABASE REGION COUNTRY]. Maaaring nasa labas ito ng Pilipinas. Tinitiyak ng mga patakaran sa pag-access na makikita ng bawat tao ang nararapat lamang sa kaniya, at naka-encrypt ang koneksyon na dinadaanan ng datos. Walang sistemang lubos na ligtas.

7. Gaano katagal namin ito iingatan
Hangga't kailangan para sa mga layunin sa itaas habang aktibo ang iyong account. Ang [REVIEWING LAWYER OR OFFICE] ang magtatakda ng eksaktong haba ng panahon bago magamit ng totoong user. Pagkatapos nito, buburahin ito o gagawing anonymous.

8. Ang iyong mga karapatan
Sa ilalim ng RA 10173, may karapatan kang malaman ang tungkol sa iyong datos, ma-access ito, tumutol, ipaayos ito, hilingin na burahin o harangan ito, makatanggap ng kopya (data portability), humingi ng danyos kung ikaw ay napinsala, at magreklamo sa National Privacy Commission (NPC).
Sa app, pumunta sa Profile > Privacy para makita ang sinang-ayunan mo, mag-download ng kopya, bawiin ang pahintulot, o hilingin na burahin ang iyong datos. Para ipaayos ang iyong datos o tumutol sa paggamit nito, makipag-ugnayan sa [DPO NAME AND EMAIL]. Sisikapin naming sumagot sa loob ng [X DAYS].
Kung babawiin mo ang kinakailangang pahintulot, titigil ang pagsubaybay at pagbabahagi ng datos hanggang pumayag kang muli.

9. Kung may mangyaring problema
Kung ang paglabag sa seguridad ng personal na datos ay maaaring makapinsala sa iyo, sasabihin namin sa iyo at sa NPC ayon sa hinihingi ng batas (sa loob ng 72 oras kung naaangkop).

10. Mga pagbabago
Kung magbago ang paunawang ito, hihilingin namin na basahin at tanggapin mo ang bagong bersyon.$nl$, false),

-- =====================================================================
-- informed_consent (consent to monitoring)
-- =====================================================================
('informed_consent', 1, 'en', 'Informed Consent to Monitoring', $nl$DRAFT, pending ethics/legal review.
This is placeholder text for a student prototype. It is not legal advice. It has not been checked by a lawyer, the Data Protection Officer or an ethics board. Items in [square brackets] are not filled in yet.

1. What you are agreeing to
You agree to use NurtureLink to monitor your pregnancy with a belt and wristband (or with readings you type in), and to have your readings and related information stored and shown to you and to your assigned provider.

2. What happens
The devices measure your baby's heart rate, your heart rate, your oxygen level and your temperature. The app saves each reading. It may raise an alert if a reading is outside the limits. Your assigned provider can see your readings and alerts. The limits are preliminary and still need to be confirmed by a medical officer.

3. Possible benefits
It may help you and your provider notice changes sooner and share readings between visits. We cannot promise any benefit.

4. Possible risks and discomforts
Readings and alerts can be wrong or missing. That can cause worry, or a false feeling that all is well. Wearing the devices may be uncomfortable. If it is, take them off and tell your provider. There is also a risk that someone who should not see your personal data could see it. We work to prevent this, but we cannot remove the risk completely.

5. This is not diagnosis or emergency care
NurtureLink is for monitoring and screening, not diagnosis. A Normal status does not mean that everything is fine. If you feel unwell or worried about yourself or your baby, contact your midwife, doctor or health facility, or call your local emergency number (911 in the Philippines) right away.

6. Your choice
Taking part is voluntary. You can withdraw at any time in Profile > Privacy. If you withdraw, monitoring and data sharing stop until you agree again. Your usual care at your health facility does not depend on using NurtureLink.

7. Video or chat consults
Video and chat consults with a provider are not part of this consent. You will be asked for a separate consent before you use them.

8. Questions
Contact [DPO NAME AND EMAIL].$nl$, false),

('informed_consent', 1, 'fil', 'Pahintulot na May Kaalaman sa Pagsubaybay', $nl$DRAFT, pending ethics/legal review.
(Draft pa lamang. Naghihintay ng pagsusuri ng ethics at legal.)
Ito ay pansamantalang teksto para sa isang prototype ng mga mag-aaral. Hindi ito legal advice. Hindi pa ito nasusuri ng abogado, ng Data Protection Officer, o ng ethics board. Ang mga nasa [square brackets] ay hindi pa napupunan.

1. Ano ang sinasang-ayunan mo
Pumapayag kang gamitin ang NurtureLink para subaybayan ang iyong pagbubuntis gamit ang belt at wristband (o gamit ang mga reading na ikaw mismo ang naglalagay), at pumapayag kang itago ang iyong mga reading at kaugnay na impormasyon at ipakita ang mga ito sa iyo at sa nakatalaga mong provider.

2. Ano ang nangyayari
Sinusukat ng mga device ang heart rate ng iyong sanggol, ang iyong heart rate, antas ng oxygen at temperatura. Sine-save ng app ang bawat reading. Maaari itong magpadala ng abiso kung ang reading ay labas sa itinakdang saklaw. Makikita ng nakatalaga mong provider ang iyong mga reading at abiso. Pansamantala pa lamang ang mga saklaw at kailangan pa itong kumpirmahin ng isang medical officer.

3. Posibleng pakinabang
Maaari itong makatulong sa iyo at sa iyong provider na mas maagang mapansin ang mga pagbabago at magbahagi ng mga reading sa pagitan ng mga pagbisita. Wala kaming ipinapangakong pakinabang.

4. Posibleng panganib at hirap
Maaaring mali o wala ang mga reading at abiso. Maaari itong magdulot ng pag-aalala, o ng maling pakiramdam na maayos ang lahat. Maaaring hindi komportable ang pagsuot ng mga device. Kung ganoon, hubarin ang mga ito at sabihin sa iyong provider. May panganib din na makita ng taong hindi dapat makakita ang iyong personal na datos. Sinisikap naming iwasan ito, ngunit hindi namin ito ganap na maaalis.

5. Hindi ito diyagnosis o emergency care
Ang NurtureLink ay para sa pagsubaybay at screening, hindi para sa diyagnosis. Ang status na Maayos ay hindi nangangahulugang maayos ang lahat. Kung masama ang pakiramdam mo o nag-aalala ka para sa iyong sarili o sa iyong sanggol, makipag-ugnayan agad sa iyong midwife, doktor o pasilidad pangkalusugan, o tumawag sa lokal na emergency number (911 sa Pilipinas).

6. Ang iyong pagpapasya
Boluntaryo ang pagsali. Maaari kang umatras anumang oras sa Profile > Privacy. Kung aatras ka, titigil ang pagsubaybay at pagbabahagi ng datos hanggang pumayag kang muli. Hindi nakasalalay sa paggamit ng NurtureLink ang karaniwan mong pangangalaga sa iyong pasilidad pangkalusugan.

7. Video o chat na konsulta
Hindi kasama sa pahintulot na ito ang video at chat na konsulta sa provider. Hihingan ka ng hiwalay na pahintulot bago mo ito gamitin.

8. Mga tanong
Makipag-ugnayan sa [DPO NAME AND EMAIL].$nl$, false),

-- =====================================================================
-- medical_disclaimer
-- =====================================================================
('medical_disclaimer', 1, 'en', 'Medical Disclaimer', $nl$DRAFT, pending ethics/legal review.
This is placeholder text for a student prototype. It is not legal advice. It has not been checked by a lawyer, the Data Protection Officer, a medical officer or an ethics board. Items in [square brackets] are not filled in yet.

1. Monitoring and screening, not diagnosis
NurtureLink is a prototype for monitoring and screening. It does not diagnose any condition and does not tell you what treatment you need.

2. It does not replace care
NurtureLink does not replace your check-ups, your midwife or doctor, or emergency care. Keep your usual appointments.

3. Readings can be wrong
Readings can be wrong or missing, for example when the belt is in the wrong place, the signal is weak, the battery is low, or there is no internet. A Normal status does not mean that everything is fine, and a missing alert does not mean that nothing is wrong.

4. Alert limits are preliminary
The limits that trigger alerts are default values. They are still to be confirmed by a medical officer and may change.

5. If you are worried
If you feel unwell or worried about yourself or your baby, for any reason, contact your midwife, doctor or health facility, or call your local emergency number (911 in the Philippines) right away. Do not wait for the app.$nl$, false),

('medical_disclaimer', 1, 'fil', 'Paalala Medikal', $nl$DRAFT, pending ethics/legal review.
(Draft pa lamang. Naghihintay ng pagsusuri ng ethics at legal.)
Ito ay pansamantalang teksto para sa isang prototype ng mga mag-aaral. Hindi ito legal advice. Hindi pa ito nasusuri ng abogado, ng Data Protection Officer, ng medical officer, o ng ethics board. Ang mga nasa [square brackets] ay hindi pa napupunan.

1. Pagsubaybay at screening, hindi diyagnosis
Ang NurtureLink ay isang prototype para sa pagsubaybay at screening. Hindi ito nagdidiyagnos ng anumang kondisyon at hindi nito sinasabi kung anong gamutan ang kailangan mo.

2. Hindi nito pinapalitan ang pangangalaga
Hindi napapalitan ng NurtureLink ang iyong mga check-up, ang iyong midwife o doktor, o ang emergency care. Ituloy ang mga karaniwan mong appointment.

3. Maaaring mali ang mga reading
Maaaring mali o wala ang mga reading, halimbawa kapag mali ang pwesto ng belt, mahina ang signal, mahina ang baterya, o walang internet. Ang status na Maayos ay hindi nangangahulugang maayos ang lahat, at ang kawalan ng abiso ay hindi nangangahulugang walang problema.

4. Pansamantala pa ang mga saklaw ng abiso
Ang mga saklaw na nagpapadala ng abiso ay mga default na halaga. Kailangan pa itong kumpirmahin ng isang medical officer at maaari itong magbago.

5. Kung nag-aalala ka
Kung masama ang pakiramdam mo o nag-aalala ka para sa iyong sarili o sa iyong sanggol, sa anumang dahilan, makipag-ugnayan agad sa iyong midwife, doktor o pasilidad pangkalusugan, o tumawag sa lokal na emergency number (911 sa Pilipinas). Huwag nang hintayin ang app.$nl$, false),

-- =====================================================================
-- guardian_assent (users under 18)
-- =====================================================================
('guardian_assent', 1, 'en', 'Parent or Guardian Assent (under 18)', $nl$DRAFT, pending ethics/legal review.
This is placeholder text for a student prototype. It is not legal advice. It has not been checked by a lawyer, the Data Protection Officer or an ethics board. Items in [square brackets] are not filled in yet.

This item is for users under 18. Please read it together with a parent or guardian.

By ticking the box, we confirm that:
- The user is under 18, and a parent or guardian is with them or has read this and agrees.
- The parent or guardian has read the Privacy Notice and the Informed Consent to Monitoring, and agrees that the user may use NurtureLink and that the user's health information may be collected and used as those documents describe.
- We understand that taking part is voluntary, and that the user or the parent or guardian can withdraw at any time in Profile > Privacy.
- We know that NurtureLink is for monitoring and screening, and does not replace medical care or emergency services.

For this prototype, the app does not check who the parent or guardian is, and it does not collect their name or contact details. [REVIEWING LAWYER OR OFFICE] will decide whether a signature or other proof is needed before real use.$nl$, false),

('guardian_assent', 1, 'fil', 'Pagsang-ayon ng Magulang o Tagapag-alaga (wala pang 18)', $nl$DRAFT, pending ethics/legal review.
(Draft pa lamang. Naghihintay ng pagsusuri ng ethics at legal.)
Ito ay pansamantalang teksto para sa isang prototype ng mga mag-aaral. Hindi ito legal advice. Hindi pa ito nasusuri ng abogado, ng Data Protection Officer, o ng ethics board. Ang mga nasa [square brackets] ay hindi pa napupunan.

Ang aytem na ito ay para sa mga user na wala pang 18 taong gulang. Pakibasa ito kasama ang magulang o tagapag-alaga.

Sa pagtsek sa kahon, kinukumpirma namin na:
- Wala pang 18 taong gulang ang user, at kasama niya ang magulang o tagapag-alaga, o nabasa na nito ito at sumasang-ayon.
- Nabasa ng magulang o tagapag-alaga ang Paunawa sa Privacy at ang Pahintulot na May Kaalaman sa Pagsubaybay, at sumasang-ayon siya na gamitin ng user ang NurtureLink at na kolektahin at gamitin ang impormasyon tungkol sa kalusugan ng user ayon sa inilalarawan ng mga dokumentong iyon.
- Nauunawaan namin na boluntaryo ang pagsali, at na maaaring umatras ang user o ang magulang o tagapag-alaga anumang oras sa Profile > Privacy.
- Alam naming ang NurtureLink ay para sa pagsubaybay at screening, at hindi nito pinapalitan ang medikal na pangangalaga o ang mga serbisyong pang-emergency.

Para sa prototype na ito, hindi sinusuri ng app kung sino ang magulang o tagapag-alaga, at hindi nito kinokolekta ang kaniyang pangalan o contact details. Ang [REVIEWING LAWYER OR OFFICE] ang magpapasya kung kailangan ng lagda o ibang patunay bago magamit ng totoong user.$nl$, false),

-- =====================================================================
-- study_data_use (OPTIONAL, never required)
-- =====================================================================
('study_data_use', 1, 'en', 'Optional: Use of Anonymized Data for the Study', $nl$DRAFT, pending ethics/legal review.
This is placeholder text for a student prototype. It is not legal advice. It has not been checked by a lawyer, the Data Protection Officer or an ethics board. Items in [square brackets] are not filled in yet.

This item is optional. You can use NurtureLink without ticking it.

1. What this is
The project team is studying how well the belt measures a baby's heart rate. This study is reviewed by [ETHICS BOARD AND PROTOCOL NUMBER]. If you tick this item, you allow us to use your readings for the study after we remove information that shows who you are.

2. What data is used
Readings (your baby's heart rate, your heart rate, oxygen level and temperature), signal quality, and gestational age. We remove your name, email address and exact date of birth before the data is used.

3. Who sees it and what happens to the results
Only the research team sees the anonymized data. Results may be shared in summary form, for example in reports or presentations, without your name. We cannot promise that anonymized data can never be linked back to a person, especially in a small study.

4. Your choice
This is voluntary. Saying no does not affect your use of NurtureLink or your usual care. You can withdraw at any time in Profile > Privacy. After you withdraw, we stop using your data for the study from then on. Data that has already been combined into results may not be possible to take out. [ETHICS BOARD AND PROTOCOL NUMBER] will confirm this wording.

5. Questions
Contact [DPO NAME AND EMAIL].$nl$, false),

('study_data_use', 1, 'fil', 'Opsyonal: Paggamit ng Anonymized na Datos para sa Pag-aaral', $nl$DRAFT, pending ethics/legal review.
(Draft pa lamang. Naghihintay ng pagsusuri ng ethics at legal.)
Ito ay pansamantalang teksto para sa isang prototype ng mga mag-aaral. Hindi ito legal advice. Hindi pa ito nasusuri ng abogado, ng Data Protection Officer, o ng ethics board. Ang mga nasa [square brackets] ay hindi pa napupunan.

Opsyonal ang aytem na ito. Magagamit mo ang NurtureLink kahit hindi mo ito tsekan.

1. Ano ito
Pinag-aaralan ng project team kung gaano kahusay sukatin ng belt ang heart rate ng sanggol. Sinusuri ng [ETHICS BOARD AND PROTOCOL NUMBER] ang pag-aaral na ito. Kung tsekan mo ang aytem na ito, pumapayag kang gamitin namin ang iyong mga reading para sa pag-aaral matapos naming alisin ang impormasyong nagpapakita kung sino ka.

2. Anong datos ang gagamitin
Mga reading (heart rate ng iyong sanggol, iyong heart rate, antas ng oxygen at temperatura), kalidad ng signal, at gestational age. Aalisin namin ang iyong pangalan, email address at eksaktong petsa ng kapanganakan bago gamitin ang datos.

3. Sino ang makakakita at ano ang mangyayari sa resulta
Ang research team lamang ang makakakita ng anonymized na datos. Maaaring ibahagi ang resulta nang buod, halimbawa sa mga ulat o presentasyon, nang walang pangalan mo. Hindi namin maipapangako na hindi na kailanman maiuugnay pabalik sa isang tao ang anonymized na datos, lalo na sa maliit na pag-aaral.

4. Ang iyong pagpapasya
Boluntaryo ito. Ang pagtanggi ay hindi makakaapekto sa paggamit mo ng NurtureLink o sa karaniwan mong pangangalaga. Maaari kang umatras anumang oras sa Profile > Privacy. Pagkatapos mong umatras, ititigil namin ang paggamit ng iyong datos para sa pag-aaral mula noon. Maaaring hindi na maalis ang datos na naisama na sa mga resulta. Kukumpirmahin ng [ETHICS BOARD AND PROTOCOL NUMBER] ang pananalitang ito.

5. Mga tanong
Makipag-ugnayan sa [DPO NAME AND EMAIL].$nl$, false),

-- =====================================================================
-- provider_confidentiality (providers only)
-- =====================================================================
('provider_confidentiality', 1, 'en', 'Provider Confidentiality Agreement', $nl$DRAFT, pending ethics/legal review.
This is placeholder text for a student prototype. It is not legal advice. It has not been checked by a lawyer, the Data Protection Officer or an ethics board. Items in [square brackets] are not filled in yet.

By ticking the box, I agree that:

1. I will open only the records of patients assigned to me, and only for their care, for alerts and consults, or for the approved study.
2. I will keep patient information confidential. I will not share it with anyone who is not allowed to see it, and I will not discuss patients in a way that could identify them in public places or in open chats.
3. I will not copy, screenshot, print or export patient information, except where the project allows it and the copy is kept safe.
4. I will keep my login private, I will not let anyone else use my account, and I will log out on shared devices.
5. I understand that every time I open a patient record, the app writes it to an audit log with my account and the time.
6. If I think patient data was lost, shown to the wrong person, or taken, I will tell [DPO NAME AND EMAIL] right away, so that any required notice (within 72 hours) can be made.
7. I understand that these duties come from the Data Privacy Act of 2012 (RA 10173) and from my professional duty of confidentiality, and that they continue after I stop using NurtureLink.
8. I understand that breaking this agreement may have consequences under the rules of [CONTROLLER NAME] and under the law.

[REVIEWING LAWYER OR OFFICE] will confirm and complete this text before real use.$nl$, false),

('provider_confidentiality', 1, 'fil', 'Kasunduan sa Pagiging Kumpidensyal ng Provider', $nl$DRAFT, pending ethics/legal review.
(Draft pa lamang. Naghihintay ng pagsusuri ng ethics at legal.)
Ito ay pansamantalang teksto para sa isang prototype ng mga mag-aaral. Hindi ito legal advice. Hindi pa ito nasusuri ng abogado, ng Data Protection Officer, o ng ethics board. Ang mga nasa [square brackets] ay hindi pa napupunan.

Sa pagtsek sa kahon, sumasang-ayon ako na:

1. Bubuksan ko lamang ang mga record ng mga pasyenteng nakatalaga sa akin, at para lamang sa kanilang pangangalaga, sa mga abiso at konsulta, o sa aprubadong pag-aaral.
2. Iingatan kong kumpidensyal ang impormasyon ng pasyente. Hindi ko ito ibabahagi sa sinumang hindi pinapayagang makakita nito, at hindi ako makikipag-usap tungkol sa mga pasyente sa paraang makikilala sila sa mga pampublikong lugar o sa mga bukas na chat.
3. Hindi ko kokopyahin, kukunan ng screenshot, ipi-print o ie-export ang impormasyon ng pasyente, maliban kung pinapayagan ito ng proyekto at iniingatan nang maayos ang kopya.
4. Iingatan kong pribado ang aking login, hindi ko ipagagamit sa iba ang aking account, at magla-log out ako sa mga ibinabahaging device.
5. Nauunawaan ko na sa tuwing magbubukas ako ng record ng pasyente, isinusulat ito ng app sa audit log kasama ang aking account at ang oras.
6. Kung sa tingin ko ay nawala ang datos ng pasyente, naipakita sa maling tao, o nakuha ng iba, agad kong sasabihin kay [DPO NAME AND EMAIL], upang magawa ang anumang kinakailangang abiso (sa loob ng 72 oras).
7. Nauunawaan ko na ang mga tungkuling ito ay nagmumula sa Data Privacy Act of 2012 (RA 10173) at sa aking propesyonal na tungkulin na magpanatili ng kumpidensyalidad, at nagpapatuloy ang mga ito kahit tumigil na ako sa paggamit ng NurtureLink.
8. Nauunawaan ko na ang paglabag sa kasunduang ito ay maaaring magkaroon ng mga kahihinatnan sa ilalim ng mga patakaran ng [CONTROLLER NAME] at ng batas.

Ang [REVIEWING LAWYER OR OFFICE] ang magkukumpirma at kukumpleto ng tekstong ito bago magamit ng totoong user.$nl$, false)

on conflict (doc_type, version, language) do update
  set title = excluded.title,
      body  = excluded.body
  where public.consent_documents.is_published = false;   -- never touch a published row

-- Check (expect 14 rows, all version 1, all is_published = false the first time):
select doc_type, version, language, title, is_published, char_length(body) as body_chars
from public.consent_documents
where version = 1
order by doc_type, language;
