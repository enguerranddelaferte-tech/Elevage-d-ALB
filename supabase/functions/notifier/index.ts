// Service de notifications de l'appli Élevage d'ALB (fonction Supabase « notifier »).
// - action "vapid"  : renvoie la clé publique utilisée par les téléphones pour s'abonner (créée au premier appel).
// - action "notify" : enregistre une notification pour les destinataires et l'envoie sur leurs téléphones (Web Push).
// - action "test"   : envoie une notification de test à la personne connectée.
// - action "invite" : envoie au propriétaire un e-mail d'invitation avec son code d'accès (service Brevo, clé BREVO_API_KEY).
import { createClient } from "npm:@supabase/supabase-js@2";
import * as webpush from "jsr:@negrel/webpush@0.5.0";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const CONTACT = "https://github.com/enguerranddelaferte-tech/elevage-d-alb";
let appServer: webpush.ApplicationServer | null = null;
let publicKey = "";

async function vapid() {
  if (appServer) return;
  let { data } = await admin.from("secrets").select("v").eq("k", "vapid").maybeSingle();
  if (!data) {
    const keys = await webpush.generateVapidKeys({ extractable: true });
    const exp = await webpush.exportVapidKeys(keys);
    await admin.from("secrets").upsert({ k: "vapid", v: JSON.stringify(exp) }, { onConflict: "k", ignoreDuplicates: true });
    ({ data } = await admin.from("secrets").select("v").eq("k", "vapid").maybeSingle());
  }
  const keys = await webpush.importVapidKeys(JSON.parse(data!.v), { extractable: false });
  appServer = await webpush.ApplicationServer.new({ contactInformation: CONTACT, vapidKeys: keys });
  publicKey = await webpush.exportApplicationServerKey(keys);
}

async function envoyer(userIds: string[], n: { titre: string; texte?: string; lien?: string }) {
  if (!userIds.length) return { destinataires: 0, telephones: 0 };
  await admin.from("notifications").insert(userIds.map((u) => ({ user_id: u, titre: n.titre, texte: n.texte ?? null, lien: n.lien ?? null })));
  const { data: subs } = await admin.from("push_subs").select("endpoint, sub").in("user_id", userIds);
  let ok = 0;
  if (subs?.length) {
    await vapid();
    const payload = JSON.stringify({ titre: n.titre, texte: n.texte ?? "", lien: n.lien ?? "" });
    await Promise.all(subs.map(async (s) => {
      try {
        await appServer!.subscribe(s.sub as webpush.PushSubscription).pushTextMessage(payload, { ttl: 86400 } as webpush.PushMessageOptions);
        ok++;
      } catch (e) {
        console.log("push:", String(e));
        if (e instanceof webpush.PushMessageError && e.isGone()) await admin.from("push_subs").delete().eq("endpoint", s.endpoint);
      }
    }));
  }
  return { destinataires: userIds.length, telephones: ok };
}

