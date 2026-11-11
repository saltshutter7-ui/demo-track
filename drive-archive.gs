/*
 TF-Tracker : Google Drive archive  (Google Apps Script web app)
 It receives the M&R "Repair" and "Testing Register" rows of ONE old month from the app and saves them in your Google Drive.
 One Google Sheet per financial year, named   repair&testing register FY-2024-25   (FY = 1 April to 31 March).
 Inside the file every month has two tabs:  "Repair 2024-04"  and  "Testing 2024-04".
 The 5 newest financial-year files stay in the folder "TF-Tracker Archive"; older files are MOVED (never deleted) to the sub-folder "Older than 5 FY".
 The same row is never saved twice (every row has a unique key in column A), so sending a month again is safe.
 The app deletes the month from Supabase only after this script has confirmed that EVERY row is in the sheet.

 SETUP (once):  1) script.google.com > New project > delete the sample code > paste this whole file.
                2) Change SECRET below to a code of your own (8 or more letters / digits).  Do not share it.
                3) In the toolbar choose the function  authorizeOnce  and press Run. Click Review permissions > your account > Advanced > Go to ... > Allow.
                4) Deploy > New deployment > type: Web app > Execute as: Me > Who has access: Anyone > Deploy.  Allow the access it asks for.
                5) Copy the "Web app" link (ends with /exec).  Open it once in a browser tab: it must show  {"ok":true,"msg":"TF-Tracker archive is running"}.
                6) Paste the link and the same SECRET in the app: Admin tab > Google Drive archive.
 After you change this code, use Deploy > Manage deployments > Edit > Version: New version > Deploy (the link stays the same).
*/
var SECRET = 'CHANGE-THIS-CODE';
var FOLDER_NAME = 'TF-Tracker Archive';
var OLD_FOLDER_NAME = 'Older than 5 FY';
var KEEP_FY = 5;
var FILE_PREFIX = 'repair&testing register FY-';

function out_(o) { return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON); }
// The app posts with a hidden form and reads the answer through postMessage (this works in every browser; fetch() is often blocked by CORS).
function reply_(o, id) {
  var j = JSON.stringify(o).replace(/</g, '\\u003c'), i = JSON.stringify(String(id || '')).replace(/</g, '\\u003c');
  return HtmlService.createHtmlOutput('<script>var r=' + j + ';r.id=' + i + ';window.top.postMessage(r,"*");</script>OK').setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}
function authorizeOnce() {                    // run this ONCE in the editor (select it above, press Run) so Google asks for your permission
  var lk = LockService.getScriptLock(); lk.waitLock(5000); lk.releaseLock();
  DriveApp.getRootFolder(); SpreadsheetApp.create('tf-tracker-permission-test').getId();
  var it = DriveApp.getFilesByName('tf-tracker-permission-test'); while (it.hasNext()) it.next().setTrashed(true);
  return 'OK';
}
function doGet() { return out_({ ok: true, msg: 'TF-Tracker archive is running' }); }

