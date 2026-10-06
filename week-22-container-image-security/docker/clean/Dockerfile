# The happy path: a current, minimal base with nothing added.
#
# Pinned by digest, not by tag. "alpine:3.22" is whatever was published this
# morning, so a tag-pinned lab produces different scan results on a rerun and
# the blog post stops being reproducible. The digest below was resolved on
# 2026-10-06 and will not move.
FROM public.ecr.aws/docker/library/alpine@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8

LABEL org.opencontainers.image.title="wk22-clean"
LABEL org.opencontainers.image.description="Current base, no added packages. Expected to pass the gate."

# Not root. Nothing here needs it, and a scanner finding is not the only thing
# that makes an image unsafe to run.
RUN addgroup -S app && adduser -S -G app app
USER app

CMD ["/bin/sh", "-c", "echo wk22-clean; sleep 3600"]
