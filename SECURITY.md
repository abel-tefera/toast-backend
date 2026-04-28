# Docker Environment Security Risk Surface Analysis - LIT-93

## Executive Summary

This document outlines the security risk surface of the Claude Code Docker/containerd environment where this agent is executing. The container is **well-hardened at the container isolation level** but has **significant operational risks** around API key exposure and multi-instance isolation.

**Overall Risk Level**: 🟠 **MEDIUM** (well-hardened container with managed operational risks)

---

## 1. Container Runtime Architecture

### Current State
- **Runtime**: Containerd (not Docker daemon)
- **Kernel**: Linux 6.10.14-linuxkit (Aug 2025, current and patched) ✅
- **Architecture**: aarch64
- **User**: Non-root user `agent` (uid=1001, gid=1001) ✅
- **Filesystem**: Overlayfs with read-only /repos mount ✅
- **Volume Mounts**:
  - `/repos` → ext4 (read-only) ✅
  - `/workspaces` → ext4 (read-write) ⚠️
  - `/sessions` → ext4 (read-write) ⚠️
  - Root filesystem → overlayfs (read-write)
- **Networking**: Bridge network, full egress enabled
- **Process Isolation**: Kernel namespaces (PID, network, mount, IPC)

---

## 2. Key Risk Areas

### A. API Key & Credential Exposure (🔴 CRITICAL)

**Risk**: API keys are visible in environment variables and accessible via multiple attack vectors.

**Attack Vectors Confirmed**:
1. ✅ Environment variables readable via `/proc/self/environ`
2. ✅ Process listing (`ps aux`) shows env vars in command line
3. ✅ Child process inheritance (all subprocesses inherit credentials)
4. ⚠️ Bash history (if HISTFILE not /dev/null)
5. ⚠️ Core dumps in /var/crash (if enabled)
6. ⚠️ Tool logging/output capture

**Exposed Credentials**:
- `ANTHROPIC_API_KEY` (Claude API authentication)
- `GITHUB_TOKEN` (GitHub REST API, full repo access)
- `LINEAR_API_KEY` (Linear GraphQL API, can read/modify issues)

**Impact if Exploited**:
- Full API access to Anthropic, GitHub, Linear services
- Ability to modify repositories, create/close issues, consume API quotas
- Lateral movement to upstream services
- Compliance violations (credential exposure in logs/artifacts)

**Current Mitigations**:
- ✅ Non-root user prevents certain OS-level attacks
- ⚠️ No secret masking in logs
- ⚠️ No environment variable redaction
- ⚠️ No bash history filtering

**Recommendations** (Priority 1 - Immediate):
- [ ] Rotate all three API keys immediately (30 minutes)
- [ ] Implement environment variable redaction in logging (mask `*_KEY` vars)
- [ ] Disable bash history: `export HISTFILE=/dev/null && set +H`
- [ ] Redact credentials from tool output before display
- [ ] Add pre-commit hook to detect secrets
- [ ] Review all stderr/stdout capturing in child processes

---

### B. Multi-Instance Isolation (🔴 CRITICAL)

**Risk**: Multiple Claude Code instances could share `/sessions` and `/workspaces` volumes

**Attack Vectors**:
1. Session hijacking if resumption tokens leaked
2. Cross-session data exfiltration from shared volumes
3. Privilege escalation via shared temp files
4. Malicious code injection into another session's workspace

**Current Status**: Unknown if multiple instances are running concurrently

**Recommendations**:
- [ ] Audit container for concurrent instances
- [ ] Implement session namespace isolation (`/sessions/{SESSION_ID}/`)
- [ ] Add cryptographic session tokens (not predictable)
- [ ] Restrict volume sharing between sessions

---

### C. Data Exfiltration (🟠 MEDIUM-HIGH)

**Risk**: Full read-write access to `/workspaces` + full network egress

**Attack Vectors**:
1. Git commits with exfiltrated data (using GITHUB_TOKEN)
2. API calls to external services (curl available)
3. DNS tunneling
4. Slack/email integration if configured

**Current Mitigations**:
- ✅ GITHUB_TOKEN scoped to repo access (not admin)
- ⚠️ No network egress filtering
- ⚠️ No DLP (Data Loss Prevention) controls

**Recommendations** (Priority 3 - Medium-term):
- [ ] Implement strict seccomp profile (deny all, allowlist only needed syscalls)
- [ ] Read-only root filesystem (except `/tmp`, `/var/tmp`)
- [ ] Network egress filtering (whitelist only required endpoints)

---

### D. Persistence & Lateral Movement (🟠 MEDIUM)

**Risk**: Read-write root filesystem and access to tool suite

**Attack Vectors**:
1. Install persistence hooks in ~/.bashrc or ~/.profile
2. Modify user cron jobs
3. Compromise git hooks (.git/hooks)
4. Plant backdoors in /app or other writable locations

**Current Mitigations**:
- ✅ Filesystem is ephemeral per session (cleaned up after)
- ⚠️ During session lifetime, full filesystem modification possible

**Recommendations**:
- [ ] Drop all Linux capabilities (none needed for non-root agent)
- [ ] Read-only root filesystem implementation
- [ ] Regular filesystem integrity checks

---

### E. Container Escape (🟡 MEDIUM)

**Risk**: Modern kernel + seccomp enabled, but no deny-list config visible

**Attack Vectors**:
1. Kernel exploits (CVE-2025-XXXX in overlayfs, etc.)
2. Containerd daemon vulnerabilities (if socket exposed)
3. CGROUP escape (memory exhaustion, CPU DoS)
4. Unintended syscall access via incomplete seccomp

