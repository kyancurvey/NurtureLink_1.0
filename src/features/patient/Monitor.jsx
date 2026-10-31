import { Component, Suspense, lazy, useEffect, useMemo, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import {
  AlertTriangleIcon,
  Button,
  Card,
  CheckIcon,
  InfoIcon,
  Modal,
  PageHeader,
  TextField,
  Toast,
} from '../../components/ui/index.js'
import { useAuth } from '../../lib/auth.jsx'
import { formatManilaDateTime } from '../../lib/dates.js'
import { friendlyError } from '../../lib/errors.js'
import {
  HISTORY_PAGE,
  MANUAL_LIMITS,
  confidenceLevel,
  newManualIds,
  saveManualReading,
  useBeltHistory,
  useHomeStatus,
  useNormalRanges,
  useProviderAssigned,
  useTrends,
} from '../../lib/patientData.js'
import { buildSeries, chartDomain, isOutside, makeTicks, needsBeltHelp } from './trendData.js'
import './monitor.css'

// Patient > Monitor. Trend charts, the check history, "Adjust belt" guidance
// and manual entry for when the device is offline.
// Rules this screen follows:
//  - The normal range (shaded band) always comes from alert_thresholds through
//    my_normal_ranges(); no limit is written in this file.
//  - A signal-lost check or a long pause is a GAP: no line is drawn across it.
//  - A value outside the normal range gets a triangle marker and words, not only a color.
//  - Hand-typed readings are labeled self-reported and are saved by the database
//    with source 'manual' and the server time. Whether they raise an alert is
//    decided by the same database trigger as every other reading.
//  - Monitoring and screening, not diagnosis: the disclaimer is always shown.

// The charting library is a separate download, fetched only when a chart is shown.
const TrendChart = lazy(() => import('./MonitorCharts.jsx'))

const RANGES = ['day', 'week', 'month']
const FALLBACK_GAP_HOURS = 14 // used only until my_home_status() has said what the freshness window is

// If the chart download fails (for example no signal), the rest of the screen,
// including manual entry, must keep working.
class ChartBoundary extends Component {
  constructor(props) {
    super(props)
    this.state = { failed: false }
  }
  static getDerivedStateFromError() {
    return { failed: true }
  }
  render() {
    if (this.state.failed) return this.props.fallback
    return this.props.children
  }
}

// Shows a loading line or a calm error with a retry, otherwise the content.
function Block({ q, children }) {
  const { t } = useTranslation()
  if (q.error) {
    const { text, detail } = friendlyError(t, q.error)
    return (
      <div className="nl-mon__problem" role="alert">
        <p>{text}</p>
        {detail && <p className="nl-mon__muted">{t('errors:technical_detail', { detail })}</p>}
        <Button variant="secondary" onClick={q.reload}>
          {t('errors:retry')}
        </Button>
      </div>
    )
  }
  if (!q.loaded) {
    return (
      <p className="nl-mon__muted" role="status">
        {t('ui.loading')}
      </p>
    )
  }
  return children
}

function RangeSwitch({ range, onChange }) {
  const { t } = useTranslation()
  return (
    <div className="nl-mon__ranges" role="group" aria-label={t('patient:monitor.range.label')}>
      <span className="nl-mon__ranges-label">{t('patient:monitor.range.label')}</span>
      {RANGES.map((r) => (
        <button
          key={r}
          type="button"
          className="nl-mon__range"
          aria-pressed={range === r}
          onClick={() => onChange(r)}
        >
          {range === r && <CheckIcon size={18} />}
          {t(`patient:monitor.range.${r}`)}
        </button>
      ))}
    </div>
  )
}

// Small copies of the chart markers, so the legend matches the chart.
function LegendDot() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true" focusable="false">
      <circle className="nl-mon__pt" cx="9" cy="9" r="3.5" />
    </svg>
  )
}
function LegendOut() {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" aria-hidden="true" focusable="false">
      <path className="nl-mon__out-shape" d="M10 2L19.5 18.5H0.5Z" />
      <path className="nl-mon__out-mark" d="M10 8V13" />
      <circle className="nl-mon__out-dot" cx="10" cy="15.6" r="1" />
    </svg>
  )
}
function LegendGap() {
  return (
    <svg width="22" height="18" viewBox="0 0 22 18" aria-hidden="true" focusable="false">
      <path className="nl-mon__gapmark" d="M1 9H6M16 9H21" />
    </svg>
  )
}

