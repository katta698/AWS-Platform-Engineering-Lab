"""
create_webhook_integration.py — creates the Week 9 ServiceNow-side wiring
(Outbound REST Message, Catalog Item + variables, Business Rule, webhook
secret as a sys_properties record) via the Table API, instead of clicking
through the ServiceNow UI by hand.

Credentials come from a repo-root .servicenow.env file (gitignored) — never
hardcode SNOW_USERNAME/SNOW_PASSWORD here. See .servicenow.env.example.

Run with the API Gateway URL as an argument:
    python create_webhook_integration.py https://xxxx.execute-api.us-east-1.amazonaws.com/dev/webhook

This is idempotent-ish: re-running will create duplicate records if the
names already exist (ServiceNow's Table API does not upsert by name). Check
the instance first if re-running after a partial failure.
"""
import json
import os
import sys
from pathlib import Path

import requests

REPO_ROOT = Path(__file__).resolve().parents[3]  # .../AWS-Platform-Engineering-Lab
ENV_FILE = REPO_ROOT / ".servicenow.env"

PROJECT_LABEL = "ECS Fargate Self-Service"
CAT_ITEM_NAME = "ECS Fargate Self-Service"
REST_MESSAGE_NAME = "AWS Fargate Self-Service"
BUSINESS_RULE_NAME = "Trigger Fargate Provisioning"
# Shared across every ServiceNow-driven week (webhook_secret is already
# shared in the HCP variable set) — set this system property's value ONCE,
# ever. Do not namespace this per-week; every future week's script should
# reuse this exact same name so the manual "set the secret" step in
# ServiceNow only ever has to happen one time.
WEBHOOK_SECRET_PROPERTY = "x_platform_lab.webhook_secret"
DEFAULT_CATALOG_NAME = "Service Catalog"

CATALOG_VARIABLES = [
    ("service_name", "Service Name (lowercase, hyphens only)", True),
    ("image_uri", "Image URI", True),
    ("container_port", "Container Port", True),
    ("cpu", "CPU Units (256/512/1024/2048/4096)", True),
    ("memory", "Memory in MiB", True),
    ("desired_count", "Desired Task Count", True),
]


def load_env(path: Path) -> dict:
    if not path.exists():
        sys.exit(
            f"Missing {path}\n"
            f"Copy .servicenow.env.example to .servicenow.env at the repo root "
            f"and fill in real values first."
        )
    values = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        values[key.strip()] = val.strip()
    placeholders = {"SNOW_INSTANCE": "devXXXXXX", "SNOW_USERNAME": "your-servicenow-admin-or-service-account", "SNOW_PASSWORD": "your-servicenow-password"}
    for required in ("SNOW_INSTANCE", "SNOW_USERNAME", "SNOW_PASSWORD"):
        if required not in values or not values[required] or values[required] == placeholders[required]:
            sys.exit(f"{required} looks unset/placeholder in {path} — fill in a real value.")
    return values


class ServiceNowClient:
    def __init__(self, instance: str, username: str, password: str):
        self.base_url = f"https://{instance}.service-now.com/api/now/table"
        self.session = requests.Session()
        self.session.auth = (username, password)
        self.session.headers.update({"Content-Type": "application/json", "Accept": "application/json"})

    def create(self, table: str, fields: dict) -> dict:
        resp = self.session.post(f"{self.base_url}/{table}", data=json.dumps(fields))
        if resp.status_code not in (200, 201):
            raise RuntimeError(f"POST {table} failed [{resp.status_code}]: {resp.text}")
        return resp.json()["result"]

    def find_one(self, table: str, query: str) -> dict | None:
        resp = self.session.get(f"{self.base_url}/{table}", params={"sysparm_query": query, "sysparm_limit": "1"})
        if resp.status_code != 200:
            raise RuntimeError(f"GET {table} failed [{resp.status_code}]: {resp.text}")
        results = resp.json()["result"]
        return results[0] if results else None


