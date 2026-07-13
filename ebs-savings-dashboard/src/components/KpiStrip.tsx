import Box from '@cloudscape-design/components/box';
import ColumnLayout from '@cloudscape-design/components/column-layout';
import Container from '@cloudscape-design/components/container';
import { formatCurrency, formatNumber } from '../utils/formatters';

interface KpiStripProps {
  totalSaved: number;
  monthlyBefore: number;
  monthlyAfter: number;
  volumesDeleted: number;
  projectedAnnual: number;
}

function Kpi({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <Box>
      <Box variant="awsui-key-label">{label}</Box>
      <Box variant="h2" color="text-status-success" fontSize="heading-xl">
        {value}
      </Box>
      {sub && (
        <Box variant="small" color="text-body-secondary">
          {sub}
        </Box>
      )}
    </Box>
  );
}

export default function KpiStrip({
  totalSaved,
  monthlyBefore,
  monthlyAfter,
  volumesDeleted,
  projectedAnnual,
}: KpiStripProps) {
  const monthlySavings = monthlyBefore - monthlyAfter;
  const pctReduction = monthlyBefore > 0 ? ((monthlySavings / monthlyBefore) * 100).toFixed(1) : '0';

  return (
    <Container>
      <ColumnLayout columns={5} variant="text-grid">
        <Kpi
          label="Total Saved (Cumulative)"
          value={formatCurrency(totalSaved)}
          sub="Since cleanup began"
        />
        <Kpi
          label="Monthly Spend (Before)"
          value={formatCurrency(monthlyBefore)}
          sub="Pre-cleanup baseline"
        />
        <Kpi
          label="Monthly Spend (After)"
          value={formatCurrency(monthlyAfter)}
          sub={`↓ ${pctReduction}% reduction`}
        />
        <Kpi
          label="Volumes Deleted"
          value={formatNumber(volumesDeleted)}
          sub="Unattached / stale EBS"
        />
        <Kpi
          label="Projected Annual Savings"
          value={formatCurrency(projectedAnnual)}
          sub="At current run rate"
        />
      </ColumnLayout>
    </Container>
  );
}
