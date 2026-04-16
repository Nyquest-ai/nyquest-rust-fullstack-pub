#!/bin/bash
# Build Nyquest with semantic pipeline integration, restart, and run live test
set -euo pipefail
cd "$(dirname "$0")/../.."

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Nyquest v3.1.1 — Build + Live Test ===${NC}"
echo ""

# Build
echo -e "${CYAN}[1/4] Building (release)...${NC}"
cargo build --release 2>&1 | tail -5
if [ $? -ne 0 ]; then echo -e "${RED}BUILD FAILED${NC}"; exit 1; fi
echo -e "${GREEN}Build OK${NC}"
ls -lh target/release/nyquest
echo ""

# Restart
echo -e "${CYAN}[2/4] Restarting Nyquest...${NC}"
if systemctl is-active --quiet nyquest 2>/dev/null; then
    sudo systemctl restart nyquest
    sleep 3
    echo -e "${GREEN}Restarted via systemd${NC}"
elif pgrep -f "target/release/nyquest" > /dev/null 2>&1; then
    pkill -f "target/release/nyquest" 2>/dev/null || true
    sleep 1
    NYQUEST_CONFIG=nyquest.yaml nohup ./target/release/nyquest > /tmp/nyquest.log 2>&1 &
    sleep 3
    echo -e "${GREEN}Restarted manually${NC}"
else
    NYQUEST_CONFIG=nyquest.yaml nohup ./target/release/nyquest > /tmp/nyquest.log 2>&1 &
    sleep 3
    echo -e "${GREEN}Started fresh${NC}"
fi
echo ""

# Health check
echo -e "${CYAN}[3/4] Health check...${NC}"
HEALTH=$(curl -s http://localhost:5400/health 2>/dev/null)
echo "$HEALTH" | python3 -m json.tool 2>/dev/null || echo "$HEALTH"
echo ""

# Live test — send a request with a large system prompt to trigger semantic compression
echo -e "${CYAN}[4/4] Live semantic compression test...${NC}"
echo ""

# Test 1: Large system prompt (should trigger semantic condensation at >4K tokens)
echo "Test A: Large system prompt through proxy..."
RESP=$(curl -s -w "\nHTTP:%{http_code} TIME:%{time_total}s" \
    -X POST http://localhost:5400/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "x-api-key: test-key" \
    -d '{
        "model": "qwen2.5:1.5b-instruct",
        "messages": [
            {"role": "system", "content": "You are a helpful AI assistant. You should always try to be as helpful as possible when responding to the user. It is very important that you maintain a professional and friendly tone at all times during the conversation. You should never provide misleading or incorrect information to the user. Always make sure your responses are accurate and well-researched. If you are not sure about something, you should let the user know that you are uncertain rather than making something up. You should be respectful and considerate in all your interactions. You should not engage in harmful, illegal, or unethical activities or encourage others to do so. When writing code, you should follow best practices and include error handling. You should provide explanations for complex topics in simple terms when possible."},
            {"role": "user", "content": "Say hello"}
        ],
        "max_tokens": 50,
        "temperature": 0
    }' 2>/dev/null)

HTTP_LINE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -n -1)
echo "  $HTTP_LINE"
echo "  Nyquest headers:"
curl -s -D - -o /dev/null -X POST http://localhost:5400/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "x-api-key: test-key" \
    -d '{"model":"qwen2.5:1.5b-instruct","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' 2>/dev/null \
    | grep -i "x-nyquest" || echo "  (no nyquest headers)"
echo ""

# Check logs for semantic activity
echo "Recent Nyquest logs (semantic):"
if [ -f /tmp/nyquest.log ]; then
    grep -i "semantic\|Semantic" /tmp/nyquest.log | tail -10 || echo "  No semantic log entries"
else
    journalctl -u nyquest --no-pager -n 20 2>/dev/null | grep -i "semantic" || echo "  No semantic log entries"
fi

echo ""
echo -e "${GREEN}=== Done ===${NC}"
