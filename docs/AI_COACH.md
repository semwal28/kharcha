# Turn on the free AI coach

The AI coach answers questions ("Where can I save?") and writes a savings plan. It works in three levels:

| Level | Cost | What answers |
|---|---|---|
| On the device (always on) | Free | Built-in rules. Used when the server AI isn't set up, and for people using the app without an account. |
| **Free AI** (recommended) | Free | An open AI model through Groq's free tier (or Google Gemini's free tier). |
| Claude | Paid per use | Anthropic's Claude, if you add credits later. |

The AI key lives only on the server (a Supabase secret). It never ships inside the app.

## Set up the free AI (about 10 minutes, no code)

### 1. Get a free key

**Groq (recommended):** sign up at https://console.groq.com, open **API Keys → Create API key**, copy it. No card needed.

Or **Google Gemini:** https://aistudio.google.com → **Get API key**. Note: on Gemini's free tier, Google may use what's sent to improve its products, and this includes spending summaries. Groq is the better default for money data.

### 2. Save the key in Supabase

Supabase dashboard → your project → **Edge Functions → Secrets** → **Add new secret**:

| Name | Value |
|---|---|
| `AI_API_KEY` | the key from step 1 |

For Gemini, also add:

| Name | Value |
|---|---|
| `AI_BASE_URL` | `https://generativelanguage.googleapis.com/v1beta/openai` |
| `AI_MODEL` | a current Flash model, e.g. `gemini-2.5-flash` |

For Groq the defaults work. To pick a different Groq model, set `AI_MODEL` to any name from https://console.groq.com/docs/models.

### 3. Deploy the `ai-coach` function

Supabase dashboard → **Edge Functions → Deploy a new function → Via Editor**:

1. Name it `ai-coach` (exactly).
2. Replace the sample code with the contents of [`supabase/functions/ai-coach/index.ts`](../supabase/functions/ai-coach/index.ts).
3. Click **Deploy**.
4. Open the function's **Details** and turn **off** "Verify JWT with legacy secret" (or "Enforce JWT verification"). The function checks who's signed in itself.

(With the Supabase CLI instead: `scripts/deploy_backend.sh <project-ref>` with `AI_API_KEY` exported.)

### 4. Check it

Open the app signed in → **Ask AI**. The label at the top says **AI coach** when the server answers, and **On-device answers** when it doesn't.

## Limits

- Free tiers allow a limited number of requests per minute and per day. When the limit is hit, the app says "The free AI is busy" and you can try again a minute later.
- Each person gets 10 AI answers a day on the free plan (set in `DAILY_LIMIT` at the top of the function).
- Only a summary of the current and last month's spending is sent, never the email address.
