import Container from '@cloudscape-design/components/container';
import Header from '@cloudscape-design/components/header';
import Table from '@cloudscape-design/components/table';
import Box from '@cloudscape-design/components/box';
import SpaceBetween from '@cloudscape-design/components/space-between';
import { useCollection } from '@cloudscape-design/collection-hooks';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';
import { formatCurrency, formatNumber } from '../utils/formatters';
import type { RegionRow } from '../data/mock';

interface RegionTableProps {
  regions: RegionRow[];
}

export default function RegionTable({ regions }: RegionTableProps) {
  const { items, collectionProps } = useCollection(regions, {
    sorting: {
      defaultState: { sortingColumn: { sortingField: 'savings' }, isDescending: true },
    },
  });

  return (
    <SpaceBetween size="l">
      <Container header={<Header variant="h2">Savings by Region (Bar Chart)</Header>}>
        <ResponsiveContainer width="100%" height={260}>
          <BarChart data={regions} margin={{ top: 10, right: 20, left: 20, bottom: 10 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#e9ebed" />
            <XAxis dataKey="region" tick={{ fontSize: 11 }} />
            <YAxis tickFormatter={(v) => `$${(v / 1000).toFixed(0)}k`} tick={{ fontSize: 11 }} />
            <Tooltip formatter={(v: number) => formatCurrency(v)} />
            <Bar dataKey="savings" name="Savings" fill="#067f68" radius={[4, 4, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </Container>

      <Table
        {...collectionProps}
        items={items}
        header={<Header variant="h2">Savings by Region</Header>}
        columnDefinitions={[
          { id: 'region',          header: 'Region',           cell: (r) => r.region,                                                  sortingField: 'region'          },
          { id: 'before',          header: 'Monthly (Before)', cell: (r) => formatCurrency(r.before),                                  sortingField: 'before'          },
          { id: 'after',           header: 'Monthly (After)',  cell: (r) => formatCurrency(r.after),                                   sortingField: 'after'           },
          {
            id: 'savings',
            header: 'Monthly Savings',
            cell: (r) => <Box color="text-status-success" variant="strong">{formatCurrency(r.savings)}</Box>,
            sortingField: 'savings',
          },
          { id: 'volumes_deleted', header: 'Volumes Deleted',  cell: (r) => formatNumber(r.volumes_deleted),                           sortingField: 'volumes_deleted' },
        ]}
        variant="embedded"
      />
    </SpaceBetween>
  );
}
