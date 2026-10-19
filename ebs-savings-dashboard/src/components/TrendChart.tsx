import Container from '@cloudscape-design/components/container';
import Header from '@cloudscape-design/components/header';
import Box from '@cloudscape-design/components/box';
import {
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ReferenceLine,
  Area,
  ComposedChart,
  ResponsiveContainer,
} from 'recharts';
import { formatCurrency, formatMonth } from '../utils/formatters';
import type { MonthlyTrend } from '../data/mock';

interface TrendChartProps {
  data: MonthlyTrend[];
  cleanupStartMonth: string;
}

function CustomTooltip({ active, payload, label }: any) {
  if (!active || !payload?.length) return null;
  return (
    <Box padding="s" variant="div">
      <div style={{ background: '#fff', border: '1px solid #d1d5db', borderRadius: 6, padding: '8px 12px' }}>
        <Box variant="strong">{formatMonth(label)}</Box>
        {payload.map((p: any) => (
          <div key={p.dataKey} style={{ color: p.color, marginTop: 2 }}>
            {p.name}: {formatCurrency(p.value)}
          </div>
        ))}
      </div>
    </Box>
  );
}

export default function TrendChart({ data, cleanupStartMonth }: TrendChartProps) {
  const chartData = data.map((d) => ({
    ...d,
    savings: d.spend < d.baseline ? d.baseline - d.spend : 0,
  }));

  return (
    <Container header={<Header variant="h2">Monthly EBS Spend vs. Baseline</Header>}>
      <ResponsiveContainer width="100%" height={340}>
        <ComposedChart data={chartData} margin={{ top: 10, right: 20, left: 20, bottom: 10 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e9ebed" />
          <XAxis
            dataKey="month"
            tickFormatter={formatMonth}
            tick={{ fontSize: 12 }}
            interval={1}
          />
          <YAxis
            tickFormatter={(v) => `$${(v / 1000).toFixed(0)}k`}
            tick={{ fontSize: 12 }}
          />
          <Tooltip content={<CustomTooltip />} />
          <Legend />
          {cleanupStartMonth && (
            <ReferenceLine
              x={cleanupStartMonth}
              stroke="#d13212"
              strokeDasharray="6 3"
              label={{ value: 'Cleanup Start', position: 'insideTopLeft', fontSize: 11, fill: '#d13212' }}
            />
          )}
          <Area
            type="monotone"
            dataKey="savings"
            name="Savings"
            fill="#067f68"
            fillOpacity={0.15}
            stroke="none"
          />
          <Line
            type="monotone"
            dataKey="baseline"
            name="Baseline"
            stroke="#aab7b8"
            strokeWidth={2}
            strokeDasharray="6 3"
            dot={false}
          />
          <Line
            type="monotone"
            dataKey="spend"
            name="Actual Spend"
            stroke="#0972d3"
            strokeWidth={2.5}
            dot={{ r: 3 }}
            activeDot={{ r: 5 }}
          />
        </ComposedChart>
      </ResponsiveContainer>
    </Container>
  );
}
