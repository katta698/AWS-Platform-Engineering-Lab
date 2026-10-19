import { useState } from 'react';
import Table from '@cloudscape-design/components/table';
import Header from '@cloudscape-design/components/header';
import Box from '@cloudscape-design/components/box';
import SpaceBetween from '@cloudscape-design/components/space-between';
import ColumnLayout from '@cloudscape-design/components/column-layout';
import Container from '@cloudscape-design/components/container';
import Select from '@cloudscape-design/components/select';
import Badge from '@cloudscape-design/components/badge';
import StatusIndicator from '@cloudscape-design/components/status-indicator';
import { useCollection } from '@cloudscape-design/collection-hooks';
import { formatCurrency, formatNumber } from '../utils/formatters';
import type { VolumeRow, AttachmentState } from '../data/mock';

interface VolumeInventoryTableProps {
  volumes: VolumeRow[];
}

const STATE_OPTIONS = [
  { label: 'All volumes',          value: 'all'             },
  { label: 'Unattached',           value: 'unattached'      },
  { label: 'Attached — stopped EC2', value: 'attached-stopped' },
  { label: 'Attached — running EC2', value: 'attached-running' },
];

function AttachmentBadge({ state }: { state: AttachmentState }) {
  if (state === 'unattached') {
    return <StatusIndicator type="error">Unattached</StatusIndicator>;
  }
  if (state === 'attached-stopped') {
    return <StatusIndicator type="warning">Stopped EC2</StatusIndicator>;
  }
  return <StatusIndicator type="success">Running EC2</StatusIndicator>;
}

function RiskBadge({ volume }: { volume: VolumeRow }) {
  if (volume.attachment_state === 'unattached' && !volume.has_recent_snapshot) {
    return <Badge color="red">Delete candidate</Badge>;
  }
  if (volume.attachment_state === 'unattached' && volume.has_recent_snapshot) {
    return <Badge color="severity-medium">Review</Badge>;
  }
  if (volume.attachment_state === 'attached-stopped') {
    return <Badge color="severity-medium">Review</Badge>;
  }
  return <Badge color="green">In use</Badge>;
}

function SummaryKpi({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <Box>
      <Box variant="awsui-key-label">{label}</Box>
      <Box variant="h3">{value}</Box>
      {sub && <Box variant="small" color="text-body-secondary">{sub}</Box>}
    </Box>
  );
}