// The sentence under a chart about the shaded band.
function bandSentence(t, ranges, band, unit, decimals) {
  if (ranges.error) return t('patient:monitor.band.unavailable')
  if (!band || (band.min == null && band.max == null)) return t('patient:monitor.band.none')
  const f = (v) => (decimals ? Number(v).toFixed(decimals) : String(v))
  const text =
    band.min != null && band.max != null
      ? t('patient:monitor.band.both', { min: f(band.min), max: f(band.max), unit })
      : band.min != null
        ? t('patient:monitor.band.minOnly', { min: f(band.min), unit })
        : t('patient:monitor.band.maxOnly', { max: f(band.max), unit })
  return t(band.confirmed ? 'patient:monitor.band.confirmed' : 'patient:monitor.band.default', { range: text })
}

function MeasureChart({ title, unit, kind, field, rows, band, ranges, trends, gapMs, decimals = 0, language, range }) {
  const { t } = useTranslation()
  const series = useMemo(() => buildSeries(rows, field, band, gapMs), [rows, field, band, gapMs])
  const view = useMemo(
    () => (series.valueCount > 0 ? chartDomain(series.points, band, kind) : null),
    [series, band, kind],
  )
  const ticks = useMemo(() => makeTicks(trends.since, trends.until, range), [trends.since, trends.until, range])
  const rangeLong = t(`patient:monitor.range.${range}Long`)
  const hasBand = view && view.area

  return (
    <Card title={title}>
      {!view ? (
        <p className="nl-mon__muted">{t('patient:monitor.chart.none')}</p>
      ) : (
        <>
          <div
            role="img"
            aria-label={t('patient:monitor.chart.aria', { title, range: rangeLong, count: series.valueCount })}
          >
            <ChartBoundary
              fallback={
                <div className="nl-mon__problem" role="alert">
                  <p>{t('patient:monitor.chart.failed')}</p>
                  <Button variant="secondary" onClick={() => window.location.reload()}>
                    {t('patient:monitor.chart.reload')}
                  </Button>
                </div>
              }
            >
              <Suspense
                fallback={
                  <p className="nl-mon__muted nl-mon__plot" role="status">
                    {t('ui.loading')}
                  </p>
                }
              >
                <TrendChart
                  points={series.points}
                  domain={view.domain}
                  yTicks={view.yTicks}
                  area={view.area}
                  ticks={ticks}
                  since={trends.since}
                  until={trends.until}
                  range={range}
                  language={language}
                  unit={unit}
                  decimals={decimals}
                  outsideText={t('patient:monitor.chart.outside')}
                  sourceText={(s) => t(`patient:monitor.source.${s}`)}
                />
              </Suspense>
            </ChartBoundary>
          </div>
          <ul className="nl-mon__legend">
            <li>
              <LegendDot />
              {hasBand ? t('patient:monitor.legend.inRange') : t('patient:monitor.chart.shown', { count: series.valueCount })}
            </li>
            {hasBand && (
              <>
                <li>
                  <LegendOut />
                  {t('patient:monitor.legend.outside')}
                </li>
                <li>
                  <span className="nl-mon__swatch" aria-hidden="true" />
                  {t('patient:monitor.legend.band')}
                </li>
              </>
            )}
            <li>
              <LegendGap />
              {t('patient:monitor.legend.gap')}
            </li>
          </ul>
        </>
      )}
      <div className="nl-mon__notes">
        {view && series.lost > 0 && (
          <p className="nl-mon__warnnote">
            <AlertTriangleIcon size={18} />
            <span>{t('patient:monitor.chart.lost', { count: series.lost })}</span>
          </p>
        )}
        {view && series.outCount > 0 && (
          <p className="nl-mon__flag">
            <AlertTriangleIcon size={18} />
            <span>{t('patient:monitor.chart.out', { count: series.outCount })}</span>
          </p>
        )}
        <p className="nl-mon__muted">{bandSentence(t, ranges, band, unit, decimals)}</p>
        {trends.truncated && <p className="nl-mon__muted">{t('patient:monitor.chart.truncated')}</p>}
      </div>
    </Card>
  )
}

