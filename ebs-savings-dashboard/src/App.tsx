import { useState, useEffect } from 'react';
import AppLayout from '@cloudscape-design/components/app-layout';
import TopNavigation from '@cloudscape-design/components/top-navigation';
import Flashbar from '@cloudscape-design/components/flashbar';
import Tabs from '@cloudscape-design/components/tabs';
import Container from '@cloudscape-design/components/container';
import Header from '@cloudscape-design/components/header';
import SpaceBetween from '@cloudscape-design/components/space-between';
import ColumnLayout from '@cloudscape-design/components/column-layout';
import Button from '@cloudscape-design/components/button';
import Select from '@cloudscape-design/components/select';
import Box from '@cloudscape-design/components/box';
import {
  PieChart,
  Pie,
  Cell,
  Tooltip,
  Legend,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  ResponsiveContainer,
} from 'recharts';

import KpiStrip from './components/KpiStrip';
import TrendChart from './components/TrendChart';
import AccountsTable from './components/AccountsTable';
import RegionTable from './components/RegionTable';
import VolumeTypeTable from './components/VolumeTypeTable';
import VolumeInventoryTable from './components/VolumeInventoryTable';
import { MOCK_DATA, type EbsSavingsData } from './data/mock';
import { formatCurrency } from './utils/formatters';

const USE_MOCK = import.meta.env.VITE_USE_MOCK !== 'false';
const API_URL = import.meta.env.VITE_API_URL ?? '';

const DONUT_COLORS = ['#0972d3', '#067f68', '#8456ce', '#c7511f', '#aab7b8'];

const PERIOD_OPTIONS = [
  { label: 'Last 3 months',  value: '3'  },
  { label: 'Last 6 months',  value: '6'  },
  { label: 'Last 12 months', value: '12' },
  { label: 'Last 18 months', value: '18' },
];

const REGION_OPTIONS = [
  { label: 'All regions',    value: 'all'            },
  { label: 'us-east-1',     value: 'us-east-1'      },
  { label: 'us-west-2',     value: 'us-west-2'      },
  { label: 'eu-west-1',     value: 'eu-west-1'      },
  { label: 'ap-southeast-1',value: 'ap-southeast-1' },
  { label: 'eu-central-1',  value: 'eu-central-1'   },
];

