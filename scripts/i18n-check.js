// i18n check: fails (exit code 1) if en.json and fil.json do not match.
// Run with:  npm run i18n:check
//
// It checks that:
//   1. both files contain exactly the expected namespaces,
//   2. every key in one file exists in the other,
//   3. every value is a non-empty string,
//   4. {{placeholders}} are the same in both languages,
//   5. every key used in the code (t('...') and labelKey: '...') exists.
// It does not check that the Filipino is good. That is what
// docs/FILIPINO_REVIEW.md and your midwife or medical officer are for.
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const NAMESPACES = ['common', 'auth', 'terms', 'patient', 'provider', 'alerts', 'errors']
const LANGS = ['en', 'fil']
const dir = join(dirname(fileURLToPath(import.meta.url)), '..', 'src', 'locales')

const srcDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'src')

const errors = []
const files = {}

for (const lang of LANGS) {
  try {
    files[lang] = JSON.parse(readFileSync(join(dir, `${lang}.json`), 'utf8'))
  } catch (e) {
    errors.push(`${lang}.json cannot be read: ${e.message}`)
  }
}

// Turn nested objects into { 'common:ui.back': 'Back', ... }.
function flatten(obj, lang) {
  const out = {}
  for (const ns of Object.keys(obj)) {
    const walk = (node, path) => {
      if (typeof node === 'string') {
        out[`${ns}:${path}`] = node
      } else if (node && typeof node === 'object' && !Array.isArray(node)) {
        for (const k of Object.keys(node)) walk(node[k], path ? `${path}.${k}` : k)
      } else {
        errors.push(`${lang}.json: ${ns}:${path} must be a string, found ${Array.isArray(node) ? 'an array' : typeof node}`)
      }
    }
    const root = obj[ns]
    if (root && typeof root === 'object' && !Array.isArray(root)) {
      for (const k of Object.keys(root)) walk(root[k], k)
    } else {
      errors.push(`${lang}.json: namespace "${ns}" must be an object`)
    }
  }
  return out
}

if (errors.length === 0) {
  for (const lang of LANGS) {
    const found = Object.keys(files[lang]).sort().join(', ')
    if (found !== [...NAMESPACES].sort().join(', ')) {
      errors.push(`${lang}.json namespaces are [${found}], expected [${[...NAMESPACES].sort().join(', ')}]`)
    }
  }
}

let keyCount = 0
if (errors.length === 0) {
  const flat = { en: flatten(files.en, 'en'), fil: flatten(files.fil, 'fil') }
  keyCount = Object.keys(flat.en).length

  for (const key of Object.keys(flat.en)) {
    if (!(key in flat.fil)) errors.push(`Missing in fil.json: ${key}`)
  }
  for (const key of Object.keys(flat.fil)) {
    if (!(key in flat.en)) errors.push(`Missing in en.json:  ${key}`)
  }

  const placeholders = (s) => (s.match(/\{\{\s*[\w.]+\s*\}\}/g) || []).map((p) => p.replace(/\s/g, '')).sort().join(' ')
  for (const lang of LANGS) {
    for (const [key, value] of Object.entries(flat[lang])) {
      if (value.trim() === '') errors.push(`Empty value in ${lang}.json: ${key}`)
    }
  }
  for (const key of Object.keys(flat.en)) {
    if (key in flat.fil && placeholders(flat.en[key]) !== placeholders(flat.fil[key])) {
      errors.push(`Placeholders differ for ${key}: en "${placeholders(flat.en[key])}" vs fil "${placeholders(flat.fil[key])}"`)
    }
  }

  // 5. Keys used in the code must exist. Static keys are checked exactly.
  //    A key built with ${...} is checked only by its fixed prefix.
  const walk = (d) =>
    readdirSync(d).flatMap((f) => {
      const p = join(d, f)
      return statSync(p).isDirectory() ? walk(p) : [p]
    })
  const codeFiles = walk(srcDir).filter((f) => /\.jsx?$/.test(f))
  const patterns = [/\bt\(\s*(['"`])([^'"`]+)\1/g, /labelKey:\s*(['"`])([^'"`]+)\1/g]
  for (const file of codeFiles) {
    const text = readFileSync(file, 'utf8')
    const rel = file.slice(srcDir.length - 3).replace(/\\/g, '/')
    for (const re of patterns) {
      for (const m of text.matchAll(re)) {
        const raw = m[2]
        const [ns, path] = raw.includes(':') ? raw.split(':') : ['common', raw]
        const full = `${ns}:${path}`
        if (raw.includes('${')) {
          const prefix = `${ns}:${path.split('${')[0]}`
          if (!Object.keys(flat.en).some((k) => k.startsWith(prefix))) {
            errors.push(`Used in ${rel} but no key starts with: ${prefix}`)
          }
        } else if (!(full in flat.en)) {
          errors.push(`Used in ${rel} but missing from en.json and fil.json: ${full}`)
        }
      }
    }
  }
}

if (errors.length > 0) {
  console.error(`i18n check FAILED (${errors.length} problem${errors.length === 1 ? '' : 's'}):`)
  for (const e of errors) console.error(`  - ${e}`)
  process.exit(1)
}

console.log(`i18n check passed: ${keyCount} keys in en.json and fil.json, ${NAMESPACES.length} namespaces, all keys match.`)