function BeltGuidance({ rows, language }) {
  const { t } = useTranslation()
  return (
    <section className="nl-mon__belt" aria-labelledby="nl-mon-belt-title">
      <div className="nl-mon__belt-head">
        <AlertTriangleIcon size={28} />
        <h2 id="nl-mon-belt-title" className="nl-mon__belt-title">
          {t('patient:monitor.belt.title')}
        </h2>
      </div>
      <p>{t('patient:monitor.belt.intro', { date: formatManilaDateTime(rows[0].measured_at, language) })}</p>
      <ol>
        {[1, 2, 3, 4, 5].map((n) => (
          <li key={n}>{t(`patient:monitor.belt.step${n}`)}</li>
        ))}
      </ol>
      <p className="nl-mon__belt-worried">{t('patient:monitor.belt.worried')}</p>
    </section>
  )
}

function HistoryCard({ q, limit, onMore, ranges, language }) {
  const { t } = useTranslation()
  const rows = q.data ?? []
  const shown = rows.slice(0, limit)
  const band = ranges.data?.fhr
  return (
    <Card title={t('patient:monitor.history.title')}>
      <Block q={q}>
        {shown.length === 0 ? (
          <p className="nl-mon__muted">{t('patient:monitor.history.none')}</p>
        ) : (
          <>
            <ul className="nl-mon__hist">
              {shown.map((r) => {
                const lost = r.signal_lost === true
                const level = confidenceLevel(r.signal_quality)
                return (
                  <li key={r.id} className="nl-mon__row">
                    <p className="nl-mon__when">{formatManilaDateTime(r.measured_at, language)}</p>
                    <p>
                      <span className="nl-mon__lbl">{t('patient:monitor.history.fhr')}</span>
                      {lost ? (
                        <span className="nl-mon__warnnote">
                          <AlertTriangleIcon size={18} />
                          <span>{t('patient:monitor.history.signalLost')}</span>
                        </span>
                      ) : (
                        <>
                          <strong>
                            {r.fetal_hr_bpm} {t('patient:home.unit.bpm')}
                          </strong>
                          {isOutside(r.fetal_hr_bpm, band) && (
                            <span className="nl-mon__flag">
                              <AlertTriangleIcon size={18} />
                              <span>{t('patient:monitor.history.outside')}</span>
                            </span>
                          )}
                        </>
                      )}
                    </p>
                    <p>
                      <span className="nl-mon__lbl">{t('patient:monitor.history.quality')}</span>
                      {level
                        ? t('patient:monitor.history.qualityValue', {
                            level: t(`patient:home.confidence.${level}`),
                            percent: r.signal_quality,
                          })
                        : t('patient:monitor.history.qualityNone')}
                    </p>
                    <p>
                      <span className="nl-mon__lbl">{t('patient:monitor.history.source')}</span>
                      {t(`patient:monitor.source.${r.source}`)}
                    </p>
                  </li>
                )
              })}
            </ul>
            {rows.length > limit && (
              <div className="nl-mon__more">
                <Button variant="secondary" onClick={onMore} disabled={q.loading}>
                  {q.loading ? t('ui.loading') : t('patient:monitor.history.more')}
                </Button>
              </div>
            )}
          </>
        )}
      </Block>
    </Card>
  )
}

// ---------- Manual entry ----------

const FIELDS = [
  { key: 'fhr', limit: MANUAL_LIMITS.fhr, labelKey: 'patient:home.fhr.title', unitKey: 'patient:home.unit.bpm', required: true, mode: 'numeric', decimals: 0 },
  { key: 'hr', limit: MANUAL_LIMITS.hr, labelKey: 'patient:home.vitals.hr', unitKey: 'patient:home.unit.bpm', required: false, mode: 'numeric', decimals: 0 },
  { key: 'spo2', limit: MANUAL_LIMITS.spo2, labelKey: 'patient:home.vitals.spo2', unitKey: 'patient:home.unit.percent', required: false, mode: 'numeric', decimals: 0 },
  { key: 'temp', limit: MANUAL_LIMITS.temp, labelKey: 'patient:home.vitals.temp', unitKey: 'patient:home.unit.celsius', required: false, mode: 'decimal', decimals: 1 },
]

// Returns { value } (a number, or null for an empty optional field) or { error } (an i18n key).
function parseField(raw, f) {
  const text = String(raw).trim().replace(',', '.')
  if (text === '') return f.required ? { error: 'errRequired' } : { value: null }
  if (!/^\d+(\.\d+)?$/.test(text)) return { error: 'errNumber' }
  const n = Number(text)
  if (f.decimals === 0 && !Number.isInteger(n)) return { error: 'errWhole' }
  const value = f.decimals ? Math.round(n * 10) / 10 : n
  if (value < f.limit.min || value > f.limit.max) return { error: 'errRange' }
  return { value }
}

