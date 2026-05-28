---
name: codemod
description: Large-scale refactor via AST-aware transforms — jscodeshift (JS/TS), ts-morph (TS), comby (any language), bowler (Python). Dry-run → review → apply loop. Use for React 18→19, Node 22→24, or any change touching 50+ call sites.
when_to_use: A breaking dep upgrade or framework migration touches many call sites. User says "migrate N call sites", "codemod", "refactor at scale", "upgrade React".
allowed-tools: Read, Glob, Grep, Edit, Write, Bash
model: sonnet
---

# Codemod — refactor at scale

50+ call sites of the same change is a codemod, not 50 manual edits.

## Tools

| Tool | Languages | When to use |
|---|---|---|
| jscodeshift | JS/TS via Babel AST | React's official codemod tool; large ecosystem of community codemods |
| ts-morph | TypeScript with type info | Type-aware refactors; renames; signature changes |
| comby | Any language via pattern matching | Cross-language; no AST setup; quick one-shot |
| bowler | Python via LibCST | Type-aware Python; preserves comments |
| ast-grep | Any language via TreeSitter | Pattern matching with structural awareness |
| Semgrep autofix | Any | When you already have a Semgrep rule |

## Process

1. **Define the transform** — write or find a codemod. Express as: "for every <pattern>, replace with <replacement>".
2. **Dry run on a few files** — verify the transform does what you expect.
3. **Dry run on the whole codebase** — generates a diff but doesn't write.
4. **Review the diff** — visual review of the proposed changes. Look for false positives.
5. **Apply** — run with `--write`. Commit the diff with a "codemod:" prefix.
6. **Verify** — tests + typecheck + lint pass.
7. **Open the PR** — descriptive title + body explaining the codemod source.

## Example: jscodeshift for a React API rename

```js
// codemods/rename-useLayoutEffect.js
module.exports = function(fileInfo, api) {
  const j = api.jscodeshift;
  return j(fileInfo.source)
    .find(j.CallExpression, { callee: { name: 'useLayoutEffect' } })
    .replaceWith(p => j.callExpression(j.identifier('useInsertionEffect'), p.value.arguments))
    .toSource();
};
```

Run:
```bash
npx jscodeshift -t codemods/rename-useLayoutEffect.js src/ --dry --print  # preview
npx jscodeshift -t codemods/rename-useLayoutEffect.js src/                  # apply
```

## Example: ts-morph for type-aware rename

```ts
// codemods/rename-method.ts
import { Project } from "ts-morph";
const project = new Project({ tsConfigFilePath: "tsconfig.json" });
project.getSourceFiles().forEach(sf => {
  sf.forEachDescendant(node => {
    if (node.getKindName() === 'MethodDeclaration' && node.getName() === 'oldName') {
      node.rename('newName');  // type-aware; updates all call sites
    }
  });
});
project.save();
```

## Example: comby (language-agnostic)

```bash
# Rename all `foo(:[args])` to `bar(:[args])` across all .ts files
comby 'foo(:[args])' 'bar(:[args])' -d src -extensions ts -in-place
```

## Hard rules

- **Dry run before write.** Always preview the diff.
- **One transform per PR.** Don't combine codemods with feature work.
- **Verify with tests + typecheck.** A codemod that breaks the type checker is a codemod that introduced a bug.
- **Save the codemod script** in `codemods/` for future re-runs and as historical record.
- **Document false positives** in the PR description if you had to skip files.

## Integration with /upgrade

When `/upgrade <pkg> --major` is invoked, this skill is the first call:
1. Read the upgrade guide
2. Find or write the matching codemods
3. Dry-run → review → apply per codemod
4. Then run the test suite + ship

## References

- jscodeshift: https://github.com/facebook/jscodeshift
- ts-morph: https://ts-morph.com/
- comby: https://comby.dev/
- bowler: https://pybowler.io/
- ast-grep: https://ast-grep.github.io/
- React codemod registry: https://github.com/reactjs/react-codemod
