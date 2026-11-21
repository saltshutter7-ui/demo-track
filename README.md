# TF-Tracker (Supabase version)

## Tabs
- **Summary**: Workshop wise, Division wise, Pending for issue - age wise, Capacity wise. Default: this month.
- **Data Sheet**: pick a PR date (or "All dates"), see the PRs, type in any cell (saved automatically), **+ Add PR**, **Paste from Excel**, delete a row (x), Excel / Print.
  A user with "View only" access sees the sheet but cannot change it.

## SQL to run once in Supabase > SQL Editor (in this order, only the ones you have not run yet)
1. `supabase-step8-app.sql`   (click lists + password flag)
2. `supabase-step9-add-user.sql`   (add_profile helper)
3. `supabase-step10-save.sql`   (saving data: save_rows, delete_pr)
4. `supabase-step11-admin.sql`   (tab access, workshops written by Admin, Driver Master, edit user)
5. `supabase-step13-dup.sql`   (DUPLICATE/WRONG PR: nothing after the firm can be filled)
6. `supabase-step14-spelling.sql`   (wrong spelling of a workshop is counted as the right one)
7. `supabase-step12-purge.sql`   (every night deletes PRs older than 400 days - cannot be undone)

## Admin panel needs ONE Edge Function (only for create user / reset password / delete user)
Supabase Dashboard > Edge Functions > Deploy a new function > name `admin-users` > paste the whole file `edge/admin-users.ts` > Deploy.
Nothing else: the secret key is added inside Supabase by itself, you never copy it anywhere.
Until it is deployed, everything else in the Admin tab works, but Create user / Reset / Delete show a message.

## Put the site online
Upload every file of the `site` folder to your NEW GitHub repository (replace the old files), Settings > Pages.

## Step 15 - Comparison tab (Admin only) + 2 year 2 month auto-delete
- Run `supabase-step15-compare.sql` once in Supabase > SQL Editor. Parts A and B (Comparison numbers + "Install on 01.04.YYYY" table) are safe.
- Part C (the last block) deletes every PR older than 2 years 2 months, every night. It cannot be undone: first run the `select count(*)` line written in the file.
- Then upload the `site` folder to GitHub and hard-refresh. The Admin sees a new "Comparison" tab. Last year's data must be in the database for the last-year columns to show numbers.

## Step 16 - Last month pendency leaves as soon as the transformer is fitted
- Run `supabase-step16-pendency.sql` once in Supabase > SQL Editor (safe to run again, no data is changed).
- A PR raised before the From date is now in "Last month pendency" only while its REPLACEMENT DATE is empty. Summary number and the list that opens by a click stay equal.

## Step 17 - Dashboard (graph icon in the Summary toolbar)
1. Supabase > SQL Editor: run `supabase-step17-dashboard.sql` once (safe to run again; no data changes). Also run step 15 (Parts A and B) and step 16 if not done yet.
2. Upload the `site` folder to GitHub and hard-refresh (the service worker cache is now tt-sb18).
3. Summary tab: set From / To, then click the graph icon right of Print. One page shows Total PR and, workshop wise, Issued, Pending to Issue, Replacement Pending and TX Return Pending (no combined pending total).
4. Each login sees only its own data (JE: own workshops, Admin: own division, DISCOM: all). Creator has no Summary, so no dashboard.
5. The dashboard follows the PRs raised in the period, so it can differ from Total Issue / Total Replacement of the Summary table (those count work done in the period).

## Step 18 - Phone look (screens up to 700px wide)
No SQL needed. Upload the `site` folder to GitHub and hard-refresh (cache tt-sb20).
- Header: round "TF" mark instead of the emblem picture. Bottom icon bar for Summary / Data Sheet / Drivers / Comparison / Admin.
- Summary: dense centred tables with borders, no sideways scroll; Capacity wise is drawn as two short tables; Division wise stays closed until clicked.
- Graph dashboard fits one phone page. Excel and Print are unchanged (full tables). Desktop look is unchanged.

## Step 19 - Dashboard rings and short Summary headings (no SQL)
- Dashboard: the rings now show Issued % and Replaced % against Total PR (top banner and each workshop card). Return stays in the bars and numbers.
- Phone only: shorter headings in the Workshop / Division tables (Pendency before date, Pending issue, Pending replacement, Iss. vs today PR, Repl. vs today PR, Today replace). Excel and Print keep the full words.
- Upload the `site` folder and hard-refresh (cache tt-sb21).

## Step 20 - Desktop look (screens wider than 900px, no SQL)
Left menu with icons (Summary, Data Sheet, Drivers, Comparison, Admin), round TF mark, six big numbers above the tables, and the Summary tables on one page (Workshop wise, Pending age wise + Division wise (closed until clicked), Capacity wise). Darker text. Excel and Print are unchanged. Upload the `site` folder, hard-refresh (cache tt-sb22).

## Step 21 - Hide / show the left menu (desktop, no SQL)
A small arrow button next to the logo hides the left menu; the same button (top-left) brings it back. The choice is remembered on that computer. Cache tt-sb23.

## Step 22 - Comparison for everybody + Summary print like the screen
1. Supabase > SQL Editor: run `supabase-step22-compare-all.sql` once (safe to run again; no data is changed). It adds two functions that return only COUNTS (no PR details, no mobile numbers).
2. Comparison tab is now visible to Admin, JE and DISCOM. Admin / JE see their whole organisation (division), DISCOM sees all. A **Workshop** filter on top (a JE starts with his own workshop) decides what is shown, printed and exported. Typing the Install numbers stays Admin only.
3. Comparison: taller rows; "BELOW 100 KVA" and "100 AND ABOVE" headings wrap.
4. Summary Print now has the same look as the screen (number strip, coloured tables); page 1 = Workshop wise + Pending age + Capacity, page 2 = Division wise.
Upload the `site` folder and hard-refresh (cache tt-sb24).

## Step 23 - Driver Master: paste from Excel
Copy several cells/rows from Excel, click the first cell (e.g. Firm) in Driver Master and press Ctrl+V. Columns go to the right in the order Workshop, Firm, Driver, Mobile, Vehicle, GPS. The first row fills the clicked row, the other rows are added as NEW drivers (saved drivers are never overwritten). Each row is checked like a typed entry; rows that fail (e.g. mobile not 10 digits) stay on screen with the reason shown. No SQL needed.

## Step 24 - Phone Summary: Division table
On phones the Division table uses short names (EDD-I AZH, EDD-III GHOSI MAU, EDD-I BALLIA), headings "Pend.", "Pend. Issue", "Pend. Repl.", warm-theme colours and normal-size zeros. Excel and Print keep the full words. No SQL needed.

## Step 25 - Comparison: short names, bigger desktop table, phone view, print fit
Division names are short (EDD-I AZH ...) in the table, Excel and Print. Desktop: table fills the width and goes down to the bottom of the screen. Phone: heading above the table, names stay on the left while numbers slide, buttons in one row. Print: the whole table is fitted on one landscape page on any device (phones used to cut the right side). No SQL needed.

## Step 26 - Comparison print: laid out in millimetres
The print table now has fixed column widths in mm, so it fills one landscape A4 page on phones and desktops alike. No SQL needed.

## Step 27 - Summary: Excel look
Summary tables (screen) now have the Excel look: black grid, light-blue headings, plain centred numbers, short headings on phones. On laptops the Summary shrinks automatically (not below 78%) to fit one screen. Print and Excel download are unchanged. No SQL needed.

## Step 28 - Choose Home Screen
New "Home screen" button (left menu on computers, header on phones). Five looks: Warm (standard), Indigo + Rings (dark blue menu, rings panel on the right), Teal + Top menu (menu on top, six big numbers on the left), Excel Clean, Dark. The choice is kept per device (browser storage) and used the next time the app opens. Print and Excel are not changed. No SQL needed.

## Step 29 (sb36)
- Home screen -> "Designs" section: 20 colour looks from your design files (choice saved on that device).
- Data Sheet: blank rows now stay at the bottom of the data.
- Only index.html + sw.js changed. No SQL needed.

## Step 30 / 31 (sb37)
- **SQL (run once, in SQL Editor): `supabase-step30-pending-return.sql`**. New rule: Pending for Return = the PR has an issue date and no return date (wrong / duplicate PR never counted). Changes Summary, the list behind the number, Capacity table, Dashboard.
- Home screen: only Warm, Excel Clean + 5 new animated designs (Cream Editorial, Midnight Glass, Mint Fresh, Orange & Black, One-Page Aurora). Summary is scaled to fit ONE screen (desktop and phone). Print and Excel are unchanged.
- Data Sheet: button "Switch to clean look" (plain Excel-like grid), remembered on the device.

