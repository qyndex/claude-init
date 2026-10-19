# Supplemental review of prior head fe8a304

Tools disabled; exact public input hash retained in manifest. Static review only, no native acceptance. Findings below were triaged: Markdown fence/newline issues fixed in45cddb5; misplaced definitions guarded; typo/comment corrected; routing unchanged; speculative current omissions not reproduced. Independent read-only review found no actionable blocker in45cddb5.

# Review: `fe8a3044` (base `6399f35`)

I found no blocker in the changed code. The main issue is a Medium design gap in the new acceptance parser that can silently drop requirements. I read the diff and source only; I ran nothing, so none of the test or acceptance claims below are verified.

## Findings

**1. Medium: ACs defined outside `## Acceptance criteria` are silently dropped.**
`.claude/scripts/acceptance-criteria.py:29-41`, used at `spec-match.sh:39` and `collect-evidence.sh:50`.
- Before, `spec-match.sh` grepped the whole spec, so any `AC-N` anywhere was required.
- Now only the one H2 section counts, and any later H1/H2 ends it.
- Scenario: someone appends `## Amendment 1` containing `**AC-9**: new requirement` to a spec. Matcher and collector report all-proven at 8/8 and never demand AC-9. There is no error, and neither tool compares against the policy's AC set.
- Fix: fail closed on definition-shaped lines outside the section (list-item, bold or `AC-N:` at line start), or cross-check against the policy AC set.
- The PR says all 50 active specs parse and only Spec014's AC-9 reference is excluded. I could not verify that, and it covers current specs only.

**2. Low: a backtick fence opener accepts a backtick in its info string.**
`acceptance-criteria.py:21,26-28`.
- Per CommonMark, a line like ```` ```x``` AC-2 text ```` is inline code, not a fence opener.
- Here it starts a fence, and the next bare ```` ``` ```` closes it. That can swallow real AC lines or a section-ending heading with no error.
- Fix: for backtick fences, reject the opener when `'`' in marker[2]`.

**3. Low: `splitlines()` is wider than Markdown's line breaks.**
`acceptance-criteria.py:13`.
- It also splits on `\x0b`, `\x0c`, `\x1c`–`\x1e`, `\x85`, `\u2028` and `\u2029`.
- A spec containing `text\u2028## Acceptance criteria` yields a heading that no Markdown renderer or human reviewer sees.
- Fix: `re.split(r'\r\n|\r|\n', text)`.

**4. Low: the Python helper is run without `-I`.**
`collect-evidence.sh:50`, `spec-match.sh:39`.
- Sibling proof-path code (`collect-evidence.sh:108-119`) uses `python3 -I` on purpose, and `evidence-proof-preservation.sh` tests that.
- Without `-I` the script directory goes on `sys.path`. This is mitigated if `.claude/scripts` is a protected path.
- Fix: use `python3 -I`.

**5. Low: the source-role predicate duplicates `_route`.**
`factory-reporting-transport.py:185-187` duplicates the logic at `:146`.
- If routing changes, `credential_role` can disagree with the token actually used, and that is the label operators will rely on for the 403 triage.
- Fix: return `(token, role)` from `_route`.

**6. Info: stale lint justification and a behavior change.**
- `collect-evidence.sh:53` still says "fallback yields zero when grep matches no AC lines". No grep or fallback remains there.
- `spec-match.sh` used to exit 0 with "nothing to match" for a spec with no ACs. It now exits 1.
- This is intended fail-closed behavior, but any caller (workflow or `check-local-evidence.py`) that relied on exit 0 for docs-only specs will break. I could not see those callers.

**7. Info: doc typo.**
`docs/OPERATOR-MANUAL.md:~265`: the unchanged line ends "...task; an" and the new line starts "# a configured session", so it reads "an a configured session".

**8. Process: the committed evidence cannot satisfy the evidence gate.**
- All four `collectors/*/evidence.json` have `results_sha256: ""`, meaning no results file existed.
- They are bound to `cff00d9`, not head `fe8a304`.
- The "Retained results" links in the committed `EVIDENCE.md` and `pr-body.md` point to `attempt-*/results.json` files that are not in the diff.
- The four FAILs therefore look like "no AC-tagged result set emitted", not a parser regression. The counts 21/8/9/4 only show that the parser enumerates ACs.
- I could not tell why no runner produced results. The collector's runner detection never ran a runner, yet `runner_exit` is 0.

## Checked, no defect found

- **Diagnostic privacy.** Stderr is capped at 2048 bytes and mapped to fixed labels. The endpoint charset (`:96` of the transport's `_route`) excludes spaces, so a request path cannot forge a "rate limit" substring. Forged attributes are filtered by `safe_diagnostic`.
- **Unchanged behavior.** I saw no change to retry, budget, token routing or permissions.
- **Normalization.** The parser's `str(int(value))` matches the `sed 's/AC-0*…/'` form used for result tags.
- **Stale evidence.** `collect-evidence.sh:43` deletes old evidence before the parser can fail, so a parse failure cannot leave stale PASS evidence.

## Limitations

- **403 cause.** The diff adds diagnostics only. Nothing in it explains the native 403s, and I make no claim about them.
- **Existing tests.** Other tests that assert exact `safe_diagnostic` dicts for `RoutedAPI` errors would break on the new `credential_role` key. Only the one updated test is visible to me.
- **Unseen files.** I did not see the specs, `check-local-evidence.py`, the workflows or `factory-intake-console.py`. The `--root` flag in the intake doc and the README anchor change from `#manual-setup-what-the-installer-cant-do` to `#manual-setup` are unverified; the anchor breaks if the heading is unchanged.
- **Docs.** I did not check the documented claims (173 tasks, run IDs, SHAs) against ground truth.
