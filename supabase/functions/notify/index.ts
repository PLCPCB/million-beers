// Edge Function « notify » : envoie les notifications push préparées par la base.
// Appelée uniquement par la base (en-tête x-hook-secret). « Verify JWT » doit être désactivé.
// Secrets à définir dans Supabase → Edge Functions → Secrets : VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, HOOK_SECRET.
import webpush from "npm:web-push@3.6.7";

const HOOK = Deno.env.get("HOOK_SECRET") ?? "";
webpush.setVapidDetails(
  "https://plcpcb.github.io/million-beers/",
  Deno.env.get("VAPID_PUBLIC_KEY") ?? "",
  Deno.env.get("VAPID_PRIVATE_KEY") ?? "",
);

Deno.serve(async (req) => {
  if (req.method !== "POST" || !HOOK || req.headers.get("x-hook-secret") !== HOOK) {
    return new Response("unauthorized", { status: 401 });
  }
  const { subs = [], payload = {} } = await req.json().catch(() => ({}));
  const dead: string[] = [];
  const errors: string[] = [];
  let sent = 0;
  await Promise.all((subs as webpush.PushSubscription[]).map(async (s) => {
    try {
      await webpush.sendNotification(s, JSON.stringify(payload), { TTL: 4 * 3600, urgency: "high" });
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode ?? 0;
      if (code === 404 || code === 410) dead.push(s.endpoint);
      else errors.push(String(code || (e as Error).message).slice(0, 120));
    }
  }));
  if (dead.length) {
    const url = Deno.env.get("SUPABASE_URL") + "/rest/v1/rpc/drop_push_subs";
    const key = Deno.env.get("SUPABASE_ANON_KEY") ?? "sb_publishable_ubKdSCY0_xbVmXxT8wQQOA_6r0_u0eH";
    await fetch(url, {
      method: "POST",
      headers: { apikey: key, "Content-Type": "application/json" },
      body: JSON.stringify({ p_secret: HOOK, p_endpoints: dead }),
    }).catch(() => {});
  }
  return Response.json({ sent, dead: dead.length, errors });
});
