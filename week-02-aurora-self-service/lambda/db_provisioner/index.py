"""
db_provisioner — Week 2: Aurora Self-Service Platform

Creates a PostgreSQL database + dedicated user on the shared Aurora cluster.
Stores per-tenant credentials in Secrets Manager with auto-rotation enabled.

Multi-tenant pattern: database-per-tenant on shared cluster.
  - Unlimited databases (Aurora Serverless v2 scales with load)
  - Full isolation: each tenant has its own DB + user + secret
  - Zero-downtime rotation: Secrets Manager rotates each tenant independently
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

sm     = boto3.client("secretsmanager")
region = os.environ.get("AWS_REGION", "us-east-1")

MASTER_SECRET_ARN   = os.environ["MASTER_SECRET_ARN"]
ROTATION_LAMBDA_ARN = os.environ["ROTATION_LAMBDA_ARN"]
PROJECT             = os.environ["PROJECT"]
ENVIRONMENT         = os.environ["ENVIRONMENT"]
ROTATION_DAYS       = int(os.environ.get("ROTATION_DAYS", "30"))


def get_master_credentials() -> dict:
    resp = sm.get_secret_value(SecretId=MASTER_SECRET_ARN)
    return json.loads(resp["SecretString"])


def generate_password(length: int = 24) -> str:
    """Generate a strong password safe for PostgreSQL connection strings."""
    alphabet = string.ascii_letters + string.digits + "!#$%^&*"
    # Ensure at least one of each class
    pwd = (
        secrets.choice(string.ascii_uppercase)
        + secrets.choice(string.ascii_lowercase)
        + secrets.choice(string.digits)
        + secrets.choice("!#$%^&*")
        + "".join(secrets.choice(alphabet) for _ in range(length - 4))
    )
    return "".join(secrets.SystemRandom().sample(pwd, len(pwd)))


def provision_database(conn, db_name: str, username: str, password: str):
    """Create database, user, and grant privileges. Idempotent."""
    # pg8000 doesn't support transactions for CREATE DATABASE
    # so we run DDL outside transaction blocks

    # Check and create database
    existing = conn.run(
        "SELECT 1 FROM pg_database WHERE datname = :db",
        db=db_name,
    )
    if not existing:
        logger.info(f"Creating database: {db_name}")
        conn.run(f'CREATE DATABASE "{db_name}"')
    else:
        logger.info(f"Database {db_name} already exists — skipping create")

    # Check and create user
    user_exists = conn.run(
        "SELECT 1 FROM pg_roles WHERE rolname = :u",
        u=username,
    )
    if not user_exists:
        logger.info(f"Creating user: {username}")
        conn.run(
            f"CREATE USER \"{username}\" WITH PASSWORD '{password}' "
            f"CONNECTION LIMIT 50 VALID UNTIL 'infinity'"
        )
    else:
        logger.info(f"User {username} exists — updating password for rotation")
        conn.run(f"ALTER USER \"{username}\" WITH PASSWORD '{password}'")

    # Grant privileges
    conn.run(f'GRANT ALL PRIVILEGES ON DATABASE "{db_name}" TO "{username}"')
    conn.run(f'GRANT CONNECT ON DATABASE "{db_name}" TO "{username}"')

    logger.info(f"Provisioning complete: db={db_name}, user={username}")


def store_tenant_secret(db_name: str, username: str, password: str, host: str, port: int) -> str:
    """Store per-tenant credentials in Secrets Manager. Returns secret ARN."""
    secret_name = f"/{PROJECT}/{ENVIRONMENT}/db/{db_name}"
    secret_value = json.dumps({
        "engine":   "postgres",
        "host":     host,
        "port":     port,
        "dbname":   db_name,
        "username": username,
        "password": password,
    })

    try:
        # Try to create new secret
        resp = sm.create_secret(
            Name=secret_name,
            Description=f"Credentials for tenant database: {db_name}",
            SecretString=secret_value,
            Tags=[
                {"Key": "Project",     "Value": PROJECT},
                {"Key": "Environment", "Value": ENVIRONMENT},
                {"Key": "TenantDB",    "Value": db_name},
            ],
        )
        secret_arn = resp["ARN"]
        logger.info(f"Created secret: {secret_name}")
    except sm.exceptions.ResourceExistsException:
        # Secret exists — update it (re-provision scenario)
        resp = sm.put_secret_value(
            SecretId=secret_name,
            SecretString=secret_value,
        )
        secret_arn = sm.describe_secret(SecretId=secret_name)["ARN"]
        logger.info(f"Updated existing secret: {secret_name}")

    return secret_arn


def enable_rotation(secret_arn: str, db_name: str):
    """Enable 30-day auto-rotation on the per-tenant secret."""
    try:
        sm.rotate_secret(
            SecretId=secret_arn,
            RotationLambdaARN=ROTATION_LAMBDA_ARN,
            RotationRules={"AutomaticallyAfterDays": ROTATION_DAYS},
            RotateImmediately=False,  # Don't rotate immediately — just enable schedule
        )
        logger.info(f"Rotation enabled for secret: {db_name} ({ROTATION_DAYS}-day schedule)")
    except Exception as e:
        logger.warning(f"Could not enable rotation for {db_name}: {e}")
        # Non-fatal — credentials are still stored, rotation can be enabled manually


def lambda_handler(event, context):
    logger.info(f"Provisioning DB for ticket: {event.get('ticket_id')}")

    db_name    = event["db_name"]
    ticket_id  = event["ticket_id"]
    team       = event["team"]

    # Derive a deterministic username from db_name (max 63 chars in PG)
    username = f"{db_name[:55]}_user"

    try:
        creds = get_master_credentials()
    except Exception as e:
        logger.error(f"Failed to retrieve master credentials: {e}")
        raise

    password = generate_password()
    host     = creds["host"]
    port     = int(creds.get("port", 5432))

    # Connect to Aurora with master credentials
    try:
        conn = pg8000.native.Connection(
            user=creds["username"],
            password=creds["password"],
            host=host,
            port=port,
            database="postgres",  # Connect to default DB to create new ones
            ssl_context=True,     # Aurora requires SSL
        )
        conn.autocommit = True    # Required for CREATE DATABASE
    except Exception as e:
        logger.error(f"Failed to connect to Aurora: {e}")
        raise

    try:
        provision_database(conn, db_name, username, password)
    finally:
        conn.close()

    # Store credentials in Secrets Manager
    secret_arn = store_tenant_secret(db_name, username, password, host, port)

    # Enable rotation
    enable_rotation(secret_arn, db_name)

    return {
        "ticket_id":       ticket_id,
        "db_name":         db_name,
        "username":        username,
        "host":            host,
        "port":            port,
        "secret_arn":      secret_arn,
        "secret_name":     f"/{PROJECT}/{ENVIRONMENT}/db/{db_name}",
        "reader_endpoint": event.get("reader_endpoint", ""),
        "status":          "provisioned",
    }
