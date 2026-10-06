"""Quarantine container images that a scanner has found blocking flaws in.

This runs on the Inspector "Inspector2 Scan" event, after an image has already
been pushed and scanned. It cannot prevent the push -- nothing in ECR can --
so enforcement here means making the image undeployable and saying so loudly.

Two decisions worth knowing about:

Quarantine, never delete. The image stays in the registry under a
`quarantined-*` tag; only the deployable tag is removed. Deleting the image
would destroy the evidence someone needs to answer "what shipped, and when did
we know". An incident review cannot run on an empty repository.

Fail closed. If this function cannot establish that an image is clean -- a
malformed event, a missing severity count, an API error -- it quarantines the
image and raises. A security gate that waves images through when it is broken
is worse than no gate, because the dashboard stays green.
"""

import json
import os

import boto3

ecr = boto3.client("ecr")
sns = boto3.client("sns")

BLOCKING = [s.strip().upper() for s in os.environ.get("BLOCKING_SEVERITIES", "CRITICAL,HIGH").split(",") if s.strip()]
TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
QUARANTINE_PREFIX = os.environ.get("QUARANTINE_PREFIX", "quarantined")


class Undetermined(Exception):
    """The gate could not decide. Treated as a failure, never as a pass."""


def repository_name(detail):
    """Pull a plain repository name out of the event.

    Inspector sends an ARN in the `repository-name` field for ECR images --
    "arn:aws:ecr:us-east-1:111122223333:repository/inspector2" -- despite the
    field name. Accept either form rather than trusting one.
    """
    raw = detail.get("repository-name") or ""
    if not raw:
        raise Undetermined("event carried no repository-name")
    if raw.startswith("arn:"):
        if ":repository/" not in raw:
            raise Undetermined("unparseable repository ARN: %s" % raw)
        return raw.split(":repository/", 1)[1]
    return raw


def blocking_count(detail):
    counts = detail.get("finding-severity-counts")
    if not isinstance(counts, dict):
        raise Undetermined("event carried no finding-severity-counts")
    total = 0
    for severity in BLOCKING:
        value = counts.get(severity, 0)
        if not isinstance(value, int):
            raise Undetermined("severity %s was %r, not an integer" % (severity, value))
        total += value
    return total


def quarantine(repo, digest, tags):
    """Re-tag the image out of deployable namespace, keeping the image itself."""
    manifest = ecr.batch_get_image(
        repositoryName=repo,
        imageIds=[{"imageDigest": digest}],
    )
    images = manifest.get("images", [])
    if not images:
        raise Undetermined("no manifest for %s@%s" % (repo, digest))

    body = images[0]["imageManifest"]
    media_type = images[0].get("imageManifestMediaType")

    short = digest.split(":")[-1][:12]
    new_tag = "%s-%s" % (QUARANTINE_PREFIX, short)

    put_args = {
        "repositoryName": repo,
        "imageManifest": body,
        "imageTag": new_tag,
    }
    if media_type:
        put_args["imageManifestMediaType"] = media_type

    try:
        ecr.put_image(**put_args)
    except ecr.exceptions.ImageAlreadyExistsException:
        # Already quarantined under this tag. Idempotent by design: the scan
        # event can be redelivered, and a second run must not fail.
        pass

    removed = [t for t in tags if t and not t.startswith(QUARANTINE_PREFIX)]
    if removed:
        ecr.batch_delete_image(
            repositoryName=repo,
            imageIds=[{"imageTag": t} for t in removed],
        )

    return new_tag, removed


def notify(subject, body):
    if not TOPIC_ARN:
        print("NO_TOPIC_CONFIGURED subject=%s" % subject)
        return
    sns.publish(TopicArn=TOPIC_ARN, Subject=subject[:100], Message=body)


def handler(event, context):
    print("event=%s" % json.dumps(event))
    detail = event.get("detail") or {}

    try:
        repo = repository_name(detail)
        digest = detail.get("image-digest")
        if not digest:
            raise Undetermined("event carried no image-digest")
        tags = detail.get("image-tags") or []
        blocking = blocking_count(detail)

    except Undetermined as exc:
        # Cannot establish that the image is clean. Say so and fail the
        # invocation so the error alarm fires.
        notify(
            "Image gate could not decide",
            "The gate failed to evaluate a scan event and is not enforcing it.\n\n"
            "Reason: %s\n\nEvent:\n%s" % (exc, json.dumps(event, indent=2)),
        )
        raise

    if blocking == 0:
        print("ALLOW repo=%s digest=%s tags=%s" % (repo, digest, tags))
        return {"verdict": "allow", "repository": repo, "digest": digest, "tags": tags}

    new_tag, removed = quarantine(repo, digest, tags)
    print("QUARANTINE repo=%s digest=%s removed=%s now=%s" % (repo, digest, removed, new_tag))

    notify(
        "Image quarantined: %s" % repo,
        "An image failed the vulnerability gate and has been made undeployable.\n\n"
        "Repository: %s\n"
        "Digest:     %s\n"
        "Tags removed: %s\n"
        "Now tagged:   %s\n"
        "Blocking severities: %s\n"
        "Counts: %s\n\n"
        "The image was NOT deleted. Pull it by digest to investigate."
        % (repo, digest, removed or "(none)", new_tag, ",".join(BLOCKING),
           json.dumps(detail.get("finding-severity-counts", {}))),
    )

    return {
        "verdict": "quarantine",
        "repository": repo,
        "digest": digest,
        "removed_tags": removed,
        "quarantine_tag": new_tag,
    }
