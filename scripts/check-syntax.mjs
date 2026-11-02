// Syntax check (NOT part of the app). Parses .js and .jsx files with TypeScript's
// parser, if it is installed, and reports syntax errors (unbalanced JSX tags,
// stray brackets, bad expressions). It is NOT a build: it does not resolve
// imports or check types. Run:  node scripts/check-syntax.mjs [file ...]
import { createRequire } from 'node:module'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
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
  console.error('TypeScript is not installed here, so no syntax check was done.')
  process.exit(2)
}
const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const walk = (d) => readdirSync(d).flatMap((f) => (statSync(join(d, f)).isDirectory() ? walk(join(d, f)) : [join(d, f)]))
const files = process.argv.length > 2 ? process.argv.slice(2).map((f) => resolve(f)) : walk(join(root, 'src')).filter((f) => /\.jsx?$/.test(f))
let bad = 0
for (const file of files) {
  const out = ts.transpileModule(readFileSync(file, 'utf8'), {
    fileName: file,
    reportDiagnostics: true,
    compilerOptions: { jsx: ts.JsxEmit.Preserve, target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext, allowJs: true },
  })
  for (const d of out.diagnostics ?? []) {
    bad += 1
    const { line } = d.file ? d.file.getLineAndCharacterOfPosition(d.start) : { line: 0 }
    console.error(`${relative(root, file)}:${line + 1}: ${ts.flattenDiagnosticMessageText(d.messageText, ' ')}`)
  }
}
console.log(`Parsed ${files.length} file(s) with TypeScript ${ts.version}: ${bad} syntax problem(s).`)
process.exit(bad ? 1 : 0)
