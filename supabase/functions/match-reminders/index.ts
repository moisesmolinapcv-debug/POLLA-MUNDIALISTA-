import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL         = Deno.env.get("URL_SUPABASE")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("KEY_SUPABASE_SERVICE_ROLE")!;
const SEND_PUSH_URL        = `${SUPABASE_URL}/functions/v1/send-push`;
const ANON_KEY             = Deno.env.get("KEY_SUPABASE_ANON")!;

serve(async (_req) => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  // Find matches starting in the next 20-25 minutes (window to avoid double-firing)
  const now  = new Date();
  const low  = new Date(now.getTime() + 20 * 60 * 1000); // +20 min
  const high = new Date(now.getTime() + 25 * 60 * 1000); // +25 min

  const { data: upcoming } = await supabase
    .from("matches")
    .select("match_no, home_name, away_name, match_date")
    .gte("match_date", low.toISOString())
    .lte("match_date", high.toISOString())
    .is("home_score", null);

  if (!upcoming || upcoming.length === 0) {
    return new Response(JSON.stringify({ checked: true, reminders: 0 }), { status: 200 });
  }

  // Avoid duplicates: skip matches already notified
  const { data: alreadySent } = await supabase
    .from("sent_reminders")
    .select("match_no")
    .in("match_no", upcoming.map((m: { match_no: number }) => m.match_no));

  const sentSet = new Set((alreadySent ?? []).map((r: { match_no: number }) => r.match_no));
  const toNotify = upcoming.filter((m: { match_no: number }) => !sentSet.has(m.match_no));

  for (const match of toNotify) {
    const matchName = `${match.home_name} vs ${match.away_name}`;
    await fetch(SEND_PUSH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${ANON_KEY}` },
      body: JSON.stringify({ type: "reminder", data: { matchNo: String(match.match_no), matchName } }),
    });

    await supabase.from("sent_reminders").upsert({ match_no: match.match_no });
  }

  return new Response(JSON.stringify({ reminders: toNotify.length }), {
    headers: { "Content-Type": "application/json" },
  });
});
