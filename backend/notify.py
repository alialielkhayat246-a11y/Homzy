"""Lead notifications — email Ali when a client asks a sales rep to contact them.

The client's identity (name + phone) is taken from their REGISTERED profile
server-side (verified via their Supabase session), not trusted from the browser.
Email is best-effort: if SMTP isn't configured the lead is still recorded and
shows up in /inbox — the email is an extra.
"""
from __future__ import annotations

from typing import Any

from . import config


def verify_user(token: str) -> dict[str, Any] | None:
    """Confirm the Supabase access token and return the auth user (id, email)."""
    if not token or not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return None
    import requests

    try:
        r = requests.get(
            config.SUPABASE_URL.rstrip("/") + "/auth/v1/user",
            headers={"apikey": config.SUPABASE_KEY, "Authorization": "Bearer " + token},
            timeout=10,
        )
        if r.status_code != 200:
            return None
        return r.json()
    except Exception:
        return None


def get_profile(uid: str, token: str) -> dict[str, Any]:
    """Read the user's own profile (RLS lets them read their own row)."""
    try:
        import requests

        r = requests.get(
            config.SUPABASE_URL.rstrip("/") + "/rest/v1/profiles",
            params={"id": "eq." + uid, "select": "full_name,phone,email", "limit": "1"},
            headers={"apikey": config.SUPABASE_KEY, "Authorization": "Bearer " + token},
            timeout=10,
        )
        rows = r.json() if r.ok else []
        return rows[0] if rows else {}
    except Exception:
        return {}


def email_configured() -> bool:
    return bool(config.SMTP_HOST and config.SMTP_USER and config.SMTP_PASS
                and config.LEAD_NOTIFY_TO)


def send_lead_email(name: str, phone: str, email: str, context: str,
                    message: str, lang: str) -> bool:
    """Send the lead alert to the operator. Returns True if actually sent."""
    if not email_configured():
        return False
    import smtplib
    import ssl
    from email.message import EmailMessage
    from email.utils import formataddr

    subject = f"🔔 عميل طلب تواصل — {name or 'بدون اسم'}"
    lines = [
        "عميل من موقع Homzy طلب إن حد من المبيعات يتواصل معاه:",
        "",
        f"الاسم: {name or '-'}",
        f"الموبايل: {phone or '-'}",
        f"الإيميل: {email or '-'}",
    ]
    if context:
        lines.append(f"مهتم بـ: {context}")
    if message:
        lines.append(f"آخر رسالة: {message}")
    lines += ["", "— تنبيه تلقائي من مستشار Homzy"]
    body = "\n".join(lines)

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = formataddr(("Homzy", config.LEAD_NOTIFY_FROM or config.SMTP_USER))
    msg["To"] = config.LEAD_NOTIFY_TO
    if phone:
        msg["Reply-To"] = email or config.LEAD_NOTIFY_FROM or config.SMTP_USER
    msg.set_content(body)

    try:
        ctx = ssl.create_default_context()
        if config.SMTP_PORT == 465:
            with smtplib.SMTP_SSL(config.SMTP_HOST, config.SMTP_PORT, context=ctx, timeout=20) as s:
                s.login(config.SMTP_USER, config.SMTP_PASS)
                s.send_message(msg)
        else:
            with smtplib.SMTP(config.SMTP_HOST, config.SMTP_PORT, timeout=20) as s:
                s.starttls(context=ctx)
                s.login(config.SMTP_USER, config.SMTP_PASS)
                s.send_message(msg)
        return True
    except Exception:
        return False


def handle_lead_contact(token: str, context: str, message: str, lang: str) -> dict[str, Any]:
    """Verify the client, pull their registered name/phone, and email the operator."""
    user = verify_user(token)
    if not user or not user.get("id"):
        return {"ok": False, "error": "not_authenticated"}
    prof = get_profile(user["id"], token)
    name = (prof.get("full_name") or "").strip()
    phone = (prof.get("phone") or "").strip()
    email = (prof.get("email") or user.get("email") or "").strip()
    sent = send_lead_email(name, phone, email, context or "", message or "", lang or "ar")
    return {"ok": True, "emailed": sent, "name": name, "phone": phone}
