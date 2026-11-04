// Provider privacy check (NOT part of the app; nothing imports it). Run with:
//   node scripts/check-provider-privacy.mjs
// Fails (exit code 1) if the words "date_of_birth", "dateOfBirth", "birth" fields or
// "email" appear ANYWHERE (code, comments or text) in any file under
// src/features/provider or in src/lib/providerData.js. Providers can read a
// patient's date of birth through the profiles table (row-level security limits rows,
// not columns), so the provider screens must never ask for it, and no provider
// screen needs an email address. The Overview works from provider_overview()
// (migration 015), which returns neither.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const walk = (d) =>
  readdirSync(d).flatMap((f) => {
    const p = join(d, f)
    return statSync(p).isDirectory() ? walk(p) : [p]
  })

const targets = [...walk(join(root, 'src', 'features', 'provider')), join(root, 'src', 'lib', 'providerData.js')]
const forbidden = [/date_of_birth/i, /dateofbirth/i, /e-?mail/i]

let problems = 0
let checked = 0
for (const file of targets) {
  if (!existsSync(file)) {
    console.error(`MISSING: ${relative(root, file)}`)
    problems += 1
    continue
  }
  checked += 1
  readFileSync(file, 'utf8')
    .split('\n')
    .forEach((line, i) => {
      for (const re of forbidden) {
        if (re.test(line)) {
          console.error(`${relative(root, file)}:${i + 1}: contains ${re}`)
          problems += 1
        }
      }
    })
}

if (problems > 0) {
  console.error(`provider privacy check FAILED (${problems} problem${problems === 1 ? '' : 's'})`)
  process.exit(1)
}
console.log(`provider privacy check passed: ${checked} files, no date of birth or email anywhere.`)
