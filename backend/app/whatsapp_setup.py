"""Read-only credential/template verification. Does not send a WhatsApp message."""
import re
import httpx
from dotenv import set_key
from app.reminders import settings, GRAPH_HOST


async def verify_whatsapp(values, client=None):
    config = settings(values)
    if config is None:
        raise ValueError("Check sender ID, business account ID, token, approved template, language, and reminder time.")
    if client is None:
        async with httpx.AsyncClient(timeout=15) as c:
            return await verify_whatsapp(values, c)
    base = f"{GRAPH_HOST}/{config['WHATSAPP_API_VERSION']}"
    headers = {"Authorization": "Bearer " + config["WHATSAPP_ACCESS_TOKEN"]}
    response = await client.get(f"{base}/{config['WHATSAPP_WABA_ID']}/phone_numbers",
        headers=headers, params={"fields": "id", "limit": "100"})
    if response.status_code != 200 or not any(str(p.get("id")) == config["WHATSAPP_PHONE_NUMBER_ID"] for p in response.json().get("data", [])):
        raise ValueError("Could not verify that the sender belongs to this WhatsApp business account. Check credentials and permissions.")
    response = await client.get(f"{base}/{config['WHATSAPP_WABA_ID']}/message_templates", headers=headers,
        params={"name": config["WHATSAPP_TEMPLATE_NAME"], "fields": "name,language,status,components,parameter_format", "limit": "100"})
    if response.status_code != 200:
        raise ValueError("Could not inspect reminder templates. The token needs WhatsApp business-management permission.")
    template = next((t for t in response.json().get("data", []) if t.get("name") == config["WHATSAPP_TEMPLATE_NAME"]
        and t.get("language") == config["WHATSAPP_TEMPLATE_LANGUAGE"] and t.get("status") == "APPROVED"), None)
    if template is None:
        raise ValueError("The selected template/language is not APPROVED yet. Complete approval in WhatsApp Manager first.")
    components = template.get("components", [])
    body = next((c.get("text", "") for c in components if c.get("type") == "BODY"), "")
    if template.get("parameter_format") == "NAMED" or set(re.findall(r"{{\s*(.*?)\s*}}", body)) != {"1", "2"}:
        raise ValueError("Use a positional body template with exactly {{1}} = class title and {{2}} = class date/time.")
    for component in components:
        if component.get("type") == "HEADER" and (component.get("format") != "TEXT" or "{{" in component.get("text", "")):
            raise ValueError("The reminder template cannot require a dynamic/media header.")
        if any("{{" in button.get("url", "") for button in component.get("buttons", [])):
            raise ValueError("Use a static website button, without dynamic URL parameters.")
    return config


def save_whatsapp(path, values):
    if not path.exists():
        raise ValueError("Run local setup first.")
    keys = ["WHATSAPP_PHONE_NUMBER_ID", "WHATSAPP_WABA_ID", "WHATSAPP_ACCESS_TOKEN", "WHATSAPP_TEMPLATE_NAME",
        "WHATSAPP_TEMPLATE_LANGUAGE", "WHATSAPP_API_VERSION", "WHATSAPP_APP_SECRET", "WHATSAPP_VERIFY_TOKEN",
        "REMINDER_MINUTES", "REMINDER_TIMEZONE"]
    for key in keys:
        if any(c in str(values.get(key, "")) for c in ("\n", "\r", "\x00")):
            raise ValueError("Enter each value on one line.")
    path.chmod(0o600)
    for key in keys:
        set_key(str(path), key, str(values.get(key, "")))