## Step 32 (sb38)
- Animation now in every look (cards slide in, numbers count up, hover lift). Smooth transition when you move from one tab to another. Screen only; Print / Excel unchanged. No SQL.

## Step 33 (sb39)
- Fix: Data Sheet is readable in all colour looks (was white text on white cells); "clean look" toolbar readable on dark looks.
- Fix: One-Page Aurora icon menu now keeps the Home screen / Password / Logout buttons.

## Step 34 (sb40)
- Data Sheet, Drivers, Comparison, Admin are readable in every home screen (desktop and phone). Smoother tab-to-tab transition. No SQL.

## Step 35 (sb41)
- **SQL (run once): `supabase-step31-pr-search.sql`** - switches on the PR / Complaint search of the LOGIN page.
- Login page: type the full PR or complaint number -> card with position (PR raised / Issued / Installed / Returned), "N times damage" (same workshop + place + capacity), JE and driver with Call buttons.
- Safety: exact number only (6-30 characters), max 5 PRs, no remarks. To hide mobile numbers set `show_mob` to false inside the SQL and run it again.

## Step 35 (sb41)
- **SQL (run once): `supabase-step31-pr-search.sql`**. Login page now has "PR / Complaint search" (no login): status card, "N Times Damage" (same workshop + same place + same capacity), JE / driver with a Call button.
- Safety: only an exact PR / complaint number (6-30 characters) is accepted, max 5 PRs shown. To hide mobile numbers set `show_mob boolean := false;` in the SQL and run it again.

## Step 36 (sb42)
- Data Sheet "clean look" on the phone is now a real sheet (one record per line, scroll sideways), data visible.
- Comparison on the phone: the frozen name column no longer lets numbers show through (dark / colour looks).
- Orange & Black: black workshop cells in Drivers fixed; top menu fits on narrower laptop screens. No SQL.

## Step 37 (sb43)
- Summary > Division wise summary: short division names (EDD-I AZH, EDC-I AZH ...) on the computer too (same as Comparison). Print / Excel keep full names. No SQL.

## Step 38 (sb44)
- **SQL (run once): `supabase-step32-pr-find.sql`** (after step 31). Login-page search: type 4+ letters / digits of PR no, complaint no or PLACE OF DAMAGE; the list appears while typing (no mobile numbers in the list); tap one line to get the full card with Call buttons.

## Step 39 (sb45)
- Data Sheet in the colour looks: the striped (locked) cells are readable now. "Place of damage" column is wider. No SQL.

## Step 40 (sb46)
- "Place of damage" column made a little narrower (230 px). No SQL.

## Step 41 (sb47) - EMERGENCY tab + SIREN
- **SQL (run once): `supabase-step33-emergency.sql`** (after step 32). Creates the table `emergency` and the functions emg_json / emg_add / emg_set / emg_del.
- Nodal: make a user in Admin > Users with only "Emergency" ticked. He fills Refer by, Village, Mobile/Complaint no., Other detail and the workshop, then "+ Add emergency".
- JE/AE (and Admin) of that workshop: types a remark and the PR NO. All other columns (PR date, division, substation, feeder, place, capacity, complain no., JE, firm, issue date, driver, replacement date) come from the Data Sheet by themselves.
- Siren at the top of Summary: RED (blinking) until the issue date is filled, GREEN after issue, gone when replaced. The line leaves the Emergency tab 2 days after the replacement date. The siren refreshes every 60 seconds.
- Tested only on local Postgres + stub, not on real Supabase.

## Step 42 (sb48)
- Emergency table: wider, well-spaced columns like the Data Sheet (horizontal scroll), clear yellow input boxes, readable grey cells. Data Sheet: Division column a little wider. No SQL.

## Step 43 (sb49)
- Emergency on phone: white cards, black bold text, clear labels, yellow input boxes, empty fields hidden. No SQL.

## Step 44 (sb50)
- Emergency: desktop has the same clear black/bold look as phone. Phone: the whole list scrolls with the page (no small frozen box), cards reach the bottom. No SQL.

## Step 45 (sb51)
- Phone: Summary shown at full size (no shrink-to-fit), page scrolls. Desktop unchanged. No SQL.

## Step 46 (sb52) - OWN WORKSHOP SETUP (a new workshop on its own free Supabase)
- New file **setup.sql** = steps 1-34 in ONE file for a NEW, EMPTY project (no data inside). Also in the `site` folder so the page can copy it. **Do NOT run it on your existing project.**
- New SQL step 34 `supabase-step34-first-admin.sql` (only for new projects; already inside setup.sql): the first person who logs in on an empty project can become Admin. Works only while there is no profile at all.
- Login page: link "Own workshop? Set up your own free account" -> 7-step guide with "Copy setup SQL" and "Copy function code" buttons, then URL + anon key (saved on that device only, "Go back to the default account" resets it). service_role / secret keys are refused.
- Tested only on local Postgres + stub, NOT on a real Supabase. Try a test project first.

## Step 47 (sb53)
- Setup guide step 6 now has Way 1 (Connect button) and Way 2 (Project Settings > API Keys / Data API), and tells to remove /rest/v1/ from the Project URL (the page also removes it by itself). No SQL.

## Step 48 (sb54)
- Own-workshop projects use logins like **anita@tf.uppcl** (the default project keeps @tf.puvvnl so existing users are not broken). setup.sql and site/admin-users.ts (the copy for new projects) use @tf.uppcl.
- Setup guide: step 5 tells to ask ChatGPT if hard; step 6 uses the dashboard names (Project URL, Publishable key / anon key, NOT the Secret key) and says to delete /rest/v1/ from the URL.

## Step 49 (sb55)
- Setup guide step 5: the ChatGPT hint was removed again (as before). No SQL.

## Step 50 (sb56) - no fixed 2-year limit; delete the oldest data only when storage is 90% full
- **SQL (run once): `supabase-step35-purge-full.sql`** (also inside setup.sql). It switches OFF the old nightly delete of step 12 / 15 part C (the "2 years 2 months" cap), and adds two weekly jobs (needs pg_cron):
  - Sunday 02:00 IST: if the database is at 90% or more of 500 MB, the oldest 10% of the PRs are deleted (never a PR newer than 14 months, never a PR without a PR date). If nothing is old enough, a note goes to `purge_log`.
  - Sunday 03:00 IST: `VACUUM FULL public.data` gives the freed space back (without it the size does not shrink).
- See what happened: `select * from public.purge_log order by id desc limit 10;`
- Tested only on a local Postgres (the delete logic with a small size limit). pg_cron / VACUUM FULL were NOT tested.

## Step 51 (sb57)
- Login page: "Forgot password?" link with the steps (Admin resets it in the Admin tab; if no other Admin, the project owner resets it in Supabase > Authentication > Users). Setup guide step 7 tells to make a second Admin. No SQL.

