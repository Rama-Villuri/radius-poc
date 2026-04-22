#!/usr/bin/env bash
# test-radius.sh — run on Mac Mini to verify RADIUS server behavior.
# Requires: docker compose up -d (from the docker/ directory)
# Requires: radtest (install via: brew install freeradius-server)

set -euo pipefail

RASPI_IP="${RASPI_IP:-RASPI_IP}"   # override via env or edit below
MAC_MINI_IP="${MAC_MINI_IP:-localhost}"
SECRET="testing123"                 # localhost secret from clients.conf

PASS_USER="radius-testuser"
PASS_PASS="TestPass123!"
FAIL_USER="notauser"
FAIL_PASS="wrongpassword"

pass() { echo "  [PASS] $*"; }
fail() { echo "  [FAIL] $*"; exit 1; }

echo "=== RADIUS Server Tests ==="
echo ""

echo "--- Test 1: Valid credentials → expect Access-Accept ---"
output=$(radtest "$PASS_USER" "$PASS_PASS" "$MAC_MINI_IP" 0 "$SECRET" 2>&1)
echo "$output" | head -5
echo "$output" | grep -q "Access-Accept" && pass "Got Access-Accept" || fail "Expected Access-Accept"

echo ""
echo "--- Test 2: Wrong password → expect Access-Reject ---"
output=$(radtest "$PASS_USER" "wrongpassword" "$MAC_MINI_IP" 0 "$SECRET" 2>&1)
echo "$output" | head -5
echo "$output" | grep -q "Access-Reject" && pass "Got Access-Reject" || fail "Expected Access-Reject"

echo ""
echo "--- Test 3: Unknown user → expect Access-Reject ---"
output=$(radtest "$FAIL_USER" "$FAIL_PASS" "$MAC_MINI_IP" 0 "$SECRET" 2>&1)
echo "$output" | head -5
echo "$output" | grep -q "Access-Reject" && pass "Got Access-Reject" || fail "Expected Access-Reject"

echo ""
echo "--- Test 4: radius-user2 credentials → expect Access-Accept ---"
output=$(radtest "radius-user2" "AnotherPass456!" "$MAC_MINI_IP" 0 "$SECRET" 2>&1)
echo "$output" | head -5
echo "$output" | grep -q "Access-Accept" && pass "Got Access-Accept" || fail "Expected Access-Accept"

echo ""
echo "=== All tests passed ==="
echo ""
echo "Next step: run setup.sh on the Raspberry Pi, then:"
echo "  ssh radius-testuser@${RASPI_IP}"