function code() {
  const a = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789", r = crypto.getRandomValues(new Uint32Array(8));
  const s = Array.from(r, (x) => a[x % a.length]).join("");
  return s.slice(0, 4) + "-" + s.slice(4);
}
const esc = (s: string) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);
  let b: Record<string, any> = {};
  try { b = await req.json(); } catch { return json({ error: "Requête invalide" }, 400); }

  try {
    if (b.action === "vapid") { await vapid(); return json({ publicKey }); }

    // Personne connectée
    // La passerelle Supabase a déjà vérifié la signature du jeton (verify_jwt) : on lit l'identifiant dedans.
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    let uid = "";
    try {
      const p = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(token.split(".")[1].length / 4) * 4, "=")));
      if (p.role === "authenticated" && typeof p.sub === "string" && (!p.exp || p.exp * 1000 > Date.now())) uid = p.sub;
    } catch { /* jeton illisible */ }
    if (!uid) {
      const { data: u, error } = await admin.auth.getUser(token);
      if (error) console.log("getUser:", error.message);
      uid = u?.user?.id ?? "";
    }
    if (!uid) return json({ error: "Connexion requise" }, 401);
    const { data: prof } = await admin.from("profils").select("role, proprietaire_id").eq("user_id", uid).maybeSingle();
    if (!prof) return json({ error: "Compte non activé" }, 403);
    const gerant = prof.role === "gerant";

    if (b.action === "test") return json(await envoyer([uid], { titre: "Notifications activées", texte: "Vous recevrez ici les annulations de cours, messages et factures de l'écurie.", lien: "" }));

    if (b.action === "notify") {
      const titre = String(b.titre ?? "").slice(0, 120), texte = String(b.texte ?? "").slice(0, 400), lien = String(b.lien ?? "").slice(0, 40);
      if (!titre) return json({ error: "Titre manquant" }, 400);
      const c = b.cible ?? {};
      let q = admin.from("profils").select("user_id");
      if (c.type === "gerant") q = q.eq("role", "gerant");
      else if (!gerant) return json({ error: "Non autorisé" }, 403);
      else if (c.type === "tous") q = q.eq("role", "client");
      else if (c.type === "proprios" && Array.isArray(c.ids) && c.ids.length) q = q.eq("role", "client").in("proprietaire_id", c.ids.slice(0, 500).map(String));
      else return json({ destinataires: 0, telephones: 0 });
      const { data: rows } = await q;
      const ids = [...new Set((rows ?? []).map((r) => r.user_id).filter((x) => x !== uid))];
      return json(await envoyer(ids, { titre, texte, lien }));
    }

    if (b.action === "invite") {
      if (!gerant) return json({ error: "Non autorisé" }, 403);
      const { data: p } = await admin.from("proprietaires").select("id, user_id, invite_code, data").eq("id", String(b.proprietaire_id ?? "")).maybeSingle();
      if (!p) return json({ error: "Fiche introuvable" }, 404);
      if (p.user_id) return json({ ok: false, raison: "deja_active" });
      const email = String(p.data?.email ?? "").trim();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ ok: false, raison: "pas_email" });
      let inv = p.invite_code as string | null;
      if (!inv) { inv = code(); await admin.from("proprietaires").update({ invite_code: inv }).eq("id", p.id); }
      const key = Deno.env.get("BREVO_API_KEY");
      const { data: cfg } = await admin.from("config").select("data").eq("id", "main").maybeSingle();
      const ec = (cfg?.data as any)?.ecurie ?? {};
      const from = Deno.env.get("EMAIL_FROM") || ec.email;
      if (!key || !from) return json({ ok: false, raison: "email_non_configure", code: inv });
      const nomEcurie = ec.nom || "Élevage d'ALB", lien = String(b.lien || ""), prenom = String(p.data?.nom ?? "").split(" ")[0];
      const texte = `Bonjour ${prenom},\n\nVotre espace client ${nomEcurie} est prêt : réservation des cours, suivi de votre cheval, factures et messages.\n\n1. Ouvrez ${lien}\n2. Touchez « Première connexion : créer mon compte »\n3. Saisissez votre e-mail, un mot de passe et ce code d'activation : ${inv}\n\nÀ bientôt !\n${nomEcurie}`;
      const html = `<div style="font-family:Arial,sans-serif;font-size:15px;line-height:1.5;color:#161B26;max-width:520px">
        <p>Bonjour ${esc(prenom)},</p><p>Votre espace client <b>${esc(nomEcurie)}</b> est prêt : réservation des cours, suivi de votre cheval, factures et messages.</p>
        <ol><li>Ouvrez <a href="${esc(lien)}">${esc(lien)}</a></li><li>Touchez « Première connexion : créer mon compte »</li><li>Saisissez votre e-mail, un mot de passe et ce code d'activation :</li></ol>
        <p style="font-size:24px;font-weight:bold;letter-spacing:2px;background:#E2E6EF;color:#1E2A44;padding:12px 16px;border-radius:10px;display:inline-block">${esc(inv)}</p>
        <p>À bientôt !<br>${esc(nomEcurie)}</p></div>`;
      const r = await fetch("https://api.brevo.com/v3/smtp/email", {
        method: "POST", headers: { "api-key": key, "Content-Type": "application/json", accept: "application/json" },
        body: JSON.stringify({ sender: { name: nomEcurie, email: from }, to: [{ email, name: p.data?.nom || email }], replyTo: { email: from }, subject: `Votre espace client ${nomEcurie}`, htmlContent: html, textContent: texte }),
      });
      if (!r.ok) return json({ ok: false, raison: "envoi_refuse", detail: (await r.text()).slice(0, 300), code: inv });
      return json({ ok: true, email, code: inv });
    }

    return json({ error: "Action inconnue" }, 400);
  } catch (e) {
    return json({ error: "Erreur du service de notifications", detail: String(e) }, 500);
  }
});
