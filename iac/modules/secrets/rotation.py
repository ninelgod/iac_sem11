"""
Minimal Aurora PostgreSQL single-user secret rotation handler.
Replace with the AWS SAR managed version for production:
  arn:aws:serverlessrepo:us-east-1:297356227824:applications/SecretsManagerRDSPostgreSQLRotationSingleUser
"""
import boto3
import json
import logging
import os
import psycopg2

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    client = boto3.client("secretsmanager")
    metadata = client.describe_secret(SecretId=arn)

    if not metadata["RotationEnabled"]:
        raise ValueError(f"Secret {arn} is not enabled for rotation")

    versions = metadata.get("VersionIdsToStages", {})
    if token not in versions:
        raise ValueError(f"Secret version {token} has no stage for secret {arn}")

    if "AWSCURRENT" in versions[token]:
        logger.info("Version %s is already AWSCURRENT — nothing to do", token)
        return
    if "AWSPENDING" not in versions[token]:
        raise ValueError(f"Version {token} is not AWSPENDING for {arn}")

    if step == "createSecret":
        _create_secret(client, arn, token)
    elif step == "setSecret":
        _set_secret(client, arn, token)
    elif step == "testSecret":
        _test_secret(client, arn, token)
    elif step == "finishSecret":
        _finish_secret(client, arn, token)
    else:
        raise ValueError(f"Invalid step: {step}")


def _get_secret(client, arn, stage, token=None):
    kwargs = {"SecretId": arn, "VersionStage": stage}
    if token:
        kwargs["VersionId"] = token
    return json.loads(client.get_secret_value(**kwargs)["SecretString"])


def _create_secret(client, arn, token):
    try:
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")
        logger.info("AWSPENDING already exists — skipping createSecret")
        return
    except client.exceptions.ResourceNotFoundException:
        pass

    current = _get_secret(client, arn, "AWSCURRENT")
    import secrets as _secrets
    import string
    alphabet = string.ascii_letters + string.digits + "!#$%&*()-_=+[]{}<>:?"
    new_password = "".join(_secrets.choice(alphabet) for _ in range(32))
    current["password"] = new_password
    client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(current),
        VersionStages=["AWSPENDING"],
    )
    logger.info("Created AWSPENDING secret version")


def _set_secret(client, arn, token):
    pending = _get_secret(client, arn, "AWSPENDING", token)
    current = _get_secret(client, arn, "AWSCURRENT")
    host = os.environ.get("DB_HOST", pending.get("host", ""))
    conn = psycopg2.connect(
        host=host, dbname=pending["dbname"],
        user=current["username"], password=current["password"],
        sslmode="require",
    )
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute(
            "ALTER USER %s WITH PASSWORD %%s" % pending["username"],
            (pending["password"],),
        )
    conn.close()
    logger.info("Password updated in Aurora")


def _test_secret(client, arn, token):
    pending = _get_secret(client, arn, "AWSPENDING", token)
    host = os.environ.get("DB_HOST", pending.get("host", ""))
    conn = psycopg2.connect(
        host=host, dbname=pending["dbname"],
        user=pending["username"], password=pending["password"],
        sslmode="require",
    )
    conn.close()
    logger.info("AWSPENDING credentials verified successfully")


def _finish_secret(client, arn, token):
    metadata = client.describe_secret(SecretId=arn)
    current_version = next(
        v for v, stages in metadata["VersionIdsToStages"].items()
        if "AWSCURRENT" in stages
    )
    if current_version == token:
        logger.info("Version %s is already AWSCURRENT", token)
        return
    client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )
    logger.info("Rotated secret to version %s", token)
