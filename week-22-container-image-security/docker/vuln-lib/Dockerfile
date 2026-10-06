# Deliberately vulnerable at the LANGUAGE layer, and clean at the OS layer.
#
# This is the image that justifies paying for Amazon Inspector. ECR's free
# basic scanner reads OS packages only; it cannot see an outdated pip, npm or
# Maven dependency. Enhanced scanning reads requirements.txt and finds it.
#
# The base is deliberately current -- an end-of-life Python would also produce
# OS findings and the experiment would no longer isolate one variable.
FROM public.ecr.aws/docker/library/python@sha256:3dd7cc108ec1493442514f5c2a871af6af0ec31d768ff6e378a93340c3b3db5f

LABEL org.opencontainers.image.title="wk22-vuln-lib"
LABEL org.opencontainers.image.description="Current base, outdated Flask. Expected to be quarantined on a language-package finding."

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN useradd --create-home --shell /bin/bash app
USER app

CMD ["python", "-c", "import flask; print('wk22-vuln-lib flask', flask.__version__)"]