function ManualCard({ onSaved, onNotice, assigned, ranges }) {
  const { t } = useTranslation()
  const { profile } = useAuth()
  const [form, setForm] = useState({ fhr: '', hr: '', spo2: '', temp: '' })
  const [errors, setErrors] = useState({})
  const [confirm, setConfirm] = useState(false)
  const [saving, setSaving] = useState(false)
  const parsed = useRef({})
  const ids = useRef(newManualIds())
  const busy = useRef(false) // changes at once, so two quick taps cannot both save

  function onReview(e) {
    e.preventDefault()
    const errs = {}
    const values = {}
    for (const f of FIELDS) {
      const r = parseField(form[f.key], f)
      if (r.error) errs[f.key] = r.error
      else values[f.key] = r.value
    }
    setErrors(errs)
    if (Object.keys(errs).length > 0) return
    parsed.current = values
    setConfirm(true)
  }

  async function onSave() {
    if (busy.current || !profile) return
    busy.current = true
    setSaving(true)
    const values = parsed.current
    const { error, savedBelt } = await saveManualReading({ patientId: profile.id, values, ids: ids.current })
    busy.current = false
    setSaving(false)
    setConfirm(false)
    if (error) {
      const text = friendlyError(t, error).text
      onNotice({ variant: 'danger', text: savedBelt ? `${t('patient:monitor.manual.partial')} ${text}` : text })
      onSaved() // show what was saved; the form keeps its values and ids so a retry cannot double anything
      return
    }
    ids.current = newManualIds()
    setForm({ fhr: '', hr: '', spo2: '', temp: '' })
    const r = ranges.data
    const outside =
      isOutside(values.fhr, r?.fhr) || isOutside(values.spo2, r?.spo2) || isOutside(values.temp, r?.temp)
    if (outside) {
      onNotice({
        variant: 'warning',
        text: [
          t('patient:monitor.manual.saved'),
          t('patient:monitor.manual.outOfRange'),
          assigned === true ? '' : t('patient:home.guidance.noProvider'),
        ]
          .filter(Boolean)
          .join(' '),
      })
    } else {
      onNotice({ variant: 'success', text: t('patient:monitor.manual.saved') })
    }
    onSaved()
  }

  const labelOf = (f) => `${t(f.labelKey)} (${t(f.unitKey)}${f.required ? '' : `, ${t('patient:monitor.manual.optional')}`})`

  return (
    <Card title={t('patient:monitor.manual.title')}>
      <form className="nl-mon__form" onSubmit={onReview} noValidate>
        <p>{t('patient:monitor.manual.intro')}</p>
        <div className="nl-mon__note" role="note">
          <InfoIcon size={24} />
          <p>{t('patient:monitor.manual.selfReported')}</p>
        </div>
        {FIELDS.map((f) => (
          <TextField
            key={f.key}
            name={f.key}
            label={labelOf(f)}
            hint={t('patient:monitor.manual.hint', {
              min: f.decimals ? f.limit.min.toFixed(1) : f.limit.min,
              max: f.decimals ? f.limit.max.toFixed(1) : f.limit.max,
            })}
            inputMode={f.mode}
            autoComplete="off"
            value={form[f.key]}
            onChange={(e) => setForm((s) => ({ ...s, [f.key]: e.target.value }))}
            error={errors[f.key] ? t(`patient:monitor.manual.${errors[f.key]}`, { min: f.limit.min, max: f.limit.max }) : undefined}
          />
        ))}
        <Button type="submit" full>
          {t('patient:monitor.manual.review')}
        </Button>
      </form>

      <Modal
        open={confirm}
        onClose={() => {
          if (!saving) setConfirm(false)
        }}
        title={t('patient:monitor.manual.reviewTitle')}
        actions={
          <>
            <Button variant="secondary" onClick={() => setConfirm(false)} disabled={saving}>
              {t('patient:monitor.manual.back')}
            </Button>
            <Button onClick={onSave} disabled={saving}>
              {saving ? t('patient:monitor.manual.saving') : t('patient:monitor.manual.save')}
            </Button>
          </>
        }
      >
        <ul className="nl-mon__confirm">
          {FIELDS.filter((f) => parsed.current[f.key] !== null && parsed.current[f.key] !== undefined).map((f) => (
            <li key={f.key}>
              {t('patient:monitor.manual.line', {
                label: t(f.labelKey),
                value: f.decimals ? parsed.current[f.key].toFixed(1) : parsed.current[f.key],
                unit: t(f.unitKey),
              })}
            </li>
          ))}
        </ul>
        <p>{t('patient:monitor.manual.reviewBody')}</p>
        <p className="nl-mon__muted">{t('patient:monitor.manual.selfReported')}</p>
        <p className="nl-disclaimer">{t('disclaimer')}</p>
      </Modal>
    </Card>
  )
}