## Step 52 (sb58) - Admin (project owner) logs in with his REAL e-mail; password reset by mail
- Login box accepts an ID (employees) OR a full e-mail (project owner). "Forgot password?" > type the e-mail > Supabase sends a reset mail > the link opens the site with a "Set a new password" box.
- Works only for the e-mail of a member of the Supabase project team (Supabase's free built-in mail sends only to team members, about 2-4 mails per hour). Employees: their Admin resets in the Admin tab.
- New projects: setup guide step 5 now says to create the first login with your own real e-mail. `supabase-step34-first-admin.sql` (and setup.sql) keep a real e-mail as the login id. Existing users / your current project: unchanged (IDs still work). If you already ran step 34 on a project, run the new step 34 file again (safe).
- In Supabase > Authentication > URL Configuration set **Site URL** to your GitHub Pages address (otherwise the mail link goes to the wrong page).
- Tested only on local stub, NOT with real Supabase mail.

## Step 53 (sb59)
- Setup guide: new OPTIONAL step "reset a forgotten Admin password by e-mail": shows the address of THIS site (for you: https://ewdazamgarh.github.io/TRANSFORMER-TRACKER/) with Copy buttons for Supabase > Authentication > URL Configuration (Site URL, and Redirect URLs with ** at the end). Supabase keeps this setting itself; it cannot be preset by SQL. No SQL.

## Step 54 (sb60)
- Setup guide step 7 (optional reset-mail setting) rewritten as 5 small clicks with Copy buttons. No SQL.

## Step 55 (sb61) - Emergency changes, bigger numbers in all looks, STRUCTURE (Circle / Division)
- **SQL (run in this order, once each):**
  1. `supabase-step36-emergency2.sql` - Emergency: only an Admin (or App Creator) of the workshop can DELETE; a replaced emergency leaves the tab after **1 day**; new "Solved emergencies" From-To list; new Complaint no. column (Nodal has Mobile no. and Complaint no. boxes); PR no. can be letters + digits (saved in capitals).
  2. `supabase-step37-structure.sql` - the Structure table (Workshop > Circle > Division, short names, order). Admin tab > Structure.
  3. `supabase-step38-seed-azamgarh.sql` - ONLY for the original Azamgarh/Mau/Ballia project: puts the old fixed circles/divisions/short names into the Structure so nothing changes. NOT in setup.sql.
  setup.sql now contains steps 1-37 (not 38).
- Admin tab > Structure: circles (name, short name, order), divisions (circle, name as in the PRs, short name, order). Renaming a division renames it in all PRs too. "Fill from my data" brings the divisions found in the PRs. The Comparison tab and the Division wise table of the Summary use this order and these short names. A new project with no structure still shows the divisions found in its PRs.
- All colour looks: Summary numbers are now bigger than the Warm look (the two looks that had to shrink most get a bit more). Phone Summary is full size.
- Tested only on local Postgres + stub, NOT on real Supabase.

## Step 56 (sb62-sb64) - phone fonts, instructions removed, STAFF LINK
- sb62: on phones every look now uses the Warm table font and the same short headings (bigger fonts only on computers).
- sb63: the "How it works" boxes and the note under the Comparative table are removed.
- sb64: **Staff link.** Own-workshop Admin tab > box "Staff link" > "Copy staff link". An employee opens the link once on his phone / computer; that browser is then connected to the workshop project and he only types his ID and password. The link holds only the public Project URL + publishable key (never a secret key; a secret / service_role key or a non-supabase address is refused). The setup guide step 6 now explains the Project URL and the Publishable key in one clear way (A and B), and a new step 9 tells the Admin to send the link. **No SQL.**
- Tested only on local Postgres + stub, NOT on real Supabase.

## Step 57 (sb65)
- Admin tab: when "Create user / Reset / Delete" fails, the app now shows the real answer of the user service (for example "Workshop MAU is not in this division.") and scrolls to it, instead of the wrong "function is missing" text. No SQL.

## Step 58 (sb66) - WORKSHOP CODE
- **SQL (run ONCE, only in the DEFAULT project = the one in config.js):** `supabase-step39-registry.sql`. Not in setup.sql.
- Own-workshop Admin tab > Staff link box > "Get workshop code": the Admin writes a short name and gets a code like `azamgarh-3f9a1c`. It stores only the public Project URL + publishable key in the default project (secret / service_role keys and foreign addresses are refused; the list cannot be read as a table; a code cannot be changed or deleted from the app).
- Login page: "First time on this phone? Enter your workshop code". The employee types the code once; this browser is then connected to the workshop project and he logs in with ID and password.
- If step 39 is not run, the app says so and the staff link still works.
- Tested only on local Postgres + stub, NOT on real Supabase.

## Step 59 (sb67) - Windows app (TF-Tracker.exe)
- Folder `exe/` + `.github/workflows/build-exe.yml` (put both in the root of the GitHub repo). GitHub > Actions > "Build Windows exe" > Run workflow; when green, download the artifact "TF-Tracker-exe" (a portable TF-Tracker.exe: no install, no admin password).
- The app opens the live site in its own window, so site updates come by themselves. The first time it asks for the workshop code (the site's own login-page link). Links to other sites open in the normal browser; Excel downloads ask where to save; with no internet it shows "Try again".
- The exe is NOT signed: Windows SmartScreen shows "Windows protected your PC" once (More info > Run anyway). Office IT may still block it; then use Edge/Chrome > Install.
- Written and syntax-checked only. NOT run here (no Windows, Electron could not be downloaded), so the first build / run is untested.
- Login page link now reads "First time on this phone or computer?".

## Step 60 (sb68) - exe + apk + Download page
- Folders `exe/`, `android/` and `.github/workflows/build-apps.yml` go in the root of the GitHub repo (replaces the older build-exe.yml). GitHub > Actions > "Build apps (exe + apk)" > Run workflow. It builds TF-Tracker.exe (Windows, portable) and TF-Tracker.apk (Android, debug-signed) and publishes both in a new GitHub Release.
- New page `download.html` (link on the login page): Windows .exe, Android .apk and iPhone "Add to Home Screen" steps side by side. Buttons use `.../releases/latest/download/TF-Tracker.exe|apk`, so they work after the first successful build.
- Android app: Excel files open in the phone's Share sheet (save / WhatsApp); Print is not available there (the app says so). Windows app keeps Save as and Print.
- Each new build of the apk is signed with a new debug key, so uninstall the old apk before installing a newer one (the site itself updates without any new apk).
- Written and tested only in a browser with a fake Android bridge. The real exe / apk build was NOT run (no Windows / Android SDK here, packages could not be downloaded), so the first GitHub build may need a small fix; send the red step's screenshot.

## Step 61 (TEST build) - M&R DASHBOARD (Maintenance & Repair)  -- not for the main repo yet
- Separate test site: `tf-mr-test-site.zip` (folder `mr_test/site`). Put it in a TEST repo + a TEST Supabase project. The main site is unchanged.
- SQL for the test project: `supabase-step40-mr.sql` (after the normal setup; `mr_test/site/setup.sql` already holds setup + step 40 in one file). New tables: `dtc`, `kitty_base`, `kitty_day`. Existing tables are not changed.
- Left menu bottom of the main (R&R) dashboard: "M&R Dashboard". Inside: M&R Summary, DTC Sheet, Kitty, and "R&R" at the bottom to come back.
- M&R user = a JE-type user created in Admin with the "M&R" tab ticked (own ID). Admin can also open M&R.
- M&R Summary: From/To date. Cards: Total PR, Total DTC, Pending for DTC. Workshop wise: Today PR / Today DTC, Total PR / Total DTC / Pending for DTC. Capacity wise: PR received, DTC done, Pending for DTC.
- DTC Sheet: one month at a time; Data Sheet columns locked; only DTC NO + DTC DATE typed; filters All / Pending / Done; Excel.
- Kitty (per workshop, per day, capacity 10 ... 630): Opening kitty (= previous day's net), Unrepaired T/F (Admin sets the start figures once; grows with the Data Sheet return date; falls the next day by the repair), Issue (from the Data Sheet issue date), Repair / Issue to other workshop / Receive from other workshop (typed by the M&R user), Net kitty = opening + repair + receive - issue - issue to other.
- Tested only on local Postgres + stub (all M&R tests PASS). NOT on real Supabase.

## Step 62 (TEST build, M&R part 2)
- **SQL:** `supabase-step41-mr2.sql` after step 40 (new tables `kitty_ly`; `mr_list_json` replaced). `mr_test/site/setup.sql` = setup + 40 + 41 for a new test project.
- DTC Sheet: issue date / replacement date removed; return date, ISSUED TO FIRM and DRIVER NAME shown (Excel too).
- Kitty > "Next month need": kitty of the viewed date + last year's repair of the next N days (same date last year) - last year's PR of those days made 2% more (rounded up) = kitty after; NEED = the missing part, capacity wise and total.
- Last year's repair is typed as a month total per capacity while the kitty has no data of that time (a day of the window falls before the kitty start date); the days use their share of the month. Once the kitty itself covers last year's days, the box disappears and the kitty's own daily repair is used.
- "Kitty Compare" tab: net kitty of the date, capacity wise, one column per workshop of the user + total; Excel.
- Tested only on local Postgres + stub (all PASS). NOT on real Supabase.

## Step 63 (TEST build, M&R part 3)
- **SQL:** `supabase-step42-mr3.sql` after step 41 (`kitty_need_json` now returns only the NEED per capacity; all calculation stays in the database). `mr_test/site/setup.sql` = setup + 40 + 41 + 42.
- Kitty Compare is no longer a tab: small button **Compare** on top of the Kitty tab; it opens a table above the kitty table for the date of the Kitty tab (follows the date, Excel, Close).
- "Next month need" shows only CAPACITY and NEED (+ total) and a hint when last year's repair is not filled.
- Last year's repair: small button **LY repair** on top of the Kitty tab opens a box (month, 9 capacities, Save). The button shows only to a user who can edit and only while last year of the viewed date is before the kitty start date; it disappears by itself later.
- Tested only on local Postgres + stub (all PASS). NOT on real Supabase.

## Step 64 (TEST build, M&R part 4)
- **SQL:** `supabase-step43-mr4.sql` after step 42 (new `kitty_need_json` with the PR increase %). `mr_test/site/setup.sql` = setup + 40 to 43.
- "Next month need" shows the full table again: KITTY, + LAST YEAR REPAIR, LAST YEAR PR, PR + x%, KITTY AFTER, NEED, total and the sentence.
- Last year's PR is made x% more (rounded up); x is typed in the box "PR increase %": 0 to 5, default 5 (more than 5 becomes 5).
- Tested only on local Postgres + stub (all PASS). NOT on real Supabase.

## Step 65 (TEST build, M&R part 5 - Repair tab)
- **SQL:** `supabase-step44-repair.sql` after steps 40 to 43 (new table `rr_entry`, functions `rr_json`, `rr_save`). `mr_test/site/setup.sql` = setup + 40 to 44.
- New M&R tab **Repair** (between Kitty and R&R): three blocks REPAIR, ASSEMBLY, OVEN like the Excel sheet. Rows = firm names (typed, + Add firm / x remove), columns = 10, 16, 25, 63, 100, 160, 250(AL), 250(CU), 400, 630, 1000, TOTAL; a TOTAL row under each block.
- Typed by the M&R user per workshop and per date; Save, Excel download. An empty day pre-fills the firm names of the latest earlier day.
- If the app shows "Could not find the function ... in the schema cache", the M&R SQL (steps 40 to 44) has not been run in that project: run the zip's `setup.sql`.
- Tested only on local Postgres + stub. NOT on real Supabase.

## Step 66 (TEST build, M&R part 6 - Chamber Assembly tab)
- **SQL:** `supabase-step45-chamber.sql` after steps 40 to 44. `mr_test/site/setup.sql` = setup + 40 to 45.
- New M&R tab **Chamber Assembly**: one report for a date, laid out like the Excel sheet: Unrepaired DTs, Availability, Assembly, Oven (workshops x 10..1000 + Total) and "Total including Oven & Assembly".
- Availability = Kitty net kitty. Unrepaired = Kitty unrepaired - ASSEMBLY entries of the Repair tab. Assembly = start figure + ASSEMBLY - OVEN entries. Oven = start figure + OVEN entries - the daily Repair of the Kitty tab (a repaired transformer leaves the oven; so the repairs the Kitty deducted from unrepaired are added back). Total including = availability + assembly + oven.
- The Admin types the Assembly / Oven start figures once ("Start figures (Admin)"); later days follow the Repair tab. 250(AL)+250(CU) = 250. The same firm typed twice in a Repair block is added together.
- Tested only on local Postgres + stub. NOT on real Supabase.

## Step 67 (TEST build, M&R part 7 - Excel-like grids)
- **SQL:** `supabase-step46-date.sql` (re-creates kitty_save, kitty_base_set, rr_save, ch_base_set: "today" is accepted also when India is already a day ahead of the database clock) and a changed `supabase-step45-chamber.sql` (entries of the start date itself now count; run step 45 and 46 again - both are `create or replace`). `mr_test/site/setup.sql` = setup + 40 to 46.
- Repair tab: ONE firm list for the REPAIR, ASSEMBLY and OVEN blocks. "+ Add firm" adds it to all three, x removes it from all three, typing the name once fills it in all three.
- Repair, Kitty (and its start-figure / need / compare tables) look like Excel: black grid, plain cells, green active cell. Number spinners are removed everywhere in the app.
- Keys like Excel: arrow keys / Enter move, Shift+arrow or mouse drag select a range, Ctrl+C copies it (tab separated), Ctrl+V pastes from Excel (the Repair tab adds firm rows if the pasted block is longer), Delete clears a selected range. Only digits can be typed in number cells.
- Tested only on local Postgres + stub. NOT on real Supabase.

## Step 68 (TEST build, M&R part 8 - Summary like R&R)
- No new SQL. The M&R Summary now has two cards like the R&R Summary: "Workshop wise summary" and ONE "Capacity wise summary" table (capacity rows; groups PR RECEIVED, DTC DONE, PENDING FOR DTC, each with the workshops and a TOTAL). Same Warm colours as R&R. Excel has two sheets (merged heading cells, like R&R).
- Tested only on local Postgres + stub. NOT on real Supabase.

## Step 69 (TEST build, M&R part 9 - M&R follows the chosen Home screen look)
- No new SQL. The look chosen with "Home screen" (Warm, Excel Clean, the new designs) now also dresses the M&R Summary (cards, tables, KPI boxes, colours); the "Home screen" button is shown in M&R too.
- Phone: the Show Summary / Excel / Print buttons and the date arrows of Kitty / Repair / Chamber no longer squeeze; the Chamber report is smaller so it fits.
- Tested only on local Postgres + stub. NOT on real Supabase.

## Step 70 (TEST build, SIR - Site Inspection Report)
- **SQL:** run the new `site/setup.sql` (it now holds steps 40-47) in the TEST project, or only `supabase-step47-sir.sql` if steps 40-46 are already done. It makes the table `sir_cfg` and the functions `sir_cfg_get`, `sir_cfg_set`, `sir_prs_json`.
- **Admin tab:** a small "SIR" button at the top (Admin only). It opens a panel with instructions, the Google Sheet link box and the column-heading box (default `INDENT NO`). Press **Test** (it tells how many SIR entries it read), then **Save**. **Remove link** unlinks.
- **Google Sheet:** open the sheet where the SIR form saves its answers > File > Share > Publish to web > CSV > Publish, paste that link. (A normal link also works if the sheet is shared "Anyone with the link - Viewer".) Only the INDENT NO column is read; the heading may be in any of the first 15 rows and is matched ignoring capital letters, dots and spaces.
- **Rule:** PR number (100 KVA & above) found in that column = SIR done, not found = SIR pending. Wrong / duplicate PRs are not counted.
- **Summary screen:** a new "SIR Summary" card under the capacity table: capacity-wise (100 and above) PR RAISED / SIR DONE / SIR PENDING, workshop-wise with TOTAL. Choose a **Pending till** date and press Show (PRs from the Summary From date to that date are counted). Refresh reads the sheet again. It goes into Excel and Print with the other cards.
- Tested only on local Postgres + a local copy of a CSV. NOT on real Supabase and NOT with a real Google Sheet link.

## Step 71 (TEST build, division names with extra spaces + Pending SIR list)
- **SQL:** run the new `site/setup.sql` (steps 40-48), or only `supabase-step48-sir-list-division.sql` after step 47.
- **Division name with 2 spaces:** a name like `EWD  AZAMGARH` (two spaces inside, or spaces at the ends) is now the SAME division as `EWD AZAMGARH`. The database cleans the names in Workshops, Users, the Structure (circle/division) and the Data Sheet on every save, and the step 48 SQL also cleans what is already stored. The app also cleans the name typed in Create user / Add workshop / Structure.
- **Pending SIR:** every number in the SIR PENDING group (capacity rows, workshop totals, TOTAL row and the number in the line above the table) is a link; it opens the list of those PRs (same list as the other Summary numbers, with Excel / Print / search).
- Tested only on local Postgres + stub + a local CSV. NOT on real Supabase.

## Step 72 (TEST build, SIR count check)
- No new SQL.
- The SIR Summary has its own **PR from** and **Pending till** dates (the PR-from date starts as the Summary From date, which is usually the 1st of the month - that is why a month-wise Summary shows fewer SIR than the whole sheet). Set PR from to an older date (e.g. 01.04.2025) to count all the PRs.
- Under the table a small "How the sheet matched (check)" box shows: rows read from the sheet, different PR numbers, rows with the column empty, how many numbers were found among the 100 KVA & above PRs (inside the dates / on other dates) and how many were not found at all (with examples).
- Tested only on local Postgres + stub + a local CSV. NOT on real Supabase / a real Google Sheet.

## Step 73 (TEST build, SIR number reading)
- No new SQL. The INDENT NO cell is now read more loosely: `8101654095`, `8,101,654,095`, `PR-8101654095`, `8101654095.0`, leading zeros, or two numbers in one cell all give the PR number.
- Tested only locally (local Postgres + stub + local CSV).

## Step 74 (TEST build, SIR column in the Data Sheet)
- No new SQL. When the SIR Google Sheet is linked (Admin > SIR), the Data Sheet gets a read-only **SIR** column just before REMARK: **DONE** (green) if the PR number is in the sheet, **PENDING** (orange) if not. Only for 100 KVA & above; smaller capacities and wrong/duplicate PRs stay blank. The column is in the search box, copy and the Excel download. It is not saved to the database. If no sheet is linked (or it cannot be read) the column is not shown.
- Tested only locally (local Postgres + stub + local CSV).

## Step 75 (TEST build: Kitty repair from the Repair tab, Chamber report in the Repair tab, Scrap tab)
- **SQL:** run `site/setup.sql` (steps 40-49) or only `supabase-step49-kitty-scrap.sql` after step 48. Run it again after the older steps 45/46 if you have not.
- **Kitty REPAIR column:** now read-only. It is the REPAIR block of the Repair tab (all firms added), every day, per capacity (250 AL + 250 CU = 250). In Kitty the JE types only "issue to other workshop" and "receive from other workshop". Days already typed in the Repair tab are copied to the Kitty when the SQL runs. (Old hand-typed kitty repair of days that have no Repair-tab entry is kept.)
- **Repair tab:** the Chamber Assembly report (same as the Chamber Assembly tab, for the Repair tab's date) is shown under the title bar, above the REPAIR / ASSEMBLY / OVEN tables. It refreshes after Save.
- **Scrap tab (new):**
  - Scrap Summary (as in your sheet): NAME OF WORKSHOP, OPENING SCRAP, SCRAP RECEIVE, ISSUE FOR RECONDITIONING, SCRAP AUCTIONED, REMAINING SCRAP (kg). The JE types issue and auctioned and presses Save.
  - SCRAP RECEIVE = repaired T/F of the Repair tab (10, 16, 25, 63, 100, 160, 250 AL only) x standard qty x 97% (from your STD sheet: 11, 20, 25, 50, 69, 90, 115 kg).
  - Remaining of a day = opening of the next day. The Admin types the opening scrap once on a start date ("Opening scrap / standard (Admin)"); the same panel changes the standard qty and the recovery % (one standard for all workshops).
  - Capacity-wise table below shows repaired x standard x recovery for the chosen workshop. Excel download included. Issue + auctioned more than the available scrap is refused.
- Tested only on local Postgres + stub. NOT on real Supabase.

## Step 76 (TEST build: Chamber Assembly Report icon in the Repair tab)
- No new SQL. In the Repair tab's title bar (between the "Repair" title and the Workshop / Date boxes) there is a small button **"Chamber Assembly Report"**. Click it and the same full report as the Chamber Assembly tab opens in a pop-up for the Repair tab's date (all workshops; close with Close / Esc / click outside). The big report under the title bar from Step 75 is removed.
- Tested only locally.

## Step 77 (TEST build: no Chamber Assembly tab; Start figures inside the Chamber Assembly Report pop-up)
- No new SQL. The **Chamber Assembly tab is removed** from the M&R menu (the report was already in the Repair tab). The "Chamber Assembly Report" pop-up of the Repair tab now has: **Excel**, **Start figures (Admin)** (only the Admin sees it; type the ASSEMBLY / OVEN figures of a start date once per workshop, the report reloads after Save) and Close.
- Tested only locally (local Postgres + stub).

## Step 78 (TEST build: Scrap capacity table removed, Chamber report Print / Copy / Excel, new Repair look, M&R animation)
- No new SQL. Upload the new `site/` files (service worker is now `tt-mr19`, so phones reload).
- **Scrap tab:** the "Capacity-wise scrap receive" table is removed. (The Admin panel "Opening scrap / standard" still has the standard qty; the Workshop box on top is only used for that panel.)
- **Chamber Assembly Report pop-up:** new buttons **Print**, **Copy**, **Excel**.
  - Print: A4 portrait, the whole report is shrunk to ONE page (green totals and yellow last row keep their colours).
  - Copy: selects the whole table and copies it; paste in Excel with Ctrl+V. You can also drag-select any part with the mouse and press Ctrl+C.
  - Excel: the file now looks like the screen (borders, merged headings, green Total cells, yellow last row, red minus numbers, date at right).
- **Repair tab:** each of REPAIR / ASSEMBLY / OVEN is its own colour card (green / blue / orange) with a heading, soft row stripes, yellow highlight on the cell you type in, round delete button, and three big live total boxes on top (they count up while you type). Grid behaviour (paste from Excel, arrow keys, Enter) is unchanged.
- **M&R animation:** screens fade in, cards rise one after another, table rows slide in, pop-up opens with a soft zoom, buttons lift on hover and press down on click, side menu icons pulse, titles have a slow colour sweep. Everything stops if the phone has "reduce motion" switched on.
- Tested only locally (headless Chrome + a stub of Supabase, print preview checked as PDF = 1 page). NOT on real Supabase.

## Step 79 (TEST build: Chamber report - no Copy button, Excel-like cell selection, print margins)
- No new SQL. Service worker is now `tt-mr20`.
- Chamber Assembly Report pop-up: the **Copy** button is removed. Cells are selected like in Excel: drag with the mouse, click, Shift+click to extend, Ctrl+A for all; selected cells turn blue. Press Ctrl+C and paste in Excel (merged headings paste as one value + blanks).
- Print: A4 portrait page now has clear left and right margins (16 mm + 4 mm inside), still ONE page.
- Tested only locally (headless Chrome + Supabase stub). NOT on real Supabase.

## Step 80 (TEST build: DTC in Data Sheet, Kitty/Repair "All workshops", Kitty 1000 KVA, Scrap period summary, delete confirm)
- **Run the new end of `site/setup.sql` (STEP 80) in Supabase.** It adds `dtc_map_json`, `scrap_range_json` and adds 1000 KVA to all kitty functions. Safe to run again. Service worker is `tt-mr21`.
- **Repair:** pressing the red x on a firm now asks "Remove the firm ...?" first. Admin gets "All workshops" (view only, firm-wise sum).
- **Kitty:** Admin gets "All workshops" (view only). 1000 KVA row added. UNREPAIRED T/F is now the same figure as the Chamber Assembly report. (Admin start figures still keep their own typed unrepaired number.)
- **DTC Sheet** is removed from the M&R menu. In the **Data Sheet** two columns **DTC NO** and **DTC DATE** now sit before SIR (only for users with M&R access; editable for those who may edit that workshop; saved by itself when the cell is left). The DTC summary stays in M&R Summary.
- **Scrap:** new card "Scrap summary - from date to date": scrap received, issue for reconditioning, scrap auctioned for the period (all workshops or one), then a date-wise list of the days on which scrap was issued or auctioned. Excel button included.
- Tested locally only (headless Chrome + Supabase stub).

## Step 81 (TEST build: autosave, no UNREPAIRED column in Kitty, Kitty vs last year)
- **Run the new end of `site/setup.sql` (STEP 81).** It adds table `kitty_lyk`, `kitty_lyk_json`, `kitty_lyk_set`. Safe to run again. Service worker `tt-mr22`.
- **Autosave** (about 1 second after the last key, message "Saved" in green): Kitty (issue to / receive from other workshop), Repair (all three blocks; deleting a firm after the confirm saves at once), Scrap (issue for reconditioning, auction), LY repair, LY kitty. Data Sheet and its DTC columns already autosaved. The old Save buttons stay as "save now". Start figures (Admin) and the Chamber start figures still use their Save button on purpose (they are set once and carry a date).
- **Kitty tab:** the UNREPAIRED T/F column is removed (it is only in the Chamber Assembly report; the Admin start figure for it is still kept because the Chamber report counts from it).
- **Kitty vs last year:** new card in the Kitty tab, button **Compare**. Shows workshop-wise this year / last year / change (with % and up/down arrow) and capacity-wise for the chosen workshop (or all). Last year's kitty of the same date is taken from the app if the kitty was already running then; otherwise it is typed once in the LAST YEAR column (saved by itself, per workshop and date). Excel button included.
- Tested locally only (headless Chrome + Supabase stub).

## Step 82 (TEST build: blue circle rows in Division wise summary, bigger Home screen)
- No new SQL. Service worker `tt-mr23`.
- **Division wise summary** (Summary tab, also in Print): the circle rows (the EDC rows that add up the divisions above them, for example "EDC-Ballia") are now light blue with blue bold text, the same as in the Comparison tab. The zone / total row stays yellow. (Comparison already had blue circle rows.)
- **Home screen (login + PR search):** on big screens the whole screen is enlarged by itself (up to 1.9x, fitted to the window height; phones and small screens keep the normal size). Re-fitted when the window is resized.
- Tested locally only.

## Step 83 (TEST build: Comparison - day-wise PR & Repair)
- **Run the new end of `site/setup.sql` (STEP 83)** in Supabase (`daywise_json`). Safe to run again. Service worker `tt-mr24`.
- Comparison tab: new button with a calendar icon, **Day-wise PR & Repair**, next to Show Comparison / Excel / Print. It uses the From and To dates and the workshop filter of the tab.
- It opens a pop-up with two tables side by side: **PR** (Data Sheet, by PR date, duplicates not counted) and **REPAIR** (the REPAIR block typed by the users in the Repair tab). In each: left block = the same dates of last year (date, every workshop, TOTAL), right block = the selected dates (date, every workshop, TOTAL, DIFF. = this year - last year), a yellow TOTAL row at the end. Excel button gives the same layout (yellow headings, merged, both tables side by side).
- Note: last year's REPAIR shows only what was typed in the Repair tab then (zeros if the tab was not used last year).
- Tested locally only (headless Chrome + Supabase stub).

## Step 84 (Summary keeps full size)
- The "whole Summary on one screen" shrink (down to 62%) is switched off on desktop: the Summary now always shows at 100% and the page scrolls down. (`hsFit` floor is 1.) Service worker `tt-mr25`. No SQL.

## Step 85-86 (TEST build: pending DTC pop-up, Data Sheet fills the screen, Repair on one screen, Repair summary)
- **Run the new end of `site/setup.sql` (STEP 85 and STEP 86)**: `mr_pending_json`, `rr_summary_json`. Safe to run again. Service worker `tt-mr26`.
- **M&R Summary:** every "Pending for DTC" figure (workshop table, capacity table incl. totals, and the top box) is underlined and clickable. It opens a pop-up with those PRs (same columns as the old DTC sheet); only DTC NO and DTC DATE are typed at the end of the row, then **Save DTC**. After saving the list and the summary reload. (First 500 PRs are shown at a time.)
- **Data Sheet:** the grid now grows down to the bottom of the window (no empty space under it).
- **Repair tab:** the rows shrink by themselves so that 5-6 firms of REPAIR / ASSEMBLY / OVEN and the Save bar are on one desktop screen (floor 20 px per row; very small screens scroll). The three top numbers are one compact line.
- **Repair summary:** new button next to "Chamber Assembly Report". From date, To date, workshop (or all), and Repaired / Sent to assembly / Sent to oven. Shows firm x capacity table with totals (and workshop x capacity when all workshops). Excel button.
- Tested locally only (headless Chrome + Supabase stub; the SQL is parsed with a real Postgres parser but not run).

## Step 87
- Repair summary shows only REPAIR (transformers repaired). The "Show: Sent to assembly / Sent to oven" choice is removed. Service worker `tt-mr27`. No SQL.

## Step 88 (TEST build: Kitty vs last year as an Excel-like sheet, paste, 5-day fallback)
- **Run the new end of `site/setup.sql` (STEP 88)** (`kitty_lyk_json` replaced). Safe to run again. Service worker `tt-mr28`.
- The old "Kitty compared with last year" card (workshop total table) is removed. The Compare button now shows ONE sheet like the Excel one: capacity rows (10 to 1000 KVA), for every workshop "last year | this year", then LAST YEAR TOTAL, THIS YEAR TOTAL, DIFF, and a TOTAL row. Header: division name and DATE. Excel button gives the same sheet.
- **Last year's kitty is typed or pasted for all workshops together:** copy the block from Excel (rows = capacity, columns = workshops, e.g. Azamgarh | Mau | Ballia) and paste into the first "last year" cell; it fills only the last-year columns and saves each workshop by itself (typed figures belong to the same date last year).
- **Same date missing:** the nearest typed date within 5 days before or after is used (shown in a note under the sheet). Where this app has itself counted the kitty on that date last year, its own daily kitty is used automatically (so typed last-year figures are needed only until the app has its own data for that date; the same rule is used by LY repair).
- Tested locally only.

## Step 89 (TEST build: Kitty vs last year - paste table + comparison sheet in the Excel look, all English)
- No new SQL (STEP 88 is enough). Service worker `tt-mr29`.
- Kitty tab, **Compare** button, now shows two tables in the Excel look (white, black lines, serif numbers):
  1. **LAST YEAR KITTY ON dd.mm.yyyy** - capacity rows (10 to 1000 KVA, no 800), one AVAILABILITY column per workshop and a TOTAL column; typed or **pasted for all workshops together** (it saves by itself). Paste works as: a plain block (rows = capacity, columns = workshops, starting at the first cell), an 11-row block (the 800 KVA row in the middle is skipped), or a block copied with the "10 KVA" labels (matched by capacity; SL and total columns are ignored).
  2. **ELECTRICITY WORKSHOP DIVISION, ... / DATE-dd.mm.yyyy** - capacity rows, for every workshop "last year | this year", LAST YEAR TOTAL, THIS YEAR TOTAL, DIFF and a TOTAL row. The Excel button gives this sheet.
- The Hindi labels and the Hindi/English button that were in this card are removed; everything is English.
- Same date last year missing -> the nearest typed date within 5 days (note under the sheet).
- Tested locally only.

## Step 90 (TEST build: LY paste table folded, Print buttons in Kitty, Excel keeps the screen look)
- No SQL. Service worker `tt-mr30`.
- **Kitty vs last year:** the "LAST YEAR KITTY ON ..." paste table is folded (closed) and opens when its title bar is clicked (it remembers open/closed). The comparison sheet is shown directly.
- **Print buttons** next to every Excel button of the Kitty area: the Kitty table, the Kitty vs last year sheet, and Kitty compare. They print the same look as on the screen on **A4, fitted to one page; portrait for a narrow table, landscape for a wide one** (Kitty table and Kitty vs last year sheet print landscape, Kitty compare prints portrait).
- **Excel downloads of the Kitty table and Kitty compare** now keep the screen look (black lines, centred, bold header and TOTAL row, negatives in red) instead of the blue default header. Kitty vs last year, the Chamber report and the Repair summary already did.
- Tested locally only (print checked as PDF: 1 page each).

## Step 91 (TEST build: Kitty table in the M&R Summary, Kitty compare removed from the Kitty tab)
- No SQL (uses the existing `kitty_cmp_json`). Service worker `tt-mr31`.
- **M&R Summary:** new card **Kitty - net kitty on <Date of the summary>** right under "Workshop wise summary": rows = workshops, columns = 10 16 25 63 100 160 250 400 630 1000 and TOTAL, a TOTAL row at the bottom (minus numbers in red, "-" where a kitty is not started). **Print** (A4 landscape, one page) and **Excel** (same look) buttons on the card.
- **Kitty tab:** the "Compare" button and its pop-up (capacity rows x workshop columns) are removed.
- Tested locally only.

## Step 92 (TEST build: Testing Register, STD, OTP delete, one-page M&R Summary, nicer Kitty)
- **Run the new end of `site/setup.sql` (STEP 92)** in Supabase (file `STEP83-92-only.sql` has steps 83 to 92). Service worker `tt-mr32`.
- **Testing Register** (new M&R tab, built from `PuVVNL_Test_Report_Summary (1066).xlsx`): columns S.No, WORKSHOP, FIRM (a list = the firms typed in the Repair tab of that workshop), CAPACITY, JOB NO / UNIQUE NO (one job no only once per workshop), TESTING DATE, TURN RATIO R/Y/B, MEGGER HV/E LV/E HV/LV, DVDF, HIGH VOLTAGE, NO LOAD LOSSES, FULL LOAD LOSS = typed by the user (up to P). IS LOSSES (from the STD), % LOSSES = round(full load loss x 100 / STD load loss) and the 10 slabs (up to 100, 100-115, 115-120, ... above 150) are calculated by themselves; REMARK is free. A TOTAL row at the bottom counts every slab.
  - Turn ratio left empty -> saved as `43.5-44.5` (shown grey, written as a hint in the empty box). Megger left empty -> `2000-5000M-ohm` (hint `2000-5000`). It is the RANGE text, not a made-up number. Anything typed over it is kept.
  - Typing is saved by itself (job no, capacity and workshop are needed). Paste a block from Excel into the grid (columns from NAME OF WORKSHOP to FULL LOAD LOSS; a copied S.No column is skipped).
  - **STD button** (shield icon) at the top: the IS LOSSES table (capacity, no load, load loss). Admin can change it; the register recalculates.
  - **Report** button: From - To (testing date) and workshop -> counts by % loss slab, workshop wise and capacity wise, TOTAL row at the end. Print (A4, one page) and Excel.
  - Excel of the register has the same two-row heading and 16 merges as the original sheet.
- **Delete needs an OTP (Admin):** deleting a PR in the Data Sheet (single or selected) and deleting a Testing Register row first asks to download the data, then "Send OTP". The Admin sees the 6 digit code in a red box at the top right of his screen (valid 10 minutes), tells it, the person types it. One OTP covers 10 minutes of deleting. The old direct delete function `delete_pr` is switched off. NOTE: the OTP is shown inside the app to the Admin, it is not sent by e-mail or SMS (that needs an Edge Function + SMTP).
- **Storage:** the weekly job of step 35 (`purge_if_full`) already deletes the oldest PRs of the Data Sheet when the database is 90% full. New: the Admin gets a yellow warning from 80% (reads `db_usage_json`) telling him to download the old data first.
- **M&R Summary** now fits on one screen (it shrinks a little if the screen is short, never below 50%).
- **Kitty tab:** four colourful number boxes (Opening, Issue, Repair, Net kitty) on top and a nicer table (blue headings, orange typing columns, green/red net kitty).
- Tested locally only (headless Chrome + Supabase stub; SQL parsed, not run).

## Step 78 - Testing Register changes (TEST build)
1. Supabase > SQL Editor: run `supabase-step50-testing.sql` (or the whole `site/setup.sql`; safe to run again). It removes the "one job no only once" rule and changes `test_save` / `test_list_json`.
2. Upload the `site` folder to GitHub and hard-refresh (service worker cache `tt-mr41`).
3. Testing Register: ONE Turn ratio and ONE Megger column (empty = one random value between 43.5-44.5 / 2000-5000 is filled). The slab columns after % LOSSES are removed from the register and the Excel; they stay in the Report. 10 blank rows at the start.
4. New "Quick entry" button at the top of the Testing Register: fill one test in a form, Submit, it goes to the register.
5. Job no colour: 2 times green, 3 yellow, 4 orange, more than 4 red.
6. `privacy.html` rewritten for the Supabase version.

## Step 79 - Paste from Excel explains why rows are skipped
After a paste with skipped rows the message now also says (workshop name not in your list / invalid PR DATE / empty PR NO). No SQL. Cache tt-mr41.

## Step 80 - Phone layout (TEST build)
Instruction texts removed from the M&R tabs; M&R Summary numbers bigger on phones; Kitty and Testing Register show one card per row on phones. No SQL. Cache tt-mr41.

## Step 81 - Speed (SQL only)
Run `site/setup.sql` once more (safe). In the summary / M&R / testing functions the permission check `my_workshops()` is now evaluated once per query instead of once per row (written as `(select public.my_workshops())`). No data changes.

## Step 82 - Quick entry compact; Kitty compare simplified
Quick entry form: two fields per line. Kitty compare: same look as Kitty, no title/date block, no SL column; the "Last year kitty" entry table is shown only to the Admin. No SQL. Cache tt-mr41.

## Step 83 - Testing Register on phone = same grid as desktop (no cards). Cache tt-mr41.

## Step 84 - FIX of step 81
Step 81 used `any ((select ...))` which Postgres reads as a sub-query ("operator does not exist: text = text[]"). Now `any (coalesce((select public.my_workshops()), '{}'))`. Run `site/setup.sql` again.

## Step 85 - FIX: "." (dot), letters and text did not work in the Testing Register grid
Cause: the Excel-like grid (class `xg`) had a global rule "only digits can be typed", which also hit the Testing Register: `43.5` became `435`, the job no `VW3A003957` became `3003957`, DVDF / REMARK letters were removed. Now the Testing Register is exempt from that rule (also for paste) and has its own filters: NO LOAD / FULL LOAD LOSS take digits and a dot, TURN RATIO takes digits, dot and the minus of a range (43.5-44.5), MEGGER and all other boxes take any text (">5000M-ohm"). A comma typed by a phone keyboard becomes a dot. The other grids (Repair, Kitty ...) still take digits only. No SQL. Cache tt-mr45. Tested with real typing.

## Step 85 - R&R keeps 3 years; M&R Repair + Testing Register archive to Google Drive
- `setup.sql` (also `site/supabase-step51-archive.sql`): `purge_if_full` now deletes (Sunday, storage >= 90%) the OLDEST 12 months of R&R PRs and NEVER a PR newer than 3 years (36 months; a smaller value raises an error). Repair (`rr_entry`) and Testing Register (`test_reg`) are not touched by it.
- New: `arch_cfg_get/set`, `arch_status_json`, `arch_month_json`, `arch_delete` (Admin / creator only), tables `arch_cfg`, `arch_log`, VACUUM FULL cron jobs for rr_entry and test_reg.
- `site/drive-archive.gs`: Google Apps Script web app (one Sheet per financial year `repair&testing register FY-2024-25`, tabs `Repair YYYY-MM` / `Testing YYYY-MM`, duplicate-safe by a key in column A, keeps the 5 newest FY files, moves older ones to `Older than 5 FY`).
- App: Admin tab > "Google Drive archive": saves the oldest month (older than 12 months) to Drive, deletes it from Supabase only after Drive confirmed every row. Enabled only when R&R has no PR older than 3 years.
- Tested only locally (local Postgres, a mocked Apps Script, a mocked browser). NOT tested on a real Supabase or a real Google Drive.

## Step 86 - Comparison keeps old periods after R&R PRs are deleted
- New table `cmp_hist` (workshop, division, capacity, day, count). `purge_if_full` saves the daily counts of the PRs it is about to delete, then deletes them.
- `compare_all` (the Comparison tab) adds these saved counts to the live PRs, so any old period (and its "last year") still compares. A day that has live PRs again is taken from the live data only (no double counting).
- Tested on a local Postgres: the same Comparison result before and after the purge. Not tested on a real Supabase.

## Step 87 - Admin panel as job tiles
- Admin tab: tiles on top (Users, New user, Workshops, Staff link, Structure, SIR sheet, Google Drive). The tapped tile opens its box below; the others are hidden. SIR and Drive tiles show Linked / Not linked, Drive warns at 90% storage.

## Step 88 - M&R Summary shows Repair (SQL step 52, mr_repair_json)
- Workshop table: TODAY REPAIR and TOTAL REPAIR; KPI card Total Repair; Capacity table: REPAIR group. Repair = REPAIR block of the Repair tab (250 AL + 250 CU = 250).
- Google Drive setup guide: new step "authorizeOnce", the link test in a browser tab, clearer error.

## Step 89 - Drive link: hidden form + postMessage instead of fetch (no CORS problem)
- drive-archive.gs answers with a small HTML page that posts the result to the app; the app (arPost) submits a hidden form into an iframe and waits for the message. After updating the .gs: Deploy > Manage deployments > New version.

## Step 90 - Drive link: accept the sandboxed (origin null) answer, allow framing (ALLOWALL)

## Step 91 - drive-archive.gs: the lock is taken after the ping, inside try (errors are returned to the app, not a silent Failed); authorizeOnce also asks for the lock permission

## Step 92 - Admin > Google Drive: first-time guide with Copy and Download buttons for drive-archive.gs, 7 steps and a "if the test fails" list

## Step 93 - Login with only ID + password (directory in the DEFAULT project, SQL step 53)
- SQL (inside setup.sql; also `site/supabase-step53-userdir.sql`): tables `ud_project`, `ud_login`, `ud_cfg`; functions `ud_register`, `ud_find`, `ud_status` (callable without login), `ud_logins_json`, `ud_cfg_get/set`, `ud_admin_list/set`. Run it in the DEFAULT project (config.js) AND in every Admin's project.
- Admin tab > "Login without code": the Admin presses "Publish my IDs" once (the project URL + publishable key + the list of IDs go to the default project; a private token stays in his own project). New / deleted users are published again by themselves.
- Admin tab > "Admin directory" (App Creator, default project): Approve / Block / Remove each Admin. Only approved Admins are used by the login page.
- Login page: the ID is looked up in the directory; found once -> the app connects to that project and logs in; found in 2 approved projects -> login refused; not found -> the old way (the project of this device, then the default project). The workshop code and the staff link still work.
- Creating a user whose ID is already used by another Admin is refused.
- Tested only on a local Postgres + a mocked browser. NOT tested on a real Supabase.

## Step 94 - ONE SQL file
- `setup.sql` is the only SQL file. It contains everything (also the workshop-code registry, only created if it is not there). Every new user / project: run setup.sql once; after an update: run it again (safe). The separate supabase-stepNN files of steps 50-53 were removed.

### Step 95 - New default project
config.js now points to the default (App Creator) project https://ctmbrmymibxdyieqjmvz.supabase.co. Run setup.sql once there; every Admin then presses "Publish my IDs" again and the App Creator approves in Admin > Admin directory. Cache tt-mr57.

### Step 96 - Default project changed again
config.js now points to https://smfjkazjgjxfykbymipp.supabase.co (App Creator: k.mith313). Run setup.sql there, make the creator profile, every Admin presses "Publish my IDs" again. Cache tt-mr58.

### Step 97 - PR / Complaint search (no login) finds the record in EVERY approved Admin
- A device linked to one Admin (staff link / workshop code / earlier login) still searches only his project.
- A fresh app (Play Store / APK / exe) asks the default project `ud_public_list()` (new, in setup.sql: only the publishable key and the DIVISION part of the label of APPROVED Admins, never an e-mail) and searches all of them, 6 at a time, 9 s limit each. The list shows the Admin division; tapping a row opens the card from that Admin project.
- With more than one project the search runs on the Search button / Enter only (no live typing). Run setup.sql again in the DEFAULT project. Cache tt-mr59.

### Step 98 - M&R workshop lists follow the Admin workshops at once
Kitty / Repair / Scrap / Dtc workshop lists were built only at login, so a workshop added afterwards showed "No workshop is given to you." until the next login. New mrFillWs() rebuilds them (keeps the chosen workshop) after every add / rename / delete. Cache tt-mr60.

### Step 99 - M&R summary on a phone
Tables no longer squeezed (workshop names broken into letters, totals touching): on a screen up to 700 px they keep a readable size, the first column stays fixed and the table scrolls sideways; in the capacity table the workshop headings show 3 letters (AZA, MAU, BAL, TOT). Desktop and print unchanged. Cache tt-mr61.

### Step 100 - Short workshop names on a phone
In the M&R summary (workshop wise, Kitty, capacity wise) the workshop name is shown as 3+ letters (AZA, MAU, BAL; longer only if two names would clash) on screens up to 700 px; desktop, Print and Excel keep the full name (the full name stays in the text, the short one is a data-ws attribute shown by CSS). Cache tt-mr62.

### Step 101 - Short workshop names in every table (phone)
On a screen up to 700 px every table cell (td/th) that is only a workshop name shows the short name (AZA, MAU, BAL; longer if two names would clash). A small observer tags the cells after each redraw (display only: the full name stays in the text, so Excel, Print and the desktop view are unchanged). Cells that are links or inputs are left alone. Cache tt-mr63.

### Step 102 - Admin sets the short workshop name
Admin > Workshops has a new column "Short name (phone)" (max 8 characters, saved with Save): the phone screen shows it in every table instead of the long workshop name; empty = automatic short name. Stored in workshops.short_name (new column + RPC ws_set_short in setup.sql: an Admin can only change his own division workshops; the same short name cannot be used twice in a division). An older database without the column keeps working (the app reads it with a fallback). Run setup.sql again in each Admin project. Cache tt-mr64.

### Step 103 - Same font for short and already-short workshop names
A short name (AZA, BAL) was drawn bigger and bolder than a name that needs no shortening (MAU). The size the cell really has is now read before the short name is shown (--wf) and weight / line height are inherited, so every workshop name in every table has the same font on a phone. Cache tt-mr65.

### Step 104 - M&R summary on one phone screen like R&R
The sideways scroll of Step 99 is removed: the M&R summary tables (workshop wise, Kitty, capacity wise) use the same compact phone font as the R&R summary and, with the short workshop names, fit the screen width. The short name typed in Admin > Workshops is saved as soon as the box is left or Enter is pressed (no need to find Save). Cache tt-mr66.

Step 105 - Reports tab (old Comparison): icon menu (PR Comparative, Daywise PR & Repair, Kitty, Chamber Assembly, Same Plinth Damage). Same Plinth Damage uses plinth_json / plinth_save (STEP 104 in setup.sql); Excel in the sample format plus REASON OF DAMAGE.

Step 106 - LY Repair day by day (kitty_lyd, kitty_lyd_json/set; used by kitty_need_json and daywise_json) = STEP 105 in setup.sql. Reports tab: new icons LY Kitty and LY Repair.

Step 107 - 1000 KVA added everywhere (STD_CAPS, LY Repair grid, kitty_need_json in STEP 105).

Step 108 - Kitty tab: All workshops = total + one table per workshop. Reports: Kitty Summary (kitty_range_json, STEP 106 in setup.sql).

Step 109 - Reports: LY Kitty renamed Kitty Comparison (read-only, last year from Kitty tab), styled like the Kitty tab; Kitty Summary styled the same.

Step 110 - LY Repair moved from Reports to the top of the Repair tab (button next to Repair summary).

Step 111 - Keeping time: R&R 3 years (oldest 12 months go in the 4th year), comparison history 10 years, M&R (rr_entry, test_reg) 5 years (STEP 107 in setup.sql, jobs tf-purge-rr / tf-purge-mr). Applied to Supabase project trakck.

112. M&R > Material Management (new tab, 2 icons): Wire & Strip Consumption and Oil Recovery Sheet, month wise. Repairs of the month come from the Repair tab (mat_rep); opening of a month = closing of the previous month; STD (material std per capacity, oil std) editable per workshop; Summary From-To (All workshops for Admin); Excel download. Needs setup.sql STEP 108 in each Admin's own Supabase project. Files: index.html, sw.js, setup.sql.

113. Material Management made Excel-like (grey grid, borderless cells, arrows / Enter / paste work like Excel). New icon "Oil Receive" (register: date, Fresh / Reclaim, from where, qty; Month entry + Summary From-To). Oil Recovery Sheet: Fresh / Reclaim Received come from Oil Receive; a Reclaim receipt issues qty +5% of B&C (dirty) oil; DTC count from the PRs (dtc table, by DTC date); oil recovered = DTC x Dirty std -> B&C Received; 3 oil STD (Fresh, Reclaim, Dirty). setup.sql STEP 109 (mat_recv, mat_dtc, mat_recv_list/save/del, new mat_get). Files: index.html, sw.js, setup.sql.

114. Data sheet auto-save now clears the saved (5-minute) Summary / Comparison copy, so the Summary shows the new figures at once. Files: index.html, sw.js.

115. Material Management: Wire & Strip - STORE BALANCE and Total Balance removed; "As per STD" is now one merged cell per capacity (all wires / strips of the capacity added); 250 KVA counts only Al (Cu not counted, also removed from the STD dialog). New icon "Oil Found Below STD" (PR no -> Vill, Substation, JE, Division, Capacity from the Data Sheet; oil found, reason, remark; Month entry + Summary). Oil Recovery Sheet: for those PRs (DTC done in the month) the oil found replaces the Dirty std. setup.sql STEP 110 (mat_low, mat_pr_lookup, mat_low_list/save/del/adj). Files: index.html, sw.js, setup.sql.

116. Material Management: "Total transformer DTC (NOS)" of the Oil Recovery Sheet = PRs received in the month (PR date, capacity wise, same as Total PR of the M&R Summary); also used for the Oil Found Below STD adjustment. Note / Reason / Remark cells are wide and wrap (grow with the text). The broken icon text of "Oil Found Below STD" fixed. setup.sql STEP 109 / 110 functions mat_dtc and mat_low_adj changed (run setup.sql again). Files: index.html, sw.js, setup.sql.

117. Oil Receive: the B&C (dirty) oil issued for a Reclaim receipt = reclaim qty / 0.95 (reclaim comes 5% less than the dirty oil; 10000 L reclaim = 10526.316 L dirty) instead of qty x 1.05. Changed in Oil Receive, Oil Recovery Sheet and the Summary. Files: index.html, sw.js (setup.sql only a comment, no need to run again).

118. Wrap only where asked: Material Management - only Reason / Remark / Note cells wrap (the other columns stay one line, PR no column wider); Emergency tab - "JE/AE remark" is now a wide, wrapping, auto-growing box. Files: index.html, sw.js.

119. Reports > "Add report" (Admin pastes the https link of a web app; it opens inside the Reports tab in a frame, with "Open in new tab" and Remove; all users of the division see it) - setup.sql STEP 111 (custom_report, rp_org, rp_list, rp_add, rp_del). Drivers: the separate "Drivers" tab is replaced by a "Drivers" icon button at the top of the Data Sheet (with a back button); a user who has Drivers but no Data Sheet still gets the Drivers tab. Files: index.html, sw.js, setup.sql.

120. Reports > added web app: the frame now fills the window height. Repair tab: new PDF button (print window, choose "Save as PDF"), also in the Repair summary. Repair tab "All workshops" (Admin): each block (Repair / Assembly / Oven) shows Workshop wise first, then Firm wise, with a switch "Workshop + Firm wise"; Excel and PDF follow the chosen view. One workshop / other users: unchanged. Files: index.html, sw.js.

121. Comparison table: fixed % column widths (screen + PDF fit one page, header aligned, Install column visible). Repair "All workshops": Workshop wise (REPAIR/ASSEMBLY/OVEN blocks with TOTAL) then Firm wise per workshop; Excel matches. sw.js tt-mr83.

122. Material Management: Oil Receive has O&U Oil and Reclaimed (O&U) Oil (Reclaimed O&U adds to Reclaim oil and issues qty/0.97 of O&U oil; Reclaim still issues qty/0.95 of B&C). "Issue for reclaim" label. "All workshops" now in Monthly entry too (added-up, view only). New Insulating Material sheet (stock, auto Consumed = as per STD, editable, no auto use when stock is short, STD per capacity in STD dialog). setup.sql STEP 112 (mat_recv kinds, mat_ins, mat_get/mat_save/mat_recv_save) must be run. sw.js tt-mr84.

123. Material Management: new "Material Requirement" icon (Wire, Strip, then Insulating in sheet order: LY PR of the same N days from the chosen date + damage % x STD - stock = actual requirement; admin All workshops). Insulating Material in the order of the Daily Stock Excel (gaskets after press board, ROD group...). Input cells fill the whole cell (the .mkt input max-width 110px was making half boxes). setup.sql STEP 113 mat_req_pr. sw.js tt-mr85.
