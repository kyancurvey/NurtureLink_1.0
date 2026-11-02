// Import checker (NOT part of the app; nothing imports it). Run with:
//   node scripts/check-imports.mjs [file ...]
// With no arguments it checks every .js and .jsx file under src/.
//
// For each RELATIVE import it checks that
//   1. the target file exists (with the extension written in the import), and
//   2. every NAMED import is really exported by that file, and a DEFAULT
//      import has a default export. `export *` and `export { x } from` are followed.
// It also warns about named imports that are never used in the importing file.
// It is a text check, not a compiler: it cannot prove the code builds. Exit
// code 1 if it finds a problem (warnings do not fail it).
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const srcDir = join(root, 'src')

const walk = (d) =>
  readdirSync(d).flatMap((f) => {
    const p = join(d, f)
    return statSync(p).isDirectory() ? walk(p) : [p]
  })

const stripComments = (text) => text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`])\/\/[^\n]*/g, '$1')

// What a file exports: { names: Set, hasDefault: bool }
const cache = new Map()
function exportsOf(file, seen = new Set()) {
  if (cache.has(file)) return cache.get(file)
  const out = { names: new Set(), hasDefault: false }
  if (seen.has(file) || !existsSync(file)) return out
  seen.add(file)
  const text = stripComments(readFileSync(file, 'utf8'))
  for (const m of text.matchAll(/export\s+(?:async\s+)?(?:function\*?|const|let|var|class)\s+([A-Za-z_$][\w$]*)/g)) out.names.add(m[1])
  if (/export\s+default\b/.test(text)) out.hasDefault = true
  for (const m of text.matchAll(/export\s*\{([^}]*)\}(?:\s*from\s*['"]([^'"]+)['"])?/g)) {
    for (const part of m[1].split(',')) {
      const bit = part.trim()
      if (!bit) continue
      const asMatch = bit.match(/^(?:([\w$]+)\s+as\s+)?([\w$]+)$/)
      if (!asMatch) continue
      if (asMatch[2] === 'default') out.hasDefault = true
      else out.names.add(asMatch[2])
    }
  }
  for (const m of text.matchAll(/export\s*\*\s*from\s*['"]([^'"]+)['"]/g)) {
    if (!m[1].startsWith('.')) continue
    const target = resolve(dirname(file), m[1])
    const sub = exportsOf(target, seen)
    sub.names.forEach((n) => out.names.add(n))
  }
  cache.set(file, out)
  return out
}

const files = process.argv.length > 2 ? process.argv.slice(2).map((f) => resolve(f)) : walk(srcDir).filter((f) => /\.jsx?$/.test(f))
const problems = []
const warnings = []
let importCount = 0

for (const file of files) {
  const rel = relative(root, file)
  const raw = readFileSync(file, 'utf8')
  const text = stripComments(raw)
  for (const m of text.matchAll(/import\s+([^'";]+?)\s+from\s+['"]([^'"]+)['"]|import\s+['"]([^'"]+)['"]/g)) {
    const spec = m[2] ?? m[3]
    if (!spec || !spec.startsWith('.')) continue
    importCount += 1
    const target = resolve(dirname(file), spec)
    if (!existsSync(target) || statSync(target).isDirectory()) {
      problems.push(`${rel}: "${spec}" does not exist`)
      continue
    }
    if (!/\.(jsx?|mjs)$/.test(target)) continue // css, json, images: existence is enough
    const clause = m[1]
    if (!clause) continue
    const ex = exportsOf(target)
    const braces = clause.match(/\{([^}]*)\}/)
    const defaultPart = clause.replace(/\{[^}]*\}/, '').replace(/,/g, '').trim()
    if (defaultPart && !defaultPart.startsWith('*') && !ex.hasDefault) {
      problems.push(`${rel}: "${spec}" has no default export, but "${defaultPart}" is imported as default`)
    }
    if (braces) {
      for (const part of braces[1].split(',')) {
        const bit = part.trim()
        if (!bit) continue
        const [name, local = name] = bit.split(/\s+as\s+/).map((s) => s.trim())
        if (!ex.names.has(name)) problems.push(`${rel}: "${name}" is not exported by "${spec}"`)
        const uses = text.replace(/import\s+[^'";]+?\s+from\s+['"][^'"]+['"]/g, '').replace(/import\s+['"][^'"]+['"]/g, '').match(new RegExp(`(?<![\\w$.])${local.replace('$', '\\$')}(?![\\w$])`, 'g'))
        if (!uses) warnings.push(`${rel}: "${local}" is imported but never used`)
      }
    }
    if (defaultPart && !defaultPart.startsWith('*')) {
      const uses = text.replace(/import\s+[^'";]+?\s+from\s+['"][^'"]+['"]/g, '').replace(/import\s+['"][^'"]+['"]/g, '').match(new RegExp(`(?<![\\w$.])${defaultPart.replace('$', '\\$')}(?![\\w$])`, 'g'))
      if (!uses) warnings.push(`${rel}: "${defaultPart}" is imported but never used`)
    }
  }
}

console.log(`Checked ${files.length} file(s), ${importCount} relative import(s).`)
for (const w of warnings) console.log(`  warning: ${w}`)
if (problems.length) {
  console.error(`FOUND ${problems.length} problem(s):`)
  for (const p of problems) console.error(`  - ${p}`)
  process.exit(1)
}
console.log('No missing files or missing exports found.' + (warnings.length ? ` (${warnings.length} warning(s) above)` : ''))
