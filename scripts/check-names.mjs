// Name check (NOT part of the app). Uses TypeScript's analyzer, if installed, to find names
// that are used but not defined (a missing import shows up here), unused variables and
// use-before-define in src/. It is not a build and does not check types.
// Run:  node scripts/check-names.mjs [part-of-a-path ...]   Exit code 1 if it finds anything.
import { createRequire } from 'node:module'
import { readdirSync, statSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'
const require = createRequire(import.meta.url)
let ts
for (const p of ['typescript', join(process.env.HOME ?? '', '.npm-global/lib/node_modules/typescript')]) {
  try {
    ts = require(p)
    break
  } catch {
    /* try the next place */
  }
}
if (!ts) {
  console.error('TypeScript is not installed here, so no name check was done.')
  process.exit(2)
}
const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const walk = (d) => readdirSync(d).flatMap((f) => (statSync(join(d, f)).isDirectory() ? walk(join(d, f)) : [join(d, f)]))
const files = walk(join(root, 'src')).filter((f) => /\.jsx?$/.test(f) && !/\.test\.js$/.test(f))
const program = ts.createProgram(files, { allowJs: true, checkJs: true, noEmit: true, jsx: ts.JsxEmit.Preserve, target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext, moduleResolution: ts.ModuleResolutionKind.Bundler, noUnusedLocals: true, skipLibCheck: true, types: [] })
const want = new Set([2304, 2552, 6133, 6196, 6198, 2451, 2448, 2454, 1155])
const only = process.argv.slice(2)
let n = 0
for (const sf of program.getSourceFiles()) {
  if (sf.fileName.includes('node_modules') || !sf.fileName.startsWith(root)) continue
  for (const d of [...program.getSyntacticDiagnostics(sf), ...program.getSemanticDiagnostics(sf)]) {
    if (!want.has(d.code)) continue
    const rel = relative(root, sf.fileName)
    if (only.length && !only.some((o) => rel.includes(o))) continue
    const { line } = sf.getLineAndCharacterOfPosition(d.start)
    console.log(`${rel}:${line + 1}: TS${d.code} ${ts.flattenDiagnosticMessageText(d.messageText, ' ')}`)
    n += 1
  }
}
console.log(`${n} finding(s) (undefined names, unused variables, use-before-define)`)
process.exit(n ? 1 : 0)
