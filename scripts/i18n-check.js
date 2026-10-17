// i18n check: fails (exit code 1) if en.json and fil.json do not match.
// Run with:  npm run i18n:check
//
// It checks that:
//   1. both files contain exactly the expected namespaces,
//   2. every key in one file exists in the other,
//   3. every value is a non-empty string,
//   4. {{placeholders}} are the same in both languages.
// It does not check that the Filipino is good. That is what
// docs/FILIPINO_REVIEW.md and your midwife or medical officer are for.
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const NAMESPACES = ['common', 'auth', 'terms', 'patient', 'provider', 'alerts', 'errors']
const LANGS = ['en', 'fil']
const dir = join(dirname(fileURLToPath(import.meta.url)), '..', 'src', 'locales')

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
}

if (errors.length > 0) {
  console.error(`i18n check FAILED (${errors.length} problem${errors.length === 1 ? '' : 's'}):`)
  for (const e of errors) console.error(`  - ${e}`)
  process.exit(1)
}

console.log(`i18n check passed: ${keyCount} keys in en.json and fil.json, ${NAMESPACES.length} namespaces, all keys match.`)