export default function Monitor() {
  const { t, i18n } = useTranslation()
  const language = i18n.language
  const [range, setRange] = useState('week')
  const [limit, setLimit] = useState(HISTORY_PAGE)
  const [notice, setNotice] = useState(null) // { variant, text }

  const status = useHomeStatus() // only for fresh_hours, the pause that counts as a gap
  const ranges = useNormalRanges()
  const trends = useTrends(range)
  const history = useBeltHistory(limit)
  const provider = useProviderAssigned()

  // Fetch everything again when the person comes back to the app.
  const reloadAll = () => [status, ranges, trends, history, provider].forEach((q) => q.reload())
  const reloadRef = useRef(reloadAll)
  reloadRef.current = reloadAll
  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState === 'visible') reloadRef.current()
    }
    document.addEventListener('visibilitychange', onVisible)
    return () => document.removeEventListener('visibilitychange', onVisible)
  }, [])

  const rows = history.data ?? []
  const nothingYet = history.loaded && !history.error && rows.length === 0
  const gapMs = (status.data?.fresh_hours ?? FALLBACK_GAP_HOURS) * 60 * 60 * 1000
  const t0 = trends.data && trends.data.range === range ? trends.data : null
  const chartsReady = t0 && ranges.loaded
  const chartProps = { trends: t0, ranges, gapMs, language, range }

  return (
    <>
      <PageHeader title={t('patient:tabs.monitor')} />
      <div className="nl-mon">
        {notice && (
          <div className="nl-mon__notice">
            <Toast variant={notice.variant} onDismiss={() => setNotice(null)}>
              {notice.text}
            </Toast>
          </div>
        )}

        {needsBeltHelp(rows) && <BeltGuidance rows={rows} language={language} />}

        {nothingYet ? (
          <section className="nl-mon__empty" role="note">
            <InfoIcon size={24} />
            <div>
              <h2 className="nl-mon__empty-title">{t('patient:monitor.empty.title')}</h2>
              <p>{t('patient:monitor.empty.body')}</p>
            </div>
          </section>
        ) : (
          <>
            <RangeSwitch range={range} onChange={setRange} />
            {trends.error ? (
              <Block q={trends}>{null}</Block>
            ) : !chartsReady ? (
              <p className="nl-mon__muted" role="status">
                {t('ui.loading')}
              </p>
            ) : (
              <div className="nl-mon__grid">
                <div className="nl-mon__wide">
                  <MeasureChart
                    {...chartProps}
                    title={t('patient:home.fhr.title')}
                    unit={t('patient:home.unit.bpm')}
                    kind="fhr"
                    field="fetal_hr_bpm"
                    rows={t0.belt}
                    band={ranges.data?.fhr}
                  />
                </div>
                <div className="nl-mon__wide nl-mon__vitals">
                  <MeasureChart
                    {...chartProps}
                    title={t('patient:home.vitals.hr')}
                    unit={t('patient:home.unit.bpm')}
                    kind="hr"
                    field="heart_rate_bpm"
                    rows={t0.vitals}
                    band={undefined}
                  />
                  <MeasureChart
                    {...chartProps}
                    title={t('patient:home.vitals.spo2')}
                    unit={t('patient:home.unit.percent')}
                    kind="spo2"
                    field="spo2_percent"
                    rows={t0.vitals}
                    band={ranges.data?.spo2}
                  />
                  <MeasureChart
                    {...chartProps}
                    title={t('patient:home.vitals.temp')}
                    unit={t('patient:home.unit.celsius')}
                    kind="temp"
                    field="temperature_c"
                    rows={t0.vitals}
                    band={ranges.data?.temp}
                    decimals={1}
                  />
                </div>
              </div>
            )}
          </>
        )}

        <div className="nl-mon__grid">
          <HistoryCard q={history} limit={limit} onMore={() => setLimit((n) => n + HISTORY_PAGE)} ranges={ranges} language={language} />
          <ManualCard
            ranges={ranges}
            assigned={provider.assigned}
            onNotice={setNotice}
            onSaved={reloadAll}
          />
        </div>

        <p className="nl-disclaimer">{t('disclaimer')}</p>
      </div>
    </>
  )
}
