#!/usr/bin/env bash
###############################################################################
# build_layer.sh — Build and publish the pg8000 Lambda layer
# pg8000 is pure Python so this works on any OS — no Docker needed
# Usage: sh scripts/build_layer.sh [region] [account_id]
###############################################################################
set -euo pipefail

REGION="${1:-us-east-1}"
ACCOUNT_ID="${2:-$(aws sts get-caller-identity --query Account --output text)}"
LAYER_NAME="pg8000-python12"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/tmp/pg8000-layer"
PYTHON_VERSION="3.12"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${YELLOW}▶  Building pg8000 Lambda layer...${NC}"

# Clean build dir
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/python"

# Install pg8000 into layer directory
pip install pg8000 --target "$BUILD_DIR/python" --quiet --break-system-packages 2>/dev/null || \
pip install pg8000 --target "$BUILD_DIR/python" --quiet

echo "   Installed packages:"
ls "$BUILD_DIR/python" | head -10

# Zip the layer (use Python since zip is not available on Windows Git Bash)
cd "$BUILD_DIR"
python -c "
import zipfile, os
with zipfile.ZipFile('layer.zip', 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk('python'):
        for f in files:
            path = os.path.join(root, f)
            z.write(path)
print('   Layer zip created')
"
echo "   Layer zip size: $(du -sh layer.zip | cut -f1)"

# Publish layer to AWS Lambda
echo ""
echo -e "${YELLOW}▶  Publishing layer to AWS Lambda...${NC}"
LAYER_ARN=$(aws lambda publish-layer-version \
  --layer-name "$LAYER_NAME" \
  --description "pg8000 PostgreSQL driver for Python 3.12" \
  --zip-file fileb://layer.zip \
  --compatible-runtimes python3.12 \
  --region "$REGION" \
  --query "LayerVersionArn" \
  --output text)

echo ""
echo -e "${GREEN}✅ Layer published!${NC}"
echo ""
echo "Layer ARN: $LAYER_ARN"
echo ""
echo "Add this to your terraform.tfvars:"
echo "  pg8000_layer_arn = \"$LAYER_ARN\""
echo ""
echo "Add this as a GitHub Secret:"
echo "  PG8000_LAYER_ARN = $LAYER_ARN"
