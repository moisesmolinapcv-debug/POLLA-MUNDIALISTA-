import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const VAPID_PUBLIC_KEY  = Deno.env.get("VAPID_PUBLIC_KEY")!;
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY")!;
const VAPID_SUBJECT     = Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@parley.la";
const SUPABASE_URL      = Deno.env.get("URL_SUPABASE")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("KEY_SUPABASE_SERVICE_ROLE")!;

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

const PAYLOADS: Record<string, (d: Record<string, string>) => { title: string; body: string; tag: string }> = {
  reminder: (d) => ({
    title: "⏰ ¡Pronostica ahora!",
    body: `Quedan 20 min para el ${d.matchName}. ¡Cierra tu pronóstico!`,
    tag: `reminder-${d.matchNo}`,
  }),
  result: (d) => ({
    title: "🏆 Resultado publicado",
    body: `${d.homeName} ${d.homeScore} - ${d.awayScore} ${d.awayName}. ¡Revisa tus puntos!`,
    tag: `result-${d.matchNo}`,
  }),
  leaderboard: (_d) => ({
    title: "📊 Tabla actualizada",
    body: "La clasificación cambió. ¿Subiste o bajaste? ¡Entra a ver!",
    tag: "leaderboard-update",
  }),
  digest: (d) => ({
    title: "📅 ¡Hoy hay fútbol!",
    body: d.message ?? "Hay partidos hoy. Entra a revisar tus pronósticos.",
    tag: "daily-digest",
  }),
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type" } });
  }

  try {
    const body = await req.json() as { type: string; data?: Record<string, string> };
    const { type, data = {} } = body;

    const builder = PAYLOADS[type];
    if (!builder) {
      return new Response(JSON.stringify({ error: `Unknown type: ${type}` }), { status: 400 });
    }

    const { title, body: notifBody, tag } = builder(data);
    const payload = JSON.stringify({ title, body: notifBody, data: { url: "./", tag } });

    // Fetch all subscriptions using the service-role key (bypasses RLS)
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const { data: subs, error } = await supabase.from("push_subscriptions").select("subscription");
    if (error) throw error;

    const results = await Promise.allSettled(
      (subs ?? []).map(({ subscription }) =>
        webpush.sendNotification(subscription, payload)
      )
    );

    const sent = results.filter((r) => r.status === "fulfilled").length;
    const failed = results.filter((r) => r.status === "rejected").length;

    return new Response(JSON.stringify({ sent, failed }), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
