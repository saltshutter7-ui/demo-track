// TF-Tracker : Edge Function  "admin-users"   (Supabase Dashboard > Edge Functions > Deploy a new function > name: admin-users)
// Creates users, resets passwords, deletes users.  It uses the secret key that Supabase keeps INSIDE the function
// (SUPABASE_SERVICE_ROLE_KEY is added by Supabase itself - you never copy or paste it anywhere).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const TABS = ["sum", "data", "drv", "emg", "mr"];

function tempPass() {
  const a = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789", b = new Uint8Array(6);
  crypto.getRandomValues(b);
  let s = ""; for (const x of b) s += a[x % a.length];
  return "Tx@" + s;
}

// pure permission rules (tested separately).  caller / target = profile rows,  wsDiv = {WORKSHOP: org_division}
export function decide(caller, action, body, target, wsDiv) {
  if (!caller || !caller.active) return "Your ID is not active.";
  if (caller.role !== "creator" && caller.role !== "admin") return "Only an Admin can do this.";
  if (action === "create") {
    const id = String(body.login || "").trim().toLowerCase();
    if (!/^[a-z0-9._@-]{3,30}$/.test(id)) return "User ID must be 3-30 characters (a-z, 0-9, . _ - @), no spaces.";
    const role = String(body.role || "je");
    if (caller.role === "admin" && role !== "je") return "An Admin can create only normal users.";
    if (caller.role === "creator" && !["admin", "discom", "je"].includes(role)) return "Role must be admin, discom or je.";
    const div = caller.role === "admin" ? caller.org_division : String(body.div || "").trim();
    if ((role === "admin" || role === "je") && !div) return "Division is required.";
    const scope = Array.isArray(body.scope) ? body.scope : [];
    if (role === "je") {
      if (!scope.length) return "Choose at least one workshop.";
      for (const w of scope) if (wsDiv[w] !== div) return "Workshop " + w + " is not in this division.";
    }
    if (body.tabs != null) {
      if (!Array.isArray(body.tabs) || !body.tabs.length || body.tabs.some((t) => !TABS.includes(t))) return "Choose at least one tab.";
    }
    if (target) return "This User ID already exists.";
    return null;
  }
  // reset / delete
  if (!target) return "User not found.";
  if (target.role === "creator") return "This user cannot be changed here.";
  if (target.user_id === caller.user_id) return "You cannot do this to your own ID.";
  if (caller.role === "admin" && !(target.role === "je" && target.org_division === caller.org_division)) return "You can manage only the users of your own division.";
  return null;
}

async function handle(req) {
  const url = Deno.env.get("SUPABASE_URL"), svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const sb = createClient(url, svc, { auth: { persistSession: false } });
  const { data: u, error: ue } = await sb.auth.getUser(jwt);
  if (ue || !u || !u.user) return { ok: false, error: "Please log in again." };
  const { data: caller } = await sb.from("profiles").select("*").eq("user_id", u.user.id).maybeSingle();
  const body = await req.json().catch(() => ({}));
  const action = String(body.action || "");
  if (!["create", "reset", "delete"].includes(action)) return { ok: false, error: "Unknown action." };
  const login = String(body.login || "").trim().toLowerCase();
  const { data: t } = await sb.from("profiles").select("*").eq("login_id", login).maybeSingle();
  const { data: ws } = await sb.from("workshops").select("name,org_division");
  const wsDiv = {}; (ws || []).forEach((w) => (wsDiv[w.name] = w.org_division));
  const bad = decide(caller, action, body, t, wsDiv);
  if (bad) return { ok: false, error: bad };

  if (action === "create") {
    const pw = tempPass(), role = String(body.role || "je");
    const div = caller.role === "admin" ? caller.org_division : String(body.div || "").trim() || null;
    const { data: cu, error: ce } = await sb.auth.admin.createUser({ email: login + "@tf.uppcl", password: pw, email_confirm: true });
    if (ce) return { ok: false, error: /already|exists|registered/i.test(ce.message) ? "This User ID already exists." : ce.message };
    const tabs = body.tabs == null ? null : body.tabs;
    const edit = role === "je" || role === "admin" ? !!body.edit && (!tabs || tabs.includes("data")) : false;
    const { error: pe } = await sb.from("profiles").insert({
      user_id: cu.user.id, login_id: login, display: String(body.name || login).trim(), role,
      org_division: role === "discom" ? null : div, scope: role === "je" ? body.scope : [],
      can_edit: edit, active: true, must_change: true, tabs,
    });
    if (pe) { await sb.auth.admin.deleteUser(cu.user.id); return { ok: false, error: pe.message }; }
    return { ok: true, password: pw };
  }
  if (action === "reset") {
    const pw = tempPass();
    const { error } = await sb.auth.admin.updateUserById(t.user_id, { password: pw });
    if (error) return { ok: false, error: error.message };
    await sb.from("profiles").update({ must_change: true }).eq("user_id", t.user_id);
    return { ok: true, password: pw };
  }
  const { error } = await sb.auth.admin.deleteUser(t.user_id);        // the profile row goes with it (on delete cascade)
  if (error) return { ok: false, error: error.message };
  return { ok: true };
}

if (typeof Deno !== "undefined" && Deno.serve) {
  Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    let out;
    try { out = await handle(req); } catch (e) { out = { ok: false, error: "Server error: " + (e && e.message ? e.message : e) }; }
    return new Response(JSON.stringify(out), { status: 200, headers: { ...CORS, "Content-Type": "application/json" } });
  });
}
