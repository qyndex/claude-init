# Stream Analysis — feat-{{ STREAM_ID }}

> Coordinator's scope decomposition. Lives at `.swarms/streams/<id>/analysis.md`.
> Stream's `brief.md` references this for the files-owned / files-shared rules.

## Tasks in this stream

| Task ID | Summary | Spec | Files |
|---|---|---|---|
| T-{{ ID }} | {{ VERB-FIRST }} | specs/active/{{ SPEC }}.md | {{ FILES }} |
| T-{{ ID }} | {{ VERB-FIRST }} | specs/active/{{ SPEC }}.md | {{ FILES }} |

## Layer decomposition (CCPM-style)

Break the work into layers. Each layer has clear file ownership.

| Layer | Files | Owner | Notes |
|---|---|---|---|
| DB | migrations/*, db/schema.* | this stream | exclusive |
| Service | src/services/foo.* | this stream | exclusive |
| API | src/api/foo.* | this stream | exclusive |
| UI | components/Foo.tsx | this stream | exclusive |
| Tests | tests/foo.*.test.* | this stream | exclusive |

## Files owned (this stream is the only writer)

- {{ PATH_1 }}
- {{ PATH_2 }}

## Files shared (designated owner stream)

If multiple streams need to write to the same file, ONE stream owns it. Others read.

| Shared file | Owner stream | Why |
|---|---|---|
| {{ PATH_X }} | feat-{{ OWNER_ID }} | first to touch; others depend on its updates |

## Contracts consumed (Round 6 E — drives verified-merge contract-tests)

Anything this stream READS or DEPENDS ON from another stream's eventual main-merge.
`contract-tests.sh` asserts each line is present on the integrated branch BEFORE
merging this stream. Formats:

- `exported_symbol:<lang>:<file>:<symbol>` — e.g., `exported_symbol:ts:src/services/user.ts:fetchUser`
- `http_route:<method>:<path>` — e.g., `http_route:POST:/api/users`
- `db_column:<table>:<column>` — e.g., `db_column:users:email_verified`
- `flag:<flag-name>` — e.g., `flag:checkout_v2`

Example:
- exported_symbol:ts:src/types/api.ts:UserShape
- http_route:GET:/api/users/:id
- db_column:users:email_verified
- flag:experimental_billing

Without this section, `contract-tests.sh` passes trivially and semantic conflicts can ship.

## Acceptance criteria (rolled up across tasks)

- {{ AC_1 }} — verified by `{{ COMMAND_1 }}`
- {{ AC_2 }} — verified by `{{ COMMAND_2 }}`

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| {{ RISK }} | low/med/high | {{ MITIGATION }} |

## Coordinator notes

- {{ NOTE_FOR_HUMAN_REVIEWING_AT_MERGE_TIME }}
