import Table from '@cloudscape-design/components/table';
import Header from '@cloudscape-design/components/header';
import Box from '@cloudscape-design/components/box';
import { useCollection } from '@cloudscape-design/collection-hooks';
import { formatCurrency, formatPercent } from '../utils/formatters';
import type { VolumeTypeRow } from '../data/mock';

interface VolumeTypeTableProps {
  volumeTypes: VolumeTypeRow[];
}

const TYPE_COLORS: Record<string, string> = {
  gp2: '#0972d3',
  gp3: '#067f68',
  io1: '#8456ce',
  st1: '#c7511f',
  sc1: '#aab7b8',
};

export default function VolumeTypeTable({ volumeTypes }: VolumeTypeTableProps) {
  const { items, collectionProps } = useCollection(volumeTypes, {
    sorting: {
      defaultState: { sortingColumn: { sortingField: 'savings' }, isDescending: true },
    },
  });

  return (
    <Table
      {...collectionProps}
      items={items}
      header={<Header variant="h2">Savings by Volume Type</Header>}
      columnDefinitions={[
        {
          id: 'volume_type',
          header: 'Volume Type',
          cell: (r) => (
            <Box>
              <span
                style={{
                  display: 'inline-block',
                  width: 10,
                  height: 10,
                  borderRadius: '50%',
                  background: TYPE_COLORS[r.volume_type] ?? '#aab7b8',
                  marginRight: 8,
                }}
              />
              <Box variant="strong" display="inline">
                {r.volume_type.toUpperCase()}
              </Box>
            </Box>
          ),
          sortingField: 'volume_type',
        },
        { id: 'before',       header: 'Monthly (Before)', cell: (r) => formatCurrency(r.before),                                                  sortingField: 'before'       },
        { id: 'after',        header: 'Monthly (After)',  cell: (r) => formatCurrency(r.after),                                                   sortingField: 'after'        },
        {
          id: 'savings',
          header: 'Monthly Savings',
          cell: (r) => <Box color="text-status-success" variant="strong">{formatCurrency(r.savings)}</Box>,
          sortingField: 'savings',
        },
        { id: 'price_per_gb', header: 'Price/GB-mo',      cell: (r) => `$${r.price_per_gb.toFixed(3)}`,                                          sortingField: 'price_per_gb' },
        { id: 'pct_of_total', header: '% of Total Savings', cell: (r) => formatPercent(r.pct_of_total),                                          sortingField: 'pct_of_total' },
      ]}
      variant="embedded"
    />
  );
}
