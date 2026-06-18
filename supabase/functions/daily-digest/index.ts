import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL         = Deno.env.get("URL_SUPABASE")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("KEY_SUPABASE_SERVICE_ROLE")!;
const SEND_PUSH_URL        = `${SUPABASE_URL}/functions/v1/send-push`;
const ANON_KEY             = Deno.env.get("KEY_SUPABASE_ANON")!;

serve(async (_req) => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  // Check if there are group-stage matches today (UTC)
  const todayStart = new Date();
  todayStart.setUTCHours(0, 0, 0, 0);
  const todayEnd = new Date();
  todayEnd.setUTCHours(23, 59, 59, 999);

  const { data: todayMatches } = await supabase
    .from("matches")
    .select("match_no, home_name, away_name, match_date")
    .eq("stage", "group")
    .gte("match_date", todayStart.toISOString())
    .lte("match_date", todayEnd.toISOString())
    .is("home_score", null)
    .order("match_date", { ascending: true });

  if (!todayMatches || todayMatches.length === 0) {
    return new Response(JSON.stringify({ sent: false, reason: "no matches today" }), { status: 200 });
  }

  // Build digest message in Venezuelan local time (UTC-4)
  const firstMatch = todayMatches[0];
  const kickoff = new Date(firstMatch.match_date);
  const timeVET = kickoff.toLocaleTimeString("es-VE", {
    hour: "2-digit", minute: "2-digit", timeZone: "America/Caracas",
  });

  const count   = todayMatches.length;
  const message = `Hoy hay ${count} partido${count > 1 ? "s" : ""}. El primero (${firstMatch.home_name} vs ${firstMatch.away_name}) a las ${timeVET}. ¡Que no te agarre el candado!`;

  await fetch(SEND_PUSH_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${ANON_KEY}` },
    body: JSON.stringify({ type: "digest", data: { message } }),
  });

  return new Response(JSON.stringify({ sent: true, matches: count }), {
    headers: { "Content-Type": "application/json" },
  });
});
