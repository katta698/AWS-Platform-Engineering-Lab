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

REPO_ROOT = Path(__file__).resolve().parents[2]  # .../AWS-Platform-Engineering-Lab
ENV_FILE = REPO_ROOT / ".servicenow.env"

PROJECT_LABEL = "ECS Fargate Self-Service"
CAT_ITEM_NAME = "ECS Fargate Self-Service"
REST_MESSAGE_NAME = "AWS Fargate Self-Service"
BUSINESS_RULE_NAME = "Trigger Fargate Provisioning"
WEBHOOK_SECRET_PROPERTY = "x_fargate.webhook_secret"

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
    for required in ("SNOW_INSTANCE", "SNOW_USERNAME", "SNOW_PASSWORD"):
        if required not in values or not values[required] or values[required].startswith("your-") or values[required].startswith("dev"):
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


def main():
    if len(sys.argv) != 2:
        sys.exit("Usage: python create_webhook_integration.py <api_gateway_url>")
    api_url = sys.argv[1]

    env = load_env(ENV_FILE)
    sn = ServiceNowClient(env["SNOW_INSTANCE"], env["SNOW_USERNAME"], env["SNOW_PASSWORD"])

    print("=== 1. Webhook secret as a password-type system property ===")
    print(f"NOTE: this creates the PROPERTY only — you still set its value")
    print(f"      yourself in ServiceNow (System Properties UI), same rule as")
    print(f"      every other secret in this project: never entered by the script.")
    prop = sn.create("sys_properties", {
        "name": WEBHOOK_SECRET_PROPERTY,
        "type": "password2",
        "value": "REPLACE_ME_IN_SERVICENOW_UI",
        "description": "HMAC-SHA256 secret shared with the AWS webhook_receiver Lambda for Week 9",
    })
    print(f"  Created sys_properties: {prop['name']} (sys_id {prop['sys_id']})")

    print("\n=== 2. Outbound REST Message ===")
    rest_message = sn.create("sys_rest_message", {
        "name": REST_MESSAGE_NAME,
        "rest_endpoint": api_url,
        "description": f"Webhook target for {PROJECT_LABEL}",
    })
    print(f"  Created sys_rest_message: {rest_message['name']} (sys_id {rest_message['sys_id']})")

    rest_fn = sn.create("sys_rest_message_fn", {
        "rest_message": rest_message["sys_id"],
        "name": "provision",
        "http_method": "POST",
        "content_type": "application/json",
    })
    print(f"  Created sys_rest_message_fn: provision (sys_id {rest_fn['sys_id']})")

    print("\n=== 3. Service Catalog Item ===")
    cat_item = sn.create("sc_cat_item", {
        "name": CAT_ITEM_NAME,
        "short_description": "Deploy a containerized service on ECS Fargate — self-service, no manual AWS console work",
        "active": "true",
    })
    print(f"  Created sc_cat_item: {cat_item['name']} (sys_id {cat_item['sys_id']})")
    print("  NOTE: 'Catalogs' field (which catalog it appears in) isn't set by "
          "this script — Week 2's manual setup found this defaults to empty and "
          "the item won't appear in the portal until it's set. Set it yourself "
          "in Catalog Builder after this runs.")

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
    var macHex    = HexUtil.convertByteArrayToHex(macBytes).toLowerCase();
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
