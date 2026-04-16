#!/bin/bash
# Nyquest Semantic Compression Stage - Setup
# Deploys Qwen 2.5 1.5B via Ollama for use as Nyquest semantic co-processor
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

OLLAMA_PORT=11434
MODEL="qwen2.5:1.5b-instruct"
NYQUEST_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo -e "${GREEN}=== Nyquest Semantic Compression Stage Setup ===${NC}"
echo ""

# Step 1: Check Ollama
echo -e "${YELLOW}[1/5] Checking Ollama...${NC}"
if command -v ollama &> /dev/null; then
    echo -e "  ${GREEN}Ollama found${NC}"
else
    echo -e "  ${RED}Installing Ollama...${NC}"
    curl -fsSL https://ollama.com/install.sh | sh
fi

if ! systemctl is-active --quiet ollama; then
    sudo systemctl start ollama
    sleep 2
fi
echo -e "  ${GREEN}Ollama service: active${NC}"

# Step 2: Pull Model
echo -e "${YELLOW}[2/5] Pulling ${MODEL}...${NC}"
if ollama list 2>/dev/null | grep -q "qwen2.5:1.5b-instruct"; then
    echo -e "  ${GREEN}Model already pulled${NC}"
else
    ollama pull "$MODEL"
fi

# Step 3: Configure VRAM persistence
echo -e "${YELLOW}[3/5] Configuring Ollama for persistent VRAM...${NC}"
OVERRIDE_DIR="/etc/systemd/system/ollama.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/nyquest.conf"

if [ ! -f "$OVERRIDE_FILE" ]; then
    sudo mkdir -p "$OVERRIDE_DIR"
    sudo tee "$OVERRIDE_FILE" > /dev/null << 'INNEREOF'
[Service]
Environment="OLLAMA_KEEP_ALIVE=-1"
Environment="OLLAMA_NUM_GPU=99"
Environment="OLLAMA_HOST=localhost:11434"
INNEREOF
    sudo systemctl daemon-reload
    sudo systemctl restart ollama
    sleep 3
    echo -e "  ${GREEN}Configured${NC}"
else
    echo -e "  ${GREEN}Already configured${NC}"
fi

# Step 4: Warm up model
echo -e "${YELLOW}[4/5] Warming up model...${NC}"
WARMUP=$(curl -s -X POST "http://localhost:${OLLAMA_PORT}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"'"${MODEL}"'","messages":[{"role":"user","content":"Say OK"}],"max_tokens":5,"temperature":0}' \
    2>/dev/null || echo "FAILED")

if echo "$WARMUP" | grep -q "choices"; then
    echo -e "  ${GREEN}Model loaded and responding${NC}"
    if command -v nvidia-smi &> /dev/null; then
        VRAM=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null || echo "?")
        echo -e "  GPU VRAM: ${VRAM} MiB"
    fi
else
    echo -e "  ${RED}Model failed. Check: journalctl -u ollama -n 20${NC}"
fi

# Step 5: Summary
echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo "Endpoint:  http://localhost:${OLLAMA_PORT}/v1/chat/completions"
echo "Model:     ${MODEL}"
echo ""
echo "Add to nyquest.yaml:"
echo "  semantic_enabled: true"
echo "  semantic_endpoint: http://localhost:${OLLAMA_PORT}/v1/chat/completions"
echo "  semantic_model: ${MODEL}"
echo ""
echo "Then: cd ${NYQUEST_DIR} && cargo build --release"