export default function VolumeInventoryTable({ volumes }: VolumeInventoryTableProps) {
  const [stateFilter, setStateFilter] = useState(STATE_OPTIONS[0]);

  if (!volumes || volumes.length === 0) {
    return (
      <Container header={<Header variant="h2">Volume Inventory</Header>}>
        <Box color="text-body-secondary" textAlign="center" padding="xl">
          No live volume inventory available. Deploy Phase 2 to enable cross-account EC2 inventory.
        </Box>
      </Container>
    );
  }

  const filtered = stateFilter.value === 'all'
    ? volumes
    : volumes.filter((v) => v.attachment_state === stateFilter.value);

  const { items, collectionProps } = useCollection(filtered, {
    sorting: {
      defaultState: { sortingColumn: { sortingField: 'monthly_cost' }, isDescending: true },
    },
  });

  const unattached       = volumes.filter((v) => v.attachment_state === 'unattached');
  const attachedStopped  = volumes.filter((v) => v.attachment_state === 'attached-stopped');
  const deleteCandidates = volumes.filter((v) => v.attachment_state === 'unattached' && !v.has_recent_snapshot);

  const wasteCost = [...unattached, ...attachedStopped].reduce((s, v) => s + v.monthly_cost, 0);

  return (
    <SpaceBetween size="l">
      {/* Summary strip */}
      <Container header={<Header variant="h2">Attachment State Summary</Header>}>
        <ColumnLayout columns={4} variant="text-grid">
          <SummaryKpi
            label="Unattached Volumes"
            value={formatNumber(unattached.length)}
            sub={`${formatCurrency(unattached.reduce((s, v) => s + v.monthly_cost, 0))}/mo wasted`}
          />
          <SummaryKpi
            label="Attached — Stopped EC2"
            value={formatNumber(attachedStopped.length)}
            sub={`${formatCurrency(attachedStopped.reduce((s, v) => s + v.monthly_cost, 0))}/mo at risk`}
          />
          <SummaryKpi
            label="Delete Candidates"
            value={formatNumber(deleteCandidates.length)}
            sub="Unattached + no snapshot"
          />
          <SummaryKpi
            label="Total Recoverable"
            value={formatCurrency(wasteCost)}
            sub="Unattached + stopped combined"
          />
        </ColumnLayout>
      </Container>

      {/* Table with filter */}
      <Container
        header={
          <Header
            variant="h2"
            counter={`(${filtered.length})`}
            actions={
              <Select
                selectedOption={stateFilter}
                onChange={({ detail }) => setStateFilter(detail.selectedOption as typeof stateFilter)}
                options={STATE_OPTIONS}
              />
            }
          >
            Volume Inventory
          </Header>
        }
      >
        <Table
          {...collectionProps}
          items={items}
          columnDefinitions={[
            {
              id: 'name',
              header: 'Volume',
              cell: (v) => (
                <Box>
                  <Box variant="strong">{v.name || '—'}</Box>
                  <Box variant="small" color="text-body-secondary">{v.volume_id}</Box>
                </Box>
              ),
              sortingField: 'name',
              minWidth: 200,
            },
            {
              id: 'attachment_state',
              header: 'Attachment State',
              cell: (v) => <AttachmentBadge state={v.attachment_state} />,
              sortingField: 'attachment_state',
            },
            {
              id: 'instance',
              header: 'EC2 Instance',
              cell: (v) =>
                v.instance_id ? (
                  <Box>
                    <Box variant="code">{v.instance_id}</Box>
                    <Box variant="small" color="text-body-secondary">
                      {v.instance_type} · {v.instance_state}
                    </Box>
                  </Box>
                ) : (
                  <Box color="text-status-inactive">—</Box>
                ),
              minWidth: 190,
            },
            {
              id: 'size',
              header: 'Size',
              cell: (v) => `${formatNumber(v.size_gb)} GB`,
              sortingField: 'size_gb',
            },
            {
              id: 'volume_type',
              header: 'Type',
              cell: (v) => v.volume_type.toUpperCase(),
              sortingField: 'volume_type',
            },
            {
              id: 'region',
              header: 'Region / AZ',
              cell: (v) => (
                <Box>
                  <Box>{v.region}</Box>
                  <Box variant="small" color="text-body-secondary">{v.az}</Box>
                </Box>
              ),
              sortingField: 'region',
            },
            {
              id: 'account',
              header: 'Account',
              cell: (v) => (
                <Box>
                  <Box>{v.account_name}</Box>
                  <Box variant="small" color="text-body-secondary">{v.account_id}</Box>
                </Box>
              ),
              sortingField: 'account_name',
            },
            {
              id: 'monthly_cost',
              header: 'Monthly Cost',
              cell: (v) => <Box variant="strong">{formatCurrency(v.monthly_cost)}</Box>,
              sortingField: 'monthly_cost',
            },
            {
              id: 'age_days',
              header: 'Age',
              cell: (v) => `${v.age_days}d`,
              sortingField: 'age_days',
            },
            {
              id: 'snapshot',
              header: 'Snapshot',
              cell: (v) =>
                v.has_recent_snapshot ? (
                  <StatusIndicator type="success">Recent</StatusIndicator>
                ) : (
                  <StatusIndicator type="warning">None</StatusIndicator>
                ),
              sortingField: 'has_recent_snapshot',
            },
            {
              id: 'risk',
              header: 'Recommendation',
              cell: (v) => <RiskBadge volume={v} />,
            },
          ]}
          variant="embedded"
          sortingDisabled={false}
        />
      </Container>
    </SpaceBetween>
  );
}
