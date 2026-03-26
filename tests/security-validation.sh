#!/bin/bash
# Container Security Validation Test
# Validates container security constraints including privilege escalation prevention,
# filesystem isolation, network restrictions, and sensitive data exposure.

PASS=0
FAIL=0

check() {
  local name="$1"
  local should_fail="$2"
  shift 2
  echo ""
  echo "── TEST: $name"
  echo "   CMD: $*" | sed 's/ghs_[a-zA-Z0-9]*/ghs_***/g'
  if output=$(timeout 5 "$@" 2>&1); then
    if [ "$should_fail" = "yes" ]; then
      echo "   ❌ FAIL — command succeeded (should have been blocked)"
      echo "   OUTPUT: $output"
      FAIL=$((FAIL + 1))
    else
      echo "   ✅ PASS — command succeeded (expected)"
      PASS=$((PASS + 1))
    fi
  else
    if [ "$should_fail" = "yes" ]; then
      echo "   ✅ PASS — command blocked (expected)"
      PASS=$((PASS + 1))
    else
      echo "   ❌ FAIL — command failed (should have succeeded)"
      echo "   OUTPUT: $output"
      FAIL=$((FAIL + 1))
    fi
  fi
}

echo "========================================"
echo "  Container Security Validation"
echo "========================================"
echo ""
echo "Container user: $(whoami) (uid=$(id -u))"
echo "Capabilities: $(cat /proc/self/status 2>/dev/null | grep -i cap || echo 'unknown')"
echo ""

# ── 1. Privilege escalation ──────────────────────────────────

check "Cannot run as root (su)" yes su -c "whoami" root
check "Cannot use sudo" yes sudo whoami
check "No setuid binaries" yes find / -perm -4000 -type f 2>/dev/null -quit
check "Running as non-root" no test "$(id -u)" -ne 0

# ── 2. Filesystem isolation ──────────────────────────────────

check "Cannot write to /repos (read-only mount)" yes touch /repos/test-write
check "Cannot write to /usr" yes touch /usr/test-write
check "Cannot write to /etc" yes touch /etc/test-write
check "Can write to /workspace" no touch /workspace/test-write && rm /workspace/test-write
check "Can write to /tmp" no touch /tmp/test-write && rm /tmp/test-write
check "Can write to ~/.claude (session mount)" no touch /home/agent/.claude/test-write && rm /home/agent/.claude/test-write

# ── 3. Network restrictions ──────────────────────────────────
# The restricted network should only allow github.com, api.anthropic.com,
# api.linear.app on port 443, plus DNS.

check "Can reach github.com (allowed)" no curl -s --max-time 5 -o /dev/null https://github.com
check "Can reach api.anthropic.com (allowed)" no curl -s --max-time 5 -o /dev/null https://api.anthropic.com
check "Cannot reach example.com (blocked)" yes curl -s --max-time 5 -o /dev/null https://example.com

# ── 4. Process capabilities ──────────────────────────────────

check "Cannot mount filesystems" yes mount -t tmpfs none /mnt 2>&1
check "Cannot create network interfaces" yes ip link add dummy0 type dummy 2>&1
check "Cannot change hostname" yes hostname hacked 2>&1
check "Cannot kill PID 1" yes kill -0 1 2>&1

# ── 5. Sensitive data exposure ───────────────────────────────

check "GITHUB_TOKEN is set (needed for git)" no test -n "${GITHUB_TOKEN:+set}"
check "Token not in git remote URL" yes git -C /workspace remote get-url origin 2>/dev/null | grep -q "$GITHUB_TOKEN"
check "Token not in .gitconfig" yes cat ~/.gitconfig 2>/dev/null | grep -q "$GITHUB_TOKEN"

# ── 6. Docker socket (should not be mounted) ─────────────────

check "No docker socket access" yes test -e /var/run/docker.sock

# ── Summary ──────────────────────────────────────────────────

echo ""
echo "========================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  echo '{"type":"result","result":"⚠️ Security test: '$PASS' passed, '$FAIL' FAILED — review output above"}'
  exit 1
else
  echo '{"type":"result","result":"✅ Security test: All '$PASS' checks passed — container is locked down"}'
fi
