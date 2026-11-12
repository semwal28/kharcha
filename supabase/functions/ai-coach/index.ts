// Spendwell AI coach: a Supabase Edge Function.
//
// POST /functions/v1/ai-coach   (Authorization: Bearer <user access token>)
//   { "mode": "plan", "summary": "<month snapshot>" }
//     -> { "items": [{ title, why, action, monthly_saving, difficulty }] }
//   { "mode": "chat", "summary": "...", "messages": [{ role, content }, ...] }
//     -> { "reply": "..." }
//
// Which AI answers (set these as Edge Function secrets):
//   Free:   AI_API_KEY    a free key from an OpenAI-compatible provider.
//           AI_BASE_URL   optional, defaults to Groq: https://api.groq.com/openai/v1
//                         Google Gemini: https://generativelanguage.googleapis.com/v1beta/openai
//           AI_MODEL      optional, defaults to openai/gpt-oss-120b (Groq).
//                         For Gemini use a Flash model, e.g. gemini-2.5-flash.
//   Claude: ANTHROPIC_API_KEY (used when AI_API_KEY is not set)
//           CLAUDE_MODEL  optional, defaults to claude-opus-5-5
// With neither, the function answers 503 and the app uses its on-device coach.
// SUPABASE_URL and the server key (SUPABASE_SERVICE_ROLE_KEY, or SUPABASE_SECRET_KEYS
// on projects using the new API keys) are provided by Supabase.

import Anthropic from "npm:@anthropic-ai/sdk@1.2.0";
import { createClient } from "npm:@supabase/supabase-js@2.119.0";

/** The server key: the legacy service_role key, or the default new secret key. */
function serviceKey(): string {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as Record<string, string>;
    return keys.default ?? Object.values(keys)[0] ?? "";
  } catch {
    return "";
  }
}

const MODEL = Deno.env.get("CLAUDE_MODEL") ?? "claude-opus-5-5";
const FREE_KEY = Deno.env.get("AI_API_KEY") ?? "";
const FREE_BASE = (Deno.env.get("AI_BASE_URL") ?? "https://api.groq.com/openai/v1").replace(/\/+$/, "");
const FREE_MODEL = Deno.env.get("AI_MODEL") ?? "openai/gpt-oss-120b";
const PROVIDER: "free" | "claude" | null = FREE_KEY ? "free" : Deno.env.get("ANTHROPIC_API_KEY") ? "claude" : null;
// Free tiers have small per-minute token limits, so send a shorter snapshot.
const MAX_FREE_SUMMARY_CHARS = 12_000;
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

const PLAN_RULES = `You are the savings coach inside Spendwell, an expense tracker app.
Using ONLY the user's data below, write a short savings plan.
- 4 to 5 actions, easiest first.
- Each action cites real merchants, counts or amounts from the data.
- Keep it very short: title at most 6 words, why at most 12 words, action at most 8 words.
- monthly_saving is a realistic whole number in the data's currency, per month.
- No generic advice such as "track your spending".`;

const CHAT_RULES = `You are the money coach inside Spendwell, an expense tracker app.
Answer the user's question using ONLY their data below.
- Use the currency shown in the data; for INR use Indian digit grouping (₹1,25,000).
- Be warm and very brief: at most 3 short sentences or 3 bullets, under 60 words.
- When you suggest a saving, name the merchant or habit and give an amount per month.
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

class UpstreamError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

/** One request to a free OpenAI-compatible chat completions API. */
async function freeCompletion(system: string, turns: Turn[], wantJson: boolean): Promise<string> {
  const res = await fetch(`${FREE_BASE}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${FREE_KEY}` },
    body: JSON.stringify({
      model: FREE_MODEL,
      messages: [{ role: "system", content: system }, ...turns],
      max_tokens: 4000,
      temperature: 0.4,
      ...(wantJson ? { response_format: { type: "json_object" } } : {}),
    }),
    signal: AbortSignal.timeout(45_000),
  });
  if (!res.ok) throw new UpstreamError(res.status, (await res.text()).slice(0, 300));
  const data = await res.json();
  const text = data?.choices?.[0]?.message?.content;
  if (typeof text !== "string" || !text.trim()) throw new UpstreamError(502, "empty answer");
  return text.trim();
}

/** Pulls the JSON object out of a reply that may have extra text around it. */
function parseJsonObject(text: string): Record<string, unknown> {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) throw new SyntaxError("no JSON object");
  return JSON.parse(text.slice(start, end + 1));
}

/** Keeps only well-formed plan items. */
function cleanItems(raw: unknown): unknown[] {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const it of raw.slice(0, 6)) {
    if (typeof it !== "object" || it === null) continue;
    const r = it as Record<string, unknown>;
    if (typeof r.title !== "string" || !r.title.trim()) continue;
    const saving = Math.max(0, Math.round(Number(r.monthly_saving) || 0));
    const difficulty = ["Easy", "Medium", "Hard"].includes(r.difficulty as string) ? r.difficulty : "Medium";
    out.push({
      title: r.title.trim().slice(0, 80),
      why: String(r.why ?? "").trim().slice(0, 160),
      action: String(r.action ?? "").trim().slice(0, 120),
      monthly_saving: saving,
      difficulty,
    });
  }
  return out;
}

const PLAN_JSON_SHAPE = `Reply with JSON only, exactly this shape:
{"items":[{"title":"...","why":"...","action":"...","monthly_saving":1200,"difficulty":"Easy"}]}
difficulty is one of Easy, Medium, Hard.`;

const anthropic = new Anthropic(); // reads ANTHROPIC_API_KEY

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "method", message: "Use POST." });
  if (!PROVIDER) {
    return json(503, { error: "not_configured", message: "AI is not set up on the server yet." });
  }

  // 1. Who is asking? Verify the user's access token.
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey());
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

  // 4a. Ask the free provider.
  if (PROVIDER === "free") {
    const data = summary.slice(0, MAX_FREE_SUMMARY_CHARS);
    try {
      if (mode === "plan") {
        const text = await freeCompletion(`${PLAN_RULES}\n${PLAN_JSON_SHAPE}\n\nDATA\n${data}`, [{ role: "user", content: "Write my savings plan." }], true);
        const items = cleanItems(parseJsonObject(text).items);
        if (items.length === 0) return json(502, { error: "upstream", message: "The AI coach didn't return a plan. Try again." });
        return json(200, { items });
      }
      return json(200, { reply: await freeCompletion(`${CHAT_RULES}\n\nDATA\n${data}`, turns!, false) });
    } catch (err) {
      if (err instanceof UpstreamError && err.status === 429) {
        return json(503, { error: "busy", message: "The free AI is busy right now. Try again in a minute." });
      }
      if (err instanceof SyntaxError) {
        return json(502, { error: "upstream", message: "The AI coach's plan came back garbled. Try again." });
      }
      console.error("free AI error", err instanceof UpstreamError ? `${err.status} ${err.message}` : err);
      return json(502, { error: "upstream", message: "The AI coach could not answer right now. Try again." });
    }
  }

  // 4b. Ask Claude.
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
