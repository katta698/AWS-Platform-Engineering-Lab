#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/userdata.log | logger -t userdata -s 2>/dev/console) 2>&1

echo "=== Starting userdata for ${project}-${environment} ==="

# ── OS Hardening ──────────────────────────────────────────────────────────────
yum update -y
yum install -y amazon-cloudwatch-agent amazon-ssm-agent

# Enable SSM agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# ── CloudWatch Agent Config ───────────────────────────────────────────────────
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/*.log",
            "log_group_name": "/app/${project}-${environment}",
            "log_stream_name": "{instance_id}/app",
            "retention_in_days": 30
          },
          {
            "file_path": "/var/log/userdata.log",
            "log_group_name": "/app/${project}-${environment}",
            "log_stream_name": "{instance_id}/userdata"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "${project}/${environment}",
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["disk_used_percent"], "resources": ["/"] }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# ── Sample app (replace with real app deployment) ─────────────────────────────
mkdir -p /var/log/app
cat > /usr/local/bin/healthcheck.py <<'PYAPP'
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
import json, platform

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "status": "healthy",
                "environment": "${environment}",
                "project": "${project}"
            }).encode())
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, format, *args):
        pass

HTTPServer(("0.0.0.0", ${app_port}), Handler).serve_forever()
PYAPP

chmod +x /usr/local/bin/healthcheck.py
python3 /usr/local/bin/healthcheck.py &

echo "=== Userdata complete for ${project}-${environment} ==="
