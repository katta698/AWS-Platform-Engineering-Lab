"""
secret_rotation — Week 2: Aurora Self-Service Platform

Rotates per-tenant Aurora PostgreSQL credentials.
Implements the 4-step Secrets Manager rotation protocol:
  createSecret → setSecret → testSecret → finishSecret

The 4-step protocol guarantees zero-downtime rotation:
  1. createSecret  — generate new password, store as AWSPENDING
  2. setSecret     — update PostgreSQL user password to match AWSPENDING
  3. testSecret    — verify AWSPENDING credentials can connect
  4. finishSecret  — promote AWSPENDING to AWSCURRENT
"""
import json
import logging
import os
import secrets
import string
import boto3
import pg8000.native

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sm = boto3.client("secretsmanager")


def generate_password(length: int = 24) -> str:
    alphabet = string.ascii_letters + string.digits + "!#$%^&*"
    pwd = (
        secrets.choice(string.ascii_uppercase)
        + secrets.choice(string.ascii_lowercase)
        + secrets.choice(string.digits)
        + secrets.choice("!#$%^&*")
        + "".join(secrets.choice(alphabet) for _ in range(length - 4))
    )
    return "".join(secrets.SystemRandom().sample(pwd, len(pwd)))


def get_secret(secret_id: str, stage: str = "AWSCURRENT") -> dict:
    resp = sm.get_secret_value(SecretId=secret_id, VersionStage=stage)
    return json.loads(resp["SecretString"])


def connect(creds: dict):
    return pg8000.native.Connection(
        user=creds["username"],
        password=creds["password"],
        host=creds["host"],
        port=int(creds.get("port", 5432)),
        database=creds.get("dbname", "postgres"),
        ssl_context=True,
    )


# ── Step 1: createSecret ──────────────────────────────────────────────────────
def create_secret(secret_id: str, token: str):
    """Generate a new password and store it as AWSPENDING."""
    # Check if AWSPENDING already exists (retry-safe)
    metadata = sm.describe_secret(SecretId=secret_id)
    versions = metadata.get("VersionIdsToStages", {})
    for v_id, stages in versions.items():
        if "AWSPENDING" in stages and v_id == token:
            logger.info("AWSPENDING already set for this token — skipping createSecret")
            return

    current = get_secret(secret_id, "AWSCURRENT")
    new_password = generate_password()

    sm.put_secret_value(
        SecretId=secret_id,
        ClientRequestToken=token,
        SecretString=json.dumps({**current, "password": new_password}),
        VersionStages=["AWSPENDING"],
    )
    logger.info("createSecret: new AWSPENDING version stored")


# ── Step 2: setSecret ─────────────────────────────────────────────────────────
def set_secret(secret_id: str, token: str):
    """Apply the AWSPENDING password to the PostgreSQL user."""
    pending = get_secret(secret_id, "AWSPENDING")
    current = get_secret(secret_id, "AWSCURRENT")

    if pending["password"] == current["password"]:
        logger.info("setSecret: AWSPENDING == AWSCURRENT — already set")
        return

    # Connect as master or current user to change the password
    # For tenant secrets, we need to use master credentials to ALTER USER
    # Master secret path: replace /db/<dbname> with /aurora/master
    master_secret_id = secret_id.rsplit("/db/", 1)[0] + "/aurora/master"
    try:
        master_creds = get_secret(master_secret_id)
        conn = connect({**master_creds, "dbname": "postgres"})
    except Exception:
        # Fall back to current credentials if master not accessible
        logger.warning("setSecret: master secret not accessible, using current creds")
        conn = connect(current)

    conn.autocommit = True
    try:
        username = pending["username"]
        new_pwd  = pending["password"]
        conn.run(f"ALTER USER \"{username}\" WITH PASSWORD '{new_pwd}'")
        logger.info(f"setSecret: password updated for user {username}")
    finally:
        conn.close()


# ── Step 3: testSecret ────────────────────────────────────────────────────────
def test_secret(secret_id: str, token: str):
    """Verify AWSPENDING credentials can connect and query."""
    pending = get_secret(secret_id, "AWSPENDING")
    try:
        conn = connect(pending)
        conn.run("SELECT 1")
        conn.close()
        logger.info("testSecret: AWSPENDING credentials verified ✓")
    except Exception as e:
        logger.error(f"testSecret: AWSPENDING credentials FAILED: {e}")
        raise


# ── Step 4: finishSecret ──────────────────────────────────────────────────────
def finish_secret(secret_id: str, token: str):
    """Promote AWSPENDING to AWSCURRENT."""
    metadata = sm.describe_secret(SecretId=secret_id)
    current_version = next(
        v for v, stages in metadata["VersionIdsToStages"].items()
        if "AWSCURRENT" in stages
    )

    if current_version == token:
        logger.info("finishSecret: already AWSCURRENT — skipping")
        return

    sm.update_secret_version_stage(
        SecretId=secret_id,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )
    logger.info("finishSecret: AWSPENDING promoted to AWSCURRENT ✓")


# ── Entry Point ───────────────────────────────────────────────────────────────
def lambda_handler(event, context):
    secret_id = event["SecretId"]
    token     = event["ClientRequestToken"]
    step      = event["Step"]

    logger.info(f"Rotation step: {step} | secret: {secret_id}")

    # Verify rotation is enabled on this secret
    metadata = sm.describe_secret(SecretId=secret_id)
    if not metadata.get("RotationEnabled"):
        raise ValueError(f"Secret {secret_id} does not have rotation enabled")

    if step == "createSecret":
        create_secret(secret_id, token)
    elif step == "setSecret":
        set_secret(secret_id, token)
    elif step == "testSecret":
        test_secret(secret_id, token)
    elif step == "finishSecret":
        finish_secret(secret_id, token)
    else:
        raise ValueError(f"Unknown rotation step: {step}")
