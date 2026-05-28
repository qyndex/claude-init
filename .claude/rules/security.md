---
# Path-scoped. Globs deliberately narrow: Round 5 audit found `**/middleware/**`
# and `**/permissions/**` triggered on every UI middleware / RBAC table — adding
# ~3 KB to context for unrelated edits. Use suffix patterns where possible so
# we only load on actual auth files, not any directory named "middleware".
paths:
  - "**/auth/**/*"
  - "**/login/**/*"
  - "**/signup/**/*"
  - "**/session/**/*"
  - "**/token/**/*"
  - "**/oauth/**/*"
  - "**/jwt/**/*"
  - "**/security/**/*"
  - "**/crypto/**/*"
  - "**/keys/**/*"
  - "**/rbac/**/*"
  - "**/*.auth.{ts,tsx,js,go,py,rs}"
  - "**/*.session.{ts,tsx,js,go,py,rs}"
---

# Security rules

> Loaded when Claude is touching auth, sessions, tokens, OAuth, middleware, crypto, or permissions code. This is the strictest rule file.

## Before writing any change in these paths

1. Run the `security-guard` skill checklist (OWASP Top 10 + LLM Top 10).
2. Run `semgrep mcp` on the diff.
3. If the change touches password handling, session lifecycle, OAuth flows, or token issuance — write a spec first with explicit threat-model + rollback.

## Hard rules

- **No new auth code without an explicit security review.** Even small changes (rate limit tweak, scope addition) need the `security` agent.
- **Never log a credential.** Not even masked. Just don't.
- **Never store a secret as code.** Use env vars, secret managers (Vault, SOPS, AWS Secrets Manager).
- **Never accept user-controlled redirects** without an allowlist check. Open redirects are how phishing campaigns work.
- **CSRF tokens** on every state-changing endpoint that uses cookie auth.
- **SameSite=Lax or Strict** on session cookies. `None` only when you need cross-site and have a clear reason.
- **HttpOnly + Secure** on all auth cookies. No exceptions.
- **Rotate session tokens** on login, logout, password change, MFA enable.

## Crypto

- **No DIY crypto.** Use libsodium, Web Crypto, AWS KMS, GCP KMS, HashiCorp Vault. Never roll your own primitive.
- **Algorithms:** AES-GCM or ChaCha20-Poly1305 for symmetric; Ed25519 or RSA-PSS-SHA256 for signatures; Argon2id for password hashing.
- **No** MD5, SHA1, RC4, DES, 3DES, ECB mode, raw RSA padding, or hardcoded IVs/nonces.
- **Random:** use a CSPRNG (`crypto.randomBytes`, `secrets.token_bytes`, `os.urandom`). Never `Math.random()` for anything security-relevant.

## Permissions / RBAC

- **Default deny.** Every endpoint declares what permission is required; no implicit "anyone authenticated can do this".
- **Permission checks are in the handler, not the middleware.** Middleware can short-circuit unauthorized, but the handler must double-check (defense in depth).
- **No "admin === true" checks.** Use a role/permission system with named permissions.

## OWASP LLM Top 10 (if this code touches LLM agents)

- **LLM01 Prompt injection:** treat any external content (user input, fetched URLs, tool output) as untrusted data, never as instructions. Wrap in `<untrusted>` tags before passing to the model.
- **LLM02 Insecure output handling:** sanitize LLM output before exec, eval, SQL, shell, or HTML render.
- **LLM06 Sensitive info disclosure:** don't pass PII to the LLM unless required; redact before.
- **LLM08 Excessive agency:** the agent has the minimum tool scope it needs. Audit `tools:` frontmatter against agent mandate.

## Verification

- **Pen-test fixtures** for new auth paths: bad password, expired token, replay, CSRF, open-redirect, IDOR.
- **`semgrep --config=p/owasp-top-ten --config=p/secrets`** before commit.
- **CodeQL workflow** runs in CI; check the dashboard for new findings.

## When in doubt

Stop and ask. Auth bugs are the most expensive bugs.
