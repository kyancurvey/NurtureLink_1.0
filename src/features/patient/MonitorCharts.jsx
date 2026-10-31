import {
  CartesianGrid,
  Line,
  LineChart,
  ReferenceArea,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { formatManilaDateTime, formatManilaTick } from '../../lib/dates.js'

// ONE trend chart. This is the only file that imports Recharts, and Monitor.jsx
// loads it with React.lazy, so the charting library is a separate download that
// is fetched only when the Monitor tab shows a chart.
//
// The line is drawn only between consecutive real values. A point with v = null
// (signal lost, or a long pause) breaks the line, so nothing is drawn across it.
// A value outside the normal range is drawn as a triangle with an exclamation
// mark (a different SHAPE, not only a different color); the normal range is the
// shaded band. Colors come from CSS variables in monitor.css.

// Each point is a round dot; an outside-the-range point is a triangle with "!".
function renderDot({ cx, cy, payload }) {
  if (cx == null || cy == null || payload?.v == null) return null
  if (payload.out) {
    return (
      <g key={`o${payload.t}`} className="nl-mon__out">
        <path className="nl-mon__out-shape" d={`M${cx} ${cy - 10}L${cx + 9.5} ${cy + 7}L${cx - 9.5} ${cy + 7}Z`} />
        <path className="nl-mon__out-mark" d={`M${cx} ${cy - 4}V${cy + 1}`} />
        <circle className="nl-mon__out-dot" cx={cx} cy={cy + 4.2} r="1" />
      </g>
    )
  }
  return <circle key={`p${payload.t}`} className="nl-mon__pt" cx={cx} cy={cy} r="3.5" />
}

function Tip({ active, payload, language, unit, decimals, outsideText, sourceText }) {
  const p = active && payload && payload[0] ? payload[0].payload : null
  if (!p || p.v == null) return null
  return (
    <div className="nl-mon__tip">
      <strong>
        {Number(p.v).toFixed(decimals)} {unit}
      </strong>
      <span>{formatManilaDateTime(p.t, language)}</span>
      {p.source && <span>{sourceText(p.source)}</span>}
      {p.out && <span className="nl-mon__tip-out">{outsideText}</span>}
    </div>
  )
}

// A little room on both sides so a marker on the newest or oldest check is not cut in half.
export default function TrendChart({
  points,
  domain,
  yTicks,
  area,
  ticks,
  since,
  until,
  range,
  language,
  unit,
  decimals = 0,
  outsideText,
  sourceText,
}) {
  return (
    <div className="nl-mon__plot">
      <ResponsiveContainer width="100%" height={230}>
        <LineChart data={points} margin={{ top: 12, right: 14, bottom: 4, left: 0 }}>
          <CartesianGrid vertical={false} />
          {area && <ReferenceArea y1={area.y1} y2={area.y2} className="nl-mon__band" ifOverflow="hidden" />}
          <XAxis
            dataKey="t"
            type="number"
            scale="time"
            domain={[since - (until - since) * 0.02, until + (until - since) * 0.03]}
            ticks={ticks}
            tickFormatter={(ms) => formatManilaTick(ms, language, range)}
            allowDataOverflow
            tickMargin={6}
          />
          <YAxis
            domain={domain}
            ticks={yTicks}
            width={46}
            allowDecimals={decimals > 0}
            tickFormatter={(v) => Number(v).toFixed(decimals)}
          />
          <Tooltip
            isAnimationActive={false}
            content={
              <Tip language={language} unit={unit} decimals={decimals} outsideText={outsideText} sourceText={sourceText} />
            }
          />
          <Line
            className="nl-mon__line"
            type="linear"
            dataKey="v"
            strokeWidth={2.5}
            connectNulls={false}
            dot={renderDot}
            activeDot={false}
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
