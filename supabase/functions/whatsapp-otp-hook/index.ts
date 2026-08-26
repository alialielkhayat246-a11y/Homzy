// Supabase Auth "Send SMS" hook → delivers the OTP over WhatsApp via Meta
// Cloud API. Supabase generates + verifies the code and manages the session;
// this function only sends it. Configure in: Auth → Hooks → Send SMS → this URL.
//
// Required function secrets (Edge Function → Secrets):
//   SEND_SMS_HOOK_SECRET  the secret Supabase shows when you create the hook (starts v1,whsec_)
//   WA_PHONE_ID           WhatsApp Cloud API phone-number ID
//   WA_TOKEN              a permanent WhatsApp access token
//   WA_TEMPLATE           approved authentication template name (default: otp)
//   WA_LANG               template language code (default: ar)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

function b64decode(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function b64encode(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

async function verifyWebhook(secretRaw: string, headers: Headers, payload: string): Promise<boolean> {
  const id = headers.get("webhook-id");
  const ts = headers.get("webhook-timestamp");
  const sigHeader = headers.get("webhook-signature");
  if (!id || !ts || !sigHeader) return false;
  const secret = secretRaw.replace(/^v1,/, "").replace(/^whsec_/, "");
  const key = await crypto.subtle.importKey(
    "raw", b64decode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${id}.${ts}.${payload}`));
  const expected = b64encode(new Uint8Array(mac));
  return sigHeader.split(" ").some((p) => p.split(",")[1] === expected);
}

Deno.serve(async (req) => {
  const payload = await req.text();
  const hookSecret = Deno.env.get("SEND_SMS_HOOK_SECRET");
  if (hookSecret) {
    const ok = await verifyWebhook(hookSecret, req.headers, payload);
    if (!ok) return new Response(JSON.stringify({ error: "bad signature" }), { status: 401 });
  }

  let body: any;
  try { body = JSON.parse(payload); } catch { return new Response("bad json", { status: 400 }); }
  const phone: string = (body?.user?.phone || "").replace(/[^0-9]/g, "");
  const otp: string = body?.sms?.otp || "";
  if (!phone || !otp) return new Response(JSON.stringify({ error: "missing phone/otp" }), { status: 400 });

  const PHONE_ID = Deno.env.get("WA_PHONE_ID");
  const TOKEN = Deno.env.get("WA_TOKEN");
  const TEMPLATE = Deno.env.get("WA_TEMPLATE") || "otp";
  const LANG = Deno.env.get("WA_LANG") || "ar";
  if (!PHONE_ID || !TOKEN) {
    return new Response(JSON.stringify({ error: "WhatsApp not configured (WA_PHONE_ID / WA_TOKEN)" }), { status: 500 });
  }

  const res = await fetch(`https://graph.facebook.com/v21.0/${PHONE_ID}/messages`, {
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to: phone,
      type: "template",
      template: {
        name: TEMPLATE,
        language: { code: LANG },
        components: [
          { type: "body", parameters: [{ type: "text", text: otp }] },
          { type: "button", sub_type: "url", index: "0", parameters: [{ type: "text", text: otp }] },
        ],
      },
    }),
  });

  if (!res.ok) {
    const errTxt = await res.text();
    console.error("WhatsApp send failed", res.status, errTxt);
    return new Response(JSON.stringify({ error: "whatsapp_send_failed", detail: errTxt }), { status: 500 });
  }
  return new Response(JSON.stringify({}), { headers: { "Content-Type": "application/json" } });
});
