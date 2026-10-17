# T339 candidate registry fixture compatibility

Only two test files changed. Baseline both suites failed reading a controlled nonempty invalid candidate registry before reaching protected-API replay; logs preserve the real failure. This is an untrusted candidate test, not a fake approved active profile. After correction both suites pass with that same candidate file, then pass again after restoring exact original empty shipped registry bytes. No registry or production runtime change committed.

Producer tests empty loader semantics in an explicit temporary registry instead of assuming an adopter repository remains unconfigured. Replay explicitly changes only scoped cwd to a separate temporary invalid candidate registry, asserts those candidate bytes differ, and proves independently protected API registry replay succeeds; finally restores cwd. Existing withdrawn/missing/foreign/API/source/certificate/57-family/fresh-process negatives remain. This does not bypass any runtime registry validation; it isolates which registry is authoritative.

No current approved PR/head changes, live settings, native proof or activation. Scope is future profile-config PR test compatibility only.