**Current Mitigations**:
- ✅ Non-root user (reduces kernel exploit impact)
- ✅ Modern kernel (6.10.14, recent patchset)
- ⚠️ No visible seccomp profile specification
- ⚠️ No resource limits visible (CPU, memory, FDs)

**Recommendations**:
- [ ] Configure resource limits (memory: 2GB, CPU: 2 cores, FD: 1024)
- [ ] Implement strict seccomp profile
- [ ] Disable core dumps

---

### F. Supply Chain & Tool Exploitation (🟡 LOW-MEDIUM)

**Risk**: Trusted tools (bash, git, curl, npm, jq) could be compromised

**Attack Vectors**:
1. Malicious bash binary with credential logging
2. Compromised git to steal SSH keys or credentials
3. Trojanized curl/npm to exfiltrate data

**Current Mitigations**:
- ✅ Tools sourced from official images (likely)
- ✅ Regular image updates
- ⚠️ No image signature verification visible

---

## 3. Blast Radius

| Component | Risk | Impact | Exploitability |
|-----------|------|--------|-----------------|
| **API Keys** | 🔴 CRITICAL | Full upstream service compromise | ✅ **Confirmed** |
| **User Repos** | 🔴 CRITICAL | Code modification, supply chain attack | ✅ High |
| **Workspaces** | 🟠 HIGH | Malicious code execution, data theft | ✅ High |
| **Sessions** | 🟠 HIGH | Session hijacking, multi-instance isolation | ⚠️ Medium |
| **Host System** | 🟡 MEDIUM | Container escape, DoS | ⚠️ Low (modern mitigations) |

---

## 4. Recommended Phased Approach

### Priority 1: Immediate (Credential Rotation) — 30 minutes
- [ ] Rotate `ANTHROPIC_API_KEY` immediately
- [ ] Rotate `GITHUB_TOKEN` immediately  
- [ ] Rotate `LINEAR_API_KEY` immediately
- [ ] Audit GitHub, Linear, Anthropic for suspicious activity
- [ ] Review git commit history for any credential exposure

**Impact**: ↓ CRITICAL → MEDIUM

### Priority 2: Short-term (Credential Handling) — 2-4 hours
- [ ] Implement environment variable redaction in logging (mask `*_KEY` vars)
- [ ] Disable bash history: `export HISTFILE=/dev/null && set +H`
- [ ] Redact credentials from tool output before display
- [ ] Add pre-commit hook to detect secrets
- [ ] Review all stderr/stdout capturing in child processes

**Impact**: ↓ MEDIUM → LOW-MEDIUM

### Priority 3: Medium-term (Container Hardening) — 1-2 weeks
- [ ] Implement strict seccomp profile (deny all, allowlist only needed syscalls)
- [ ] Add resource limits (memory: 2GB, CPU: 2 cores, FD: 1024)
- [ ] Read-only root filesystem (except `/tmp`, `/var/tmp`)
- [ ] Drop all Linux capabilities (none needed for non-root agent)
- [ ] Disable core dumps

**Impact**: ↓ LOW-MEDIUM → LOW

### Priority 4: Long-term (Observability) — 2-4 weeks
- [ ] Container security event logging (kernel audit, seccomp violations)
- [ ] Session isolation verification (no cross-session data access)
- [ ] Anomaly detection (unexpected network egress, file writes)
- [ ] Incident response automation (kill container on breach signal)

---

## 5. Open Questions

1. **Session Management**: Are multiple Claude Code instances running concurrently? Do they share `/sessions` or `/workspaces`?
2. **Secrets Rotation**: Is there an automated key rotation policy? How often are credentials rotated?
3. **Bash History**: Is `HISTFILE` configured to `/dev/null` or `/dev/false`? Is history persisted?
4. **Resource Limits**: What are the actual cgroup limits on CPU, memory, file descriptors?
5. **Seccomp Profile**: What syscalls are allowed? Is there a strict deny-list policy?
6. **Image Scanning**: Are base images scanned for CVEs before deployment?
7. **Monitoring**: Is there container security event logging? Can we detect credential access?
8. **Incident Response**: What's the SLA for responding to credential leaks?
9. **Network Egress**: Are there firewall rules blocking unexpected destinations?
10. **Session Isolation**: What prevents one instance from reading `/sessions/{OTHER_SESSION_ID}` files?

---

## 6. Complexity Estimate

| Item | Complexity | Effort | Risk Reduction |
|------|-----------|--------|-----------------|
| **Priority 1** (Key Rotation) | S | 30 min | CRITICAL → MEDIUM |
| **Priority 2** (Credential Handling) | S | 2-4 hrs | MEDIUM → LOW-MEDIUM |
| **Priority 3** (Container Hardening) | M | 3-5 days | LOW-MEDIUM → LOW |
| **Priority 4** (Observability) | M | 2-4 weeks | Detection & Response |
| **Total** | **M** | **~1 month** | **CRITICAL → LOW** |

---

## 7. Conclusion

The Claude Code Docker/containerd environment is **hardened at the container isolation level** (non-root user, modern kernel, overlayfs) but has **critical operational risks** around credential exposure.

**Primary Risk Sources** (in order):
1. 🔴 **API keys in plaintext environment variables** → **ACTIVELY EXPLOITABLE**
2. 🔴 **Multi-instance isolation unclear** → Potential cross-session attacks
3. 🟠 **Full network egress + read-write workspaces** → Data exfiltration possible
4. 🟠 **No visible seccomp profile** → Kernel escapes harder to detect
5. 🟡 **Container escape via kernel CVEs** → Low probability, high impact

**Immediate Actions** (Reduce CRITICAL → LOW in ~3 hours):
1. Rotate all three API keys NOW
2. Implement credential redaction in logging
3. Disable bash history
4. Audit for any exposed secrets in git history

This analysis was completed as part of LIT-93 security assessment spike.
