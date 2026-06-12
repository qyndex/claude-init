// Commitlint config aligned with the constitution's §VI commit protocol.
//
// The harness permits any imperative summary after the type(scope): prefix —
// including leading-capital and acronym subjects like "feat(e2e): AC-5 journey
// evidence". The default @commitlint/config-conventional `subject-case` rule
// rejects sentence/start/pascal/upper-case subjects, which would fail the
// harness's own compliant commits (live-E2E FINDING-12 / spec 004 T-135).
//
// We keep every other conventional rule (type-enum, the colon-space prefix, the
// non-empty subject, the blank line before the body) and relax ONLY
// subject-case. Trailers in §VI (Constraint/Rejected/Confidence/...) are
// free-form body lines and were never constrained by conventional config.
module.exports = {
  extends: ["@commitlint/config-conventional"],
  rules: {
    // 0 = disabled. Subject case is a stylistic choice §VI leaves to the author.
    "subject-case": [0],
    // The §VI trailer block + decision body legitimately run long; don't cap body lines.
    "body-max-line-length": [0],
  },
};
