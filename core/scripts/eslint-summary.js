#!/usr/bin/env node
/**
 * Prints a fixed-format summary of an `eslint -f json` report, so the runner agent copies
 * numbers instead of counting them (Haiku drops items when it condenses a large set).
 * Usage: node .claude/scripts/eslint-summary.js <eslint.json> [changed-path ...]
 * Exit: 0 summary printed (whatever the lint result) · 64 usage · 65 unreadable report.
 */
const fs = require('fs')
const path = require('path')

const ROOT = path.resolve(__dirname, '../..')
const TOP_RULES = 10
const MAX_ERROR_FILES = 30
const MAX_CHANGED_ERRORS = 20 // per changed file; the rest become one CHANGED_ERROR_MORE line
const MAX_NOT_LINTED = 20

const [, , reportPath, ...changedArgs] = process.argv
if (!reportPath) {
  console.error('usage: eslint-summary.js <eslint.json> [changed-path ...]')
  process.exit(64)
}

let results
try {
  results = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
  if (!Array.isArray(results)) throw new Error('not an eslint -f json array')
} catch (e) {
  console.error(`eslint-summary: cannot read ${reportPath}: ${e.message}`)
  process.exit(65)
}

// Does a linted file (repo-relative, forward slashes) count as "changed" for one CLI argument?
// Arguments usually come from `git diff --name-only <base>`, so they are repo-relative too.
// A directory argument matches every file under it, on a `/` boundary so `src/a` never matches
// `src/ab.ts`. `./x`, absolute paths and trailing slashes normalise to the same form.
function matchesChanged(relPath, arg) {
  const want = path.relative(ROOT, path.resolve(ROOT, arg)).split(path.sep).join('/')
  if (!want || want.startsWith('..')) return false // the repo root itself, or outside the repo
  return relPath === want || relPath.startsWith(`${want}/`)
}

const rel = (abs) => path.relative(ROOT, abs).split(path.sep).join('/')
const isError = (m) => m.severity === 2
// A null ruleId is a parse error only when fatal; otherwise it's a rule-less notice (e.g. "file ignored").
const ruleOf = (m) => m.ruleId || (m.fatal ? '(parse error)' : '(no rule)')
// One fact per line: collapse a multi-line message.
const oneLine = (t) => String(t).replace(/\s+/g, ' ').trim()

let errors = 0
let warnings = 0
let fatal = 0
const byRule = new Map() // ruleId -> { errors, warnings }
const errorFiles = []
const changed = []

for (const r of results) {
  const file = rel(r.filePath)
  errors += r.errorCount
  warnings += r.warningCount
  for (const m of r.messages) {
    if (m.fatal) fatal++
    const id = ruleOf(m)
    const tally = byRule.get(id) || { errors: 0, warnings: 0 }
    isError(m) ? tally.errors++ : tally.warnings++
    byRule.set(id, tally)
  }
  if (r.errorCount) errorFiles.push({ file, errors: r.errorCount })
  if (changedArgs.some((arg) => matchesChanged(file, arg))) changed.push({ file, r })
}

console.log(
  `TOTAL errors=${errors} warnings=${warnings} files=${results.length} ` +
    `files_with_errors=${errorFiles.length} fatal=${fatal}`
)

const rules = [...byRule].sort((a, b) => b[1].errors - a[1].errors || b[1].warnings - a[1].warnings)
for (const [id, t] of rules.slice(0, TOP_RULES)) {
  console.log(`RULE ${id} errors=${t.errors} warnings=${t.warnings}`)
}
if (rules.length > TOP_RULES) console.log(`RULE_MORE ${rules.length - TOP_RULES}`)

errorFiles.sort((a, b) => b.errors - a.errors || a.file.localeCompare(b.file))
for (const f of errorFiles.slice(0, MAX_ERROR_FILES)) console.log(`ERROR_FILE ${f.file} errors=${f.errors}`)
if (errorFiles.length > MAX_ERROR_FILES) console.log(`ERROR_FILE_MORE ${errorFiles.length - MAX_ERROR_FILES}`)

for (const { file, r } of changed) {
  console.log(`CHANGED ${file} errors=${r.errorCount} warnings=${r.warningCount}`)
  const errs = r.messages.filter(isError)
  for (const m of errs.slice(0, MAX_CHANGED_ERRORS)) {
    console.log(`CHANGED_ERROR ${file}:${m.line}:${m.column} ${ruleOf(m)} ${oneLine(m.message)}`)
  }
  if (errs.length > MAX_CHANGED_ERRORS) console.log(`CHANGED_ERROR_MORE ${file} ${errs.length - MAX_CHANGED_ERRORS}`)
}
// A changed path that matched no linted file was ignored by .eslintignore or isn't JS/TS.
const notLinted = changedArgs.filter((arg) => !results.some((r) => matchesChanged(rel(r.filePath), arg)))
for (const arg of notLinted.slice(0, MAX_NOT_LINTED)) console.log(`CHANGED_NOT_LINTED ${arg}`)
if (notLinted.length > MAX_NOT_LINTED) console.log(`CHANGED_NOT_LINTED_MORE ${notLinted.length - MAX_NOT_LINTED}`)
