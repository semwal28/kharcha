// Spendwell: delete the signed-in user's account and all their data.
//
// POST /functions/v1/delete-account   (Authorization: Bearer <user access token>)
//   -> { "ok": true }
//
// Deleting the auth user removes the profile, expenses, custom categories,
// budgets and AI usage rows too (every table references auth.users with
// ON DELETE CASCADE). Required by Google Play for apps with sign-in.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

import { createClient } from "npm:@supabase/supabase-js@2.119.0";

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "method", message: "Use POST." });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data } = jwt ? await admin.auth.getUser(jwt) : { data: null };
  const user = data?.user;
  if (!user) return json(401, { error: "auth", message: "Sign in again, then try deleting your account." });

  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) {
    console.error("delete-account failed", user.id, error.message);
    return json(500, { error: "delete_failed", message: "Could not delete your account. Try again." });
  }
  return json(200, { ok: true });
});