def main():
    if len(sys.argv) != 2:
        sys.exit("Usage: python create_webhook_integration.py <api_gateway_url>")
    api_url = sys.argv[1]

    env = load_env(ENV_FILE)
    sn = ServiceNowClient(env["SNOW_INSTANCE"], env["SNOW_USERNAME"], env["SNOW_PASSWORD"])

    print("=== 1. Webhook secret as a password-type system property ===")
    print(f"      Shared across every ServiceNow-driven week — only created")
    print(f"      once, ever. If it already exists this step is skipped.")
    existing_prop = sn.find_one("sys_properties", f"name={WEBHOOK_SECRET_PROPERTY}")
    if existing_prop:
        print(f"  Already exists: {WEBHOOK_SECRET_PROPERTY} (sys_id {existing_prop['sys_id']}) — skipping creation")
    else:
        print(f"NOTE: this creates the PROPERTY only — you still set its value")
        print(f"      yourself in ServiceNow (System Properties UI), same rule as")
        print(f"      every other secret in this project: never entered by the script.")
        prop = sn.create("sys_properties", {
            "name": WEBHOOK_SECRET_PROPERTY,
            "type": "password2",
            "value": "REPLACE_ME_IN_SERVICENOW_UI",
            "description": "HMAC-SHA256 secret shared with every AWS webhook_receiver Lambda across all weeks",
        })
        print(f"  Created sys_properties: {prop['name']} (sys_id {prop['sys_id']})")

    print("\n=== 2. Outbound REST Message ===")
    rest_message = sn.create("sys_rest_message", {
        "name": REST_MESSAGE_NAME,
        "rest_endpoint": api_url,
        "description": f"Webhook target for {PROJECT_LABEL}",
    })
    print(f"  Created sys_rest_message: {rest_message['name']} (sys_id {rest_message['sys_id']})")

    # The method's identifying field is `function_name`, NOT `name` — using
    # `name` here silently no-ops (Table API ignores unknown field keys
    # rather than erroring), leaving function_name blank. Confirmed via a
    # real "REST message/method ... not found" error on Week 9 (2026-07-12):
    # sn_ws.RESTMessageV2(message_name, method_name) looks up by
    # function_name, so a blank one makes the method unfindable at runtime.
    rest_fn = sn.create("sys_rest_message_fn", {
        "rest_message": rest_message["sys_id"],
        "function_name": "provision",
        "http_method": "POST",
        "content_type": "application/json",
    })
    print(f"  Created sys_rest_message_fn: provision (sys_id {rest_fn['sys_id']})")

    print("\n=== 3. Service Catalog Item ===")
    catalog = sn.find_one("sc_catalog", f"title={DEFAULT_CATALOG_NAME}")
    catalog_fields = {"sc_catalogs": catalog["sys_id"]} if catalog else {}
    if not catalog:
        print(f"  WARNING: catalog '{DEFAULT_CATALOG_NAME}' not found — creating item without "
              f"a Catalogs assignment. Set it manually in Catalog Builder or it won't appear "
              f"in the portal (same gotcha Week 2's manual setup hit).")

    cat_item = sn.create("sc_cat_item", {
        "name": CAT_ITEM_NAME,
        "short_description": "Deploy a containerized service on ECS Fargate — self-service, no manual AWS console work",
        "active": "true",
        **catalog_fields,
    })
    print(f"  Created sc_cat_item: {cat_item['name']} (sys_id {cat_item['sys_id']})")
    if catalog:
        print(f"  Set Catalogs = '{DEFAULT_CATALOG_NAME}' directly ({catalog['sys_id']}) at "
              f"creation time. NOT YET CONFIRMED whether setting this field via the API on "
              f"create produces the same sc_cat_item_catalog join-table sync that saving it "
              f"through the UI form does (only the UI path has been observed so far). Check "
              f"the portal after this runs — if the item isn't visible, open it in Catalog "
              f"Builder and re-save the Catalogs field manually once, then report back so "
              f"this note can be corrected either way.")

    for order, (name, label, mandatory) in enumerate(CATALOG_VARIABLES, start=1):
        var = sn.create("item_option_new", {
            "cat_item": cat_item["sys_id"],
            "name": name,
            "question_text": label,
            "type": "6",  # Single Line Text — see script docstring for why
            "mandatory": "true" if mandatory else "false",
            "order": str(order * 100),
        })
        print(f"  Created variable: {name} (sys_id {var['sys_id']})")

    print("\n=== 4. Business Rule (with HMAC-SHA256 signing) ===")
    script = f"""(function executeRule(current, previous) {{
  try {{
    var body = JSON.stringify({{
      ticket_id:      current.number.toString(),
      ticket_sys_id:  current.sys_id.toString(),
      service_name:   current.variables.service_name.toString(),
      image_uri:      current.variables.image_uri.toString(),
      container_port: parseInt(current.variables.container_port.toString()),
      cpu:            parseInt(current.variables.cpu.toString()),
      memory:         parseInt(current.variables.memory.toString()),
      desired_count:  parseInt(current.variables.desired_count.toString())
    }});

    var secret = gs.getProperty('{WEBHOOK_SECRET_PROPERTY}');

    var mac = new GlideCertificateEncryption();
    var keyBase64 = GlideStringUtil.base64Encode(secret);
    var macBase64 = mac.generateMac(keyBase64, 'HmacSHA256', body);
    var macBytes  = GlideStringUtil.base64DecodeAsBytes(macBase64);

    // HexUtil.convertByteArrayToHex() is NOT available in this scripting
    // context despite being documented that way in ServiceNow community
    // posts — confirmed via a real "HexUtil is not defined" error on Week 9
    // (2026-07-12). Plain-JS conversion instead, no platform-specific class.
    var macHex = '';
    for (var i = 0; i < macBytes.length; i++) {{
      var b = macBytes[i] & 0xFF;
      macHex += (b < 16 ? '0' : '') + b.toString(16);
    }}
    var signature = 'sha256=' + macHex;

    var r = new sn_ws.RESTMessageV2('{REST_MESSAGE_NAME}', 'provision');
    r.setRequestBody(body);
    r.setRequestHeader('x-servicenow-hmac', signature);
    var response = r.execute();
    gs.info('Fargate provisioning triggered: ' + response.getStatusCode());
  }} catch (ex) {{
    gs.error('Fargate provisioning failed: ' + ex.message);
  }}
}})(current, previous);"""

    rule = sn.create("sys_script", {
        "name": BUSINESS_RULE_NAME,
        "collection": "sc_req_item",
        "when": "after",
        "action_insert": "true",
        "action_update": "false",
        "condition": f"current.cat_item.name == '{CAT_ITEM_NAME}'",
        "script": script,
        "active": "true",
    })
    print(f"  Created sys_script (Business Rule): {rule['name']} (sys_id {rule['sys_id']})")

    print("\n=== Done ===")
    print("Manual steps still required in the ServiceNow UI:")
    print(f"  1. Set the real secret value on system property '{WEBHOOK_SECRET_PROPERTY}'")
    print(f"     (must match the webhook_secret value in the HCP variable set)")
    print(f"  2. Set the Catalog Item's 'Catalogs' field so it's visible in the portal")
    print(f"  3. Publish the catalog item (Catalog Builder -> Publish)")


if __name__ == "__main__":
    main()