export default function App() {
  const [data, setData] = useState<EbsSavingsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [period, setPeriod] = useState(PERIOD_OPTIONS[3]);
  const [region, setRegion] = useState(REGION_OPTIONS[0]);
  const [activeTabId, setActiveTabId] = useState('overview');

  async function fetchData() {
    setLoading(true);
    setError(null);
    try {
      if (USE_MOCK) {
        await new Promise((r) => setTimeout(r, 400));
        setData(MOCK_DATA);
      } else {
        const url = `${API_URL.replace(/\/$/, '')}/ebs-savings?months=${period.value}&region=${region.value}`;
        const res = await fetch(url);
        if (!res.ok) throw new Error(`API error ${res.status}: ${await res.text()}`);
        const json = await res.json();
        setData(json);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setData(null);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { fetchData(); }, [period, region]); // eslint-disable-line react-hooks/exhaustive-deps

  const monthlySavings = data ? data.kpi.monthly_before - data.kpi.monthly_after : 0;

  function exportCsv() {
    if (!data) return;
    type Row = Record<string, string | number>;
    let rows: Row[] = [];
    let filename = 'ebs-savings';

    if (activeTabId === 'by-account') {
      rows = data.accounts.map((a) => ({ account_id: a.account_id, account_name: a.account_name, savings: a.savings, volumes_deleted: a.volumes_deleted }));
      filename = 'ebs-savings-by-account';
    } else if (activeTabId === 'by-region') {
      rows = data.regions.map((r) => ({ region: r.region, savings: r.savings, volumes_deleted: r.volumes_deleted }));
      filename = 'ebs-savings-by-region';
    } else if (activeTabId === 'by-volume-type') {
      rows = data.volume_types.map((v) => ({ volume_type: v.volume_type, savings: v.savings, pct_of_total: v.pct_of_total, price_per_gb: v.price_per_gb }));
      filename = 'ebs-savings-by-volume-type';
    } else if (activeTabId === 'volume-inventory') {
      rows = data.volumes.map((v) => ({ volume_id: v.volume_id, account_id: v.account_id, region: v.region, size_gb: v.size_gb, volume_type: v.volume_type, monthly_cost: v.monthly_cost, attachment_state: v.attachment_state }));
      filename = 'ebs-volume-inventory';
    } else {
      rows = data.monthly_trend.map((m) => ({ month: m.month, spend: m.spend, baseline: m.baseline }));
      filename = 'ebs-savings-overview';
    }

    if (rows.length === 0) return;
    const headers = Object.keys(rows[0]);
    const csv = [headers.join(','), ...rows.map((r) => headers.map((h) => r[h]).join(','))].join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${filename}-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <>
      <TopNavigation
        identity={{ href: '/', title: 'EBS Cost Savings Dashboard', logo: { src: '/aws-logo.svg', alt: 'AWS' } }}
        utilities={[]}
      />

      <AppLayout
        navigationHide
        toolsHide
        notifications={
          <Flashbar
            items={[
              ...(error ? [{
                type: 'error' as const,
                header: 'Failed to load data',
                content: error,
                dismissible: true,
                id: 'error-flash',
              }] : []),
              ...(data ? [{
                type: 'success' as const,
                header: `EBS cleanup is saving ${formatCurrency(monthlySavings)}/month`,
                content: `${data.kpi.volumes_deleted.toLocaleString()} unattached volumes deleted · Projected annual savings: ${formatCurrency(data.kpi.projected_annual)}`,
                dismissible: true,
                id: 'savings-flash',
              }] : []),
            ]}
          />
        }
        content={
          <SpaceBetween size="l">
            {/* Filters */}
            <Container>
              <ColumnLayout columns={3}>
                <Box variant="div">
                  <Box variant="awsui-key-label">Time Period</Box>
                  <Select
                    selectedOption={period}
                    onChange={({ detail }) => setPeriod(detail.selectedOption as typeof period)}
                    options={PERIOD_OPTIONS}
                  />
                </Box>
                <Box variant="div">
                  <Box variant="awsui-key-label">AWS Region</Box>
                  <Select
                    selectedOption={region}
                    onChange={({ detail }) => setRegion(detail.selectedOption as typeof region)}
                    options={REGION_OPTIONS}
                  />
                </Box>
                <Box variant="div" padding={{ top: 'xl' }}>
                  <SpaceBetween direction="horizontal" size="xs">
                    <Button variant="primary" iconName="refresh" onClick={fetchData} loading={loading}>
                      Refresh
                    </Button>
                    <Button iconName="download" onClick={exportCsv} disabled={!data}>Export CSV</Button>
                  </SpaceBetween>
                </Box>
              </ColumnLayout>
            </Container>

            {/* KPI strip */}
            {data && (
              <KpiStrip
                totalSaved={data.kpi.total_saved}
                monthlyBefore={data.kpi.monthly_before}
                monthlyAfter={data.kpi.monthly_after}
                volumesDeleted={data.kpi.volumes_deleted}
                projectedAnnual={data.kpi.projected_annual}
              />
            )}

            {/* Tabs */}
            {data && (
              <Tabs
                activeTabId={activeTabId}
                onChange={({ detail }) => setActiveTabId(detail.activeTabId)}
                tabs={[
                  {
                    id: 'overview',
                    label: 'Overview',
                    content: (
                      <SpaceBetween size="l">
                        <TrendChart data={data.monthly_trend} cleanupStartMonth={data.cleanup_start_month} />
                        <ColumnLayout columns={2}>
                          {/* Donut by volume type */}
                          <Container header={<Header variant="h2">Savings by Volume Type</Header>}>
                            <ResponsiveContainer width="100%" height={260}>
                              <PieChart>
                                <Pie
                                  data={data.donut}
                                  cx="50%"
                                  cy="50%"
                                  innerRadius={60}
                                  outerRadius={100}
                                  dataKey="value"
                                  nameKey="name"
                                  label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                                >
                                  {data.donut.map((_, i) => (
                                    <Cell key={i} fill={DONUT_COLORS[i % DONUT_COLORS.length]} />
                                  ))}
                                </Pie>
                                <Tooltip formatter={(v: number) => formatCurrency(v)} />
                                <Legend />
                              </PieChart>
                            </ResponsiveContainer>
                          </Container>

                          {/* Bar by OU */}
                          <Container header={<Header variant="h2">Savings by Organizational Unit</Header>}>
                            {data.ou_savings.length > 0 ? (
                              <ResponsiveContainer width="100%" height={260}>
                                <BarChart data={data.ou_savings} layout="vertical" margin={{ left: 20 }}>
                                  <CartesianGrid strokeDasharray="3 3" stroke="#e9ebed" />
                                  <XAxis type="number" tickFormatter={(v) => `$${(v / 1000).toFixed(0)}k`} tick={{ fontSize: 11 }} />
                                  <YAxis type="category" dataKey="ou" tick={{ fontSize: 11 }} width={90} />
                                  <Tooltip formatter={(v: number) => formatCurrency(v)} />
                                  <Bar dataKey="savings" name="Savings" fill="#0972d3" radius={[0, 4, 4, 0]} />
                                </BarChart>
                              </ResponsiveContainer>
                            ) : (
                              <Box color="text-body-secondary" textAlign="center" padding="xl">
                                OU data available in Phase 2 with AWS Organizations integration.
                              </Box>
                            )}
                          </Container>
                        </ColumnLayout>

                        {/* Cumulative savings bar */}
                        <Container header={<Header variant="h2">Cumulative Savings Over Time</Header>}>
                          <ResponsiveContainer width="100%" height={240}>
                            <BarChart
                              data={data.monthly_trend
                                .filter((d) => d.spend < d.baseline)
                                .reduce<Array<{ month: string; cumulative: number }>>((acc, d) => {
                                  const prev = acc.length ? acc[acc.length - 1].cumulative : 0;
                                  acc.push({ month: d.month, cumulative: prev + (d.baseline - d.spend) });
                                  return acc;
                                }, [])}
                              margin={{ top: 10, right: 20, left: 20, bottom: 10 }}
                            >
                              <CartesianGrid strokeDasharray="3 3" stroke="#e9ebed" />
                              <XAxis dataKey="month" tick={{ fontSize: 11 }} />
                              <YAxis tickFormatter={(v) => `$${(v / 1000).toFixed(0)}k`} tick={{ fontSize: 11 }} />
                              <Tooltip formatter={(v: number) => formatCurrency(v)} />
                              <Bar dataKey="cumulative" name="Cumulative Savings" fill="#067f68" radius={[4, 4, 0, 0]} />
                            </BarChart>
                          </ResponsiveContainer>
                        </Container>
                      </SpaceBetween>
                    ),
                  },
                  {
                    id: 'by-account',
                    label: 'By Account',
                    content: (
                      <Container>
                        <AccountsTable accounts={data.accounts} />
                      </Container>
                    ),
                  },
                  {
                    id: 'by-region',
                    label: 'By Region',
                    content: <RegionTable regions={data.regions} />,
                  },
                  {
                    id: 'by-volume-type',
                    label: 'By Volume Type',
                    content: (
                      <Container>
                        <VolumeTypeTable volumeTypes={data.volume_types} />
                      </Container>
                    ),
                  },
                  {
                    id: 'volume-inventory',
                    label: 'Volume Inventory',
                    content: <VolumeInventoryTable volumes={data.volumes} />,
                  },
                ]}
              />
            )}
          </SpaceBetween>
        }
      />
    </>
  );
}
