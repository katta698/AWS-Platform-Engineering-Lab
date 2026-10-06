# Deliberately vulnerable at the OS layer.
#
# Ubuntu 20.04 reached end of standard support in May 2025, so its packages
# carry published CVEs that nobody is shipping fixes for. This is the image
# the gate is expected to quarantine.
#
# Worth knowing: ECR's free basic scanning would also find these. OS-package
# findings are not what enhanced scanning is for -- see ../vuln-lib.
FROM public.ecr.aws/docker/library/ubuntu@sha256:8feb4d8ca5354def3d8fce243717141ce31e2c428701f6682bd2fafe15388214

LABEL org.opencontainers.image.title="wk22-vuln-os"
LABEL org.opencontainers.image.description="End-of-life base. Expected to be quarantined on OS-package findings."

CMD ["/bin/sh", "-c", "echo wk22-vuln-os; sleep 3600"]
