// Kharcha AI coach: a Supabase Edge Function that calls Claude.
//
// POST /functions/v1/ai-coach   (Authorization: Bearer <user access token>)
//   { "mode": "plan", "summary": "<month snapshot>" }
//     -> { "items": [{ title, why, action, monthly_saving, difficulty }] }
//   { "mode": "chat", "summary": "...", "messages": [{ role, content }, ...] }
//     -> { "reply": "..." }
//
// Secrets (set with `supabase secrets set`):
//   ANTHROPIC_API_KEY   required
//   CLAUDE_MODEL        optional, defaults to claude-opus-5-5
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

import Anthropic from "npm:@anthropic-ai/sdk@1.7.0";
import { createClient } from "npm:@supabase/supabase-js@2.119.0";

const MODEL = Deno.env.get("CLAUDE_MODEL") ?? "claude-opus-5-5";
const DAILY_LIMIT: Record<string, number> = { free: 10, pro: 100, family: 200 };
const MAX_SUMMARY_CHARS = 60_000;
const MAX_TURNS = 10;
const MAX_TURN_CHARS = 2_000;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const PLAN_RULES = `You are the savings coach inside Kharcha, an Indian expense tracker app.
Using ONLY the user's data below, write a short savings plan.
- 4 to 5 actions, easiest first.
- Each action cites real merchants, counts or rupee amounts from the data.
- Keep it very short: title at most 6 words, why at most 12 words, action at most 8 words.
- monthly_saving is a realistic whole number of rupees per month.
- No generic advice such as "track your spending".`;

const CHAT_RULES = `You are the money coach inside Kharcha, an Indian expense tracker app.
Answer the user's question using ONLY their data below.
- Use ₹ with Indian digit grouping (₹1,25,000).
- Be warm and very brief: at most 3 short sentences or 3 bullets, under 60 words.
- When you suggest a saving, name the merchant or habit and give a ₹ amount per month.
- If the data cannot answer the question, say so plainly. No headings, no tables.`;

const PLAN_SCHEMA = {
  type: "object",
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          why: { type: "string" },
          action: { type: "string" },
          monthly_saving: { type: "integer" },
          difficulty: { type: "string", enum: ["Easy", "Medium", "Hard"] },
        },
        required: ["title", "why", "action", "monthly_saving", "difficulty"],
        additionalProperties: false,
      },
    },
  },
  required: ["items"],
  additionalProperties: false,
};

type Turn = { role: "user" | "assistant"; content: string };

function parseTurns(raw: unknown): Turn[] | null {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > MAX_TURNS) return null;
  const turns: Turn[] = [];
  for (const t of raw) {
    if (typeof t !== "object" || t === null) return null;
    const { role, content } = t as Record<string, unknown>;
    if ((role !== "user" && role !== "assistant") || typeof content !== "string") return null;
    const text = content.trim().slice(0, MAX_TURN_CHARS);
    if (!text) return null;
    turns.push({ role, content: text });
  }
  // The conversation must start and end with the user.
  if (turns[0].role !== "user" || turns[turns.length - 1].role !== "user") return null;
  return turns;
}

function textOf(content: Anthropic.Beta.BetaContentBlock[]): string {
  return content
    .filter((b): b is Anthropic.Beta.BetaTextBlock => b.type === "text")
    .map((b) => b.text)
    .join("")
    .trim();
}

const anthropic = new Anthropic(); // reads ANTHROPIC_API_KEY

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "method", message: "Use POST." });
  if (!Deno.env.get("ANTHROPIC_API_KEY")) {
    return json(503, { error: "not_configured", message: "AI is not set up on the server yet." });
  }

  // 1. Who is asking? Verify the user's access token.
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: userData } = jwt ? await admin.auth.getUser(jwt) : { data: null };
  const user = userData?.user;
  if (!user) return json(401, { error: "auth", message: "Sign in again to use AI." });

  // 2. Validate the request.
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "bad_request", message: "Send JSON." });
  }
  const mode = body.mode;
  const summary = typeof body.summary === "string" ? body.summary.slice(0, MAX_SUMMARY_CHARS) : "";
  if ((mode !== "plan" && mode !== "chat") || !summary.trim()) {
    return json(400, { error: "bad_request", message: "Missing mode or summary." });
  }
  const turns = mode === "chat" ? parseTurns(body.messages) : null;
  if (mode === "chat" && !turns) {
    return json(400, { error: "bad_request", message: "Messages must start and end with the user." });
  }

  // 3. Daily limit per plan, counted with the service role.
  const { data: profile } = await admin.from("profiles").select("plan").eq("id", user.id).maybeSingle();
  const limit = DAILY_LIMIT[(profile?.plan as string | undefined) ?? "free"] ?? DAILY_LIMIT.free;
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count } = await admin
    .from("ai_requests")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gte("created_at", since);
  if ((count ?? 0) >= limit) {
    return json(429, { error: "limit", message: `You've used today's ${limit} AI answers. More tomorrow.` });
  }
  await admin.from("ai_requests").insert({ user_id: user.id, kind: mode });

  // 4. Ask Claude.
  try {
    const system: Anthropic.Beta.BetaTextBlockParam[] = [
      {
        type: "text",
        text: `${mode === "plan" ? PLAN_RULES : CHAT_RULES}\n\nDATA\n${summary}`,
        cache_control: { type: "ephemeral" },
      },
    ];

    if (mode === "plan") {
      const response = await anthropic.beta.messages.create({
        model: MODEL,
        max_tokens: 16000,
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        output_config: { effort: "medium", format: { type: "json_schema", schema: PLAN_SCHEMA } },
        system,
        messages: [{ role: "user", content: "Write my savings plan." }],
      });
      if (response.stop_reason === "refusal") {
        return json(422, { error: "refused", message: "Claude couldn't help with this one. Try again later." });
      }
      const parsed = JSON.parse(textOf(response.content) || "{}");
      return json(200, { items: Array.isArray(parsed.items) ? parsed.items.slice(0, 6) : [] });
    }

    const response = await anthropic.beta.messages.create({
      model: MODEL,
      max_tokens: 16000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: { effort: "low" },
      system,
      messages: turns!,
    });
    if (response.stop_reason === "refusal") {
      return json(422, { error: "refused", message: "Claude couldn't answer that. Try asking another way." });
    }
    return json(200, { reply: textOf(response.content) });
  } catch (err) {
    if (err instanceof Anthropic.RateLimitError) {
      return json(503, { error: "busy", message: "AI is busy right now. Try again in a minute." });
    }
    if (err instanceof Anthropic.APIError) {
      console.error("Claude API error", err.status, err.message);
      return json(502, { error: "upstream", message: "Claude could not answer right now. Try again." });
    }
    if (err instanceof SyntaxError) {
      return json(502, { error: "upstream", message: "Claude's plan came back garbled. Try again." });
    }
    console.error("ai-coach failed", err);
    return json(500, { error: "internal", message: "Something went wrong. Try again." });
  }
});
