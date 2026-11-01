import Table from '@cloudscape-design/components/table';
import Header from '@cloudscape-design/components/header';
import Box from '@cloudscape-design/components/box';
import ProgressBar from '@cloudscape-design/components/progress-bar';
import { useCollection } from '@cloudscape-design/collection-hooks';
import { formatCurrency, formatNumber } from '../utils/formatters';
import type { AccountRow } from '../data/mock';

interface AccountsTableProps {
  accounts: AccountRow[];
}

export default function AccountsTable({ accounts }: AccountsTableProps) {
  const { items, collectionProps } = useCollection(accounts, {
    sorting: {
      defaultState: {
        sortingColumn: { sortingField: 'savings' },
        isDescending: true,
      },
    },
  });

  return (
    <Table
      {...collectionProps}
      items={items}
      header={
        <Header
          variant="h2"
          counter={`(${accounts.length})`}
        >
          Savings by Account
        </Header>
      }
      columnDefinitions={[
        {
          id: 'account_name',
          header: 'Account',
          cell: (row) => (
            <Box>
              <Box variant="strong">{row.account_name}</Box>
              {row.account_name !== row.account_id && (
                <Box variant="small" color="text-body-secondary">{row.account_id}</Box>
              )}
            </Box>
          ),
          sortingField: 'account_name',
          minWidth: 180,
        },
        {
          id: 'ou',
          header: 'OU',
          cell: (row) => row.ou,
          sortingField: 'ou',
        },
        {
          id: 'before',
          header: 'Monthly (Before)',
          cell: (row) => formatCurrency(row.before),
          sortingField: 'before',
        },
        {
          id: 'after',
          header: 'Monthly (After)',
          cell: (row) => formatCurrency(row.after),
          sortingField: 'after',
        },
        {
          id: 'savings',
          header: 'Monthly Savings',
          cell: (row) => (
            <Box color="text-status-success" variant="strong">
              {formatCurrency(row.savings)}
            </Box>
          ),
          sortingField: 'savings',
        },
        {
          id: 'pct_reduction',
          header: '% Reduction',
          cell: (row) => (
            <ProgressBar
              value={row.pct_reduction}
              additionalInfo={`${row.pct_reduction.toFixed(1)}%`}
              label=""
            />
          ),
          sortingField: 'pct_reduction',
          minWidth: 160,
        },
        {
          id: 'volumes_deleted',
          header: 'Volumes Deleted',
          cell: (row) => formatNumber(row.volumes_deleted),
          sortingField: 'volumes_deleted',
        },
      ]}
      sortingDisabled={false}
      variant="embedded"
    />
  );
}
