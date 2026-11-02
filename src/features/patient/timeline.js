// The health record timeline (step 3.5): readings, alerts and appointments in one
// list, newest first. Pure functions, no React, no network.
//
// Each source is loaded with its own limit, so a plain merge could skip an older
// item of a source that was cut off while still showing newer items of another.
// To avoid a silent gap, items older than the HORIZON are left out. The horizon
// is the newest of the "oldest loaded item" times of the sources that were cut.

const time = (value) => {
  const ms = new Date(value).getTime()
  return Number.isNaN(ms) ? null : ms
}

// readings, alerts, appointments: arrays of rows (or null).
// cut: { readings, alerts, appointments } booleans, true if that source hit its limit.
// Returns { items, limited } where items is newest first:
//   { key, kind: 'reading' | 'alert' | 'appointment', at (ms), row }
// and limited is true when some older items may exist that are not listed.
export function buildTimeline({ readings, alerts, appointments, cut }) {
  const sources = [
    ['reading', readings, 'measured_at', cut?.readings],
    ['alert', alerts, 'created_at', cut?.alerts],
    ['appointment', appointments, 'starts_at', cut?.appointments],
  ]
  const items = []
  let horizon = null
  for (const [kind, rows, field, isCut] of sources) {
    let oldest = null
    for (const row of rows ?? []) {
      const at = time(row[field])
      if (at === null) continue
      items.push({ key: `${kind}:${row.id}`, kind, at, row })
      if (oldest === null || at < oldest) oldest = at
    }
    if (isCut && oldest !== null && (horizon === null || oldest > horizon)) horizon = oldest
  }
  const kept = horizon === null ? items : items.filter((i) => i.at >= horizon)
  kept.sort((a, b) => b.at - a.at || (a.key < b.key ? 1 : -1))
  return { items: kept, limited: horizon !== null }
}