function fyOf_(month) {                       // '2024-04' -> '2024-25',  '2025-02' -> '2024-25'
  var y = +month.slice(0, 4), m = +month.slice(5, 7), s = m >= 4 ? y : y - 1;
  return s + '-' + String(s + 1).slice(-2);
}
function folder_(parent, name) {
  var it = (parent ? parent.getFoldersByName(name) : DriveApp.getFoldersByName(name));
  return it.hasNext() ? it.next() : (parent ? parent.createFolder(name) : DriveApp.createFolder(name));
}
function ssFor_(folder, fy) {
  var name = FILE_PREFIX + fy, it = folder.getFilesByName(name);
  if (it.hasNext()) return SpreadsheetApp.open(it.next());
  var ss = SpreadsheetApp.create(name), f = DriveApp.getFileById(ss.getId());
  folder.addFile(f); DriveApp.getRootFolder().removeFile(f);
  return ss;
}
function put_(ss, tab, header, rows) {        // rows: arrays, row[0] = the unique key.  Returns how many are new / already there / confirmed
  var sh = ss.getSheetByName(tab);
  if (!sh) { sh = ss.insertSheet(tab); sh.getRange(1, 1, 1, header.length).setValues([header]).setFontWeight('bold'); sh.setFrozenRows(1); }
  var last = sh.getLastRow(), have = {}, i;
  if (last > 1) { var k = sh.getRange(2, 1, last - 1, 1).getValues(); for (i = 0; i < k.length; i++) have[String(k[i][0])] = 1; }
  var add = [], dup = 0;
  for (i = 0; i < rows.length; i++) { var key = String(rows[i][0]); if (have[key]) { dup++; continue; } have[key] = 1; add.push(rows[i].map(function (v) { return v === null || v === undefined ? '' : String(v); })); }
  if (add.length) { var rg = sh.getRange(last + 1, 1, add.length, header.length); rg.setNumberFormat('@'); rg.setValues(add); }
  SpreadsheetApp.flush();
  var l2 = sh.getLastRow(), now = {}, ok = 0;                        // read back: confirm that every sent key is really in the sheet
  if (l2 > 1) { var k2 = sh.getRange(2, 1, l2 - 1, 1).getValues(); for (i = 0; i < k2.length; i++) now[String(k2[i][0])] = 1; }
  for (i = 0; i < rows.length; i++) if (now[String(rows[i][0])]) ok++;
  return { sent: rows.length, saved: add.length, dup: dup, confirmed: ok };
}
function dropFirstBlank_(ss) {
  var s = ss.getSheetByName('Sheet1'); if (s && ss.getSheets().length > 1 && s.getLastRow() === 0) ss.deleteSheet(s);
}
function rotate_(folder) {                    // keep the 5 newest FY files, move the older ones (not delete)
  var names = [], it = folder.getFiles(), f;
  while (it.hasNext()) { f = it.next(); if (f.getName().indexOf(FILE_PREFIX) === 0) names.push(f); }
  names.sort(function (a, b) { return a.getName() < b.getName() ? 1 : -1; });
  if (names.length <= KEEP_FY) return;
  var old = folder_(folder, OLD_FOLDER_NAME);
  for (var i = KEEP_FY; i < names.length; i++) { old.addFile(names[i]); folder.removeFile(names[i]); }
}

function doPost(e) {
  var id = '', out = function (o) { return id ? reply_(o, id) : out_(o); }, lock = null;
  try {
    var raw = (e && e.parameter && e.parameter.payload) || (e && e.postData && e.postData.contents), b = JSON.parse(raw);
    id = (b && b.id) ? String(b.id) : '';
    if (SECRET === 'CHANGE-THIS-CODE' || String(SECRET).length < 8) return out({ ok: false, error: 'Set your own SECRET in the script first.' });
    if (!b || b.token !== SECRET) return out({ ok: false, error: 'Wrong secret code.' });
    if (b.ping) return out({ ok: true, ping: true });                    // the link test needs no Drive and no lock
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(b.month || '')) return out({ ok: false, error: 'Wrong month.' });
    if (b.kind !== 'rr' && b.kind !== 'tr') return out({ ok: false, error: 'Wrong kind.' });
    if (!Array.isArray(b.rows) || !Array.isArray(b.header)) return out({ ok: false, error: 'No rows.' });
    lock = LockService.getScriptLock(); lock.waitLock(30000);
    var fy = fyOf_(b.month), folder = folder_(null, FOLDER_NAME), ss = ssFor_(folder, fy);
    var tab = (b.kind === 'rr' ? 'Repair ' : 'Testing ') + b.month;
    var r = put_(ss, tab, b.header, b.rows);
    dropFirstBlank_(ss); rotate_(folder);
    r.ok = r.confirmed === r.sent; r.file = FILE_PREFIX + fy; r.tab = tab;
    return out(r);
  } catch (err) {
    return out({ ok: false, error: String(err && err.message || err) });
  } finally { if (lock) { try { lock.releaseLock(); } catch (x) { /* ignore */ } } }
}
