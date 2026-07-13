export interface MonthlyTrend {
  month: string;
  spend: number;
  baseline: number;
}

export interface AccountRow {
  account_id: string;
  account_name: string;
  ou: string;
  before: number;
  after: number;
  savings: number;
  pct_reduction: number;
  volumes_deleted: number;
}

export interface RegionRow {
  region: string;
  before: number;
  after: number;
  savings: number;
  volumes_deleted: number;
}

export interface VolumeTypeRow {
  volume_type: string;
  before: number;
  after: number;
  savings: number;
  price_per_gb: number;
  pct_of_total: number;
}

export interface OuBarItem {
  ou: string;
  savings: number;
}

export interface DonutItem {
  name: string;
  value: number;
}

export type AttachmentState = 'unattached' | 'attached-stopped' | 'attached-running';

export interface VolumeRow {
  volume_id: string;
  name: string;
  size_gb: number;
  volume_type: string;
  region: string;
  account_id: string;
  account_name: string;
  attachment_state: AttachmentState;
  instance_id: string | null;
  instance_type: string | null;
  instance_state: 'running' | 'stopped' | null;
  monthly_cost: number;
  age_days: number;
  has_recent_snapshot: boolean;
  az: string;
  tags_name: string;
  tags_env: string;
  tags_team: string;
}

export interface EbsSavingsData {
  kpi: {
    total_saved: number;
    monthly_before: number;
    monthly_after: number;
    volumes_deleted: number;
    projected_annual: number;
  };
  monthly_trend: MonthlyTrend[];
  cleanup_start_month: string;
  accounts: AccountRow[];
  regions: RegionRow[];
  volume_types: VolumeTypeRow[];
  ou_savings: OuBarItem[];
  donut: DonutItem[];
  volumes: VolumeRow[];
}

export const MOCK_DATA: EbsSavingsData = {
  kpi: {
    total_saved: 284_700,
    monthly_before: 97_400,
    monthly_after: 49_750,
    volumes_deleted: 1_843,
    projected_annual: 572_400,
  },
  cleanup_start_month: '2025-09',
  monthly_trend: [
    { month: '2025-01', spend: 94_200,  baseline: 94_200 },
    { month: '2025-02', spend: 95_800,  baseline: 95_800 },
    { month: '2025-03', spend: 96_100,  baseline: 96_100 },
    { month: '2025-04', spend: 97_400,  baseline: 97_400 },
    { month: '2025-05', spend: 96_900,  baseline: 97_400 },
    { month: '2025-06', spend: 97_100,  baseline: 97_400 },
    { month: '2025-07', spend: 96_500,  baseline: 97_400 },
    { month: '2025-08', spend: 97_000,  baseline: 97_400 },
    { month: '2025-09', spend: 81_200,  baseline: 97_400 },
    { month: '2025-10', spend: 63_400,  baseline: 97_400 },
    { month: '2025-11', spend: 54_100,  baseline: 97_400 },
    { month: '2025-12', spend: 51_300,  baseline: 97_400 },
    { month: '2026-01', spend: 50_200,  baseline: 97_400 },
    { month: '2026-02', spend: 49_900,  baseline: 97_400 },
    { month: '2026-03', spend: 49_750,  baseline: 97_400 },
  ],
  accounts: [
    { account_id: '123456789012', account_name: 'prod-platform',    ou: 'Production',  before: 18_400, after: 9_200,  savings: 9_200,  pct_reduction: 50.0, volumes_deleted: 342 },
    { account_id: '234567890123', account_name: 'prod-data',        ou: 'Production',  before: 14_200, after: 6_800,  savings: 7_400,  pct_reduction: 52.1, volumes_deleted: 281 },
    { account_id: '345678901234', account_name: 'dev-sandbox',      ou: 'Development', before: 12_900, after: 4_100,  savings: 8_800,  pct_reduction: 68.2, volumes_deleted: 394 },
    { account_id: '456789012345', account_name: 'staging-infra',    ou: 'Staging',     before: 11_300, after: 5_600,  savings: 5_700,  pct_reduction: 50.4, volumes_deleted: 210 },
    { account_id: '567890123456', account_name: 'analytics-prod',   ou: 'Production',  before: 10_800, after: 5_900,  savings: 4_900,  pct_reduction: 45.4, volumes_deleted: 178 },
    { account_id: '678901234567', account_name: 'ml-training',      ou: 'ML',          before: 9_600,  after: 4_200,  savings: 5_400,  pct_reduction: 56.3, volumes_deleted: 162 },
    { account_id: '789012345678', account_name: 'security-tooling', ou: 'Security',    before: 7_100,  after: 3_800,  savings: 3_300,  pct_reduction: 46.5, volumes_deleted: 97  },
    { account_id: '890123456789', account_name: 'devops-shared',    ou: 'Development', before: 6_800,  after: 3_100,  savings: 3_700,  pct_reduction: 54.4, volumes_deleted: 131 },
    { account_id: '901234567890', account_name: 'finops-reporting', ou: 'Shared Svcs', before: 3_900,  after: 2_100,  savings: 1_800,  pct_reduction: 46.2, volumes_deleted: 48  },
  ],
  regions: [
    { region: 'us-east-1',      before: 42_100, after: 21_300, savings: 20_800, volumes_deleted: 781 },
    { region: 'us-west-2',      before: 21_400, after: 10_900, savings: 10_500, volumes_deleted: 402 },
    { region: 'eu-west-1',      before: 14_800, after: 7_200,  savings: 7_600,  volumes_deleted: 284 },
    { region: 'ap-southeast-1', before: 8_900,  after: 4_400,  savings: 4_500,  volumes_deleted: 201 },
    { region: 'eu-central-1',   before: 6_200,  after: 3_100,  savings: 3_100,  volumes_deleted: 118 },
    { region: 'us-east-2',      before: 4_000,  after: 2_850,  savings: 1_150,  volumes_deleted: 57  },
  ],
  volume_types: [
    { volume_type: 'gp2',  before: 48_200, after: 12_300, savings: 35_900, price_per_gb: 0.10, pct_of_total: 75.3 },
    { volume_type: 'gp3',  before: 28_100, after: 22_400, savings: 5_700,  price_per_gb: 0.08, pct_of_total: 12.0 },
    { volume_type: 'io1',  before: 12_400, after: 9_200,  savings: 3_200,  price_per_gb: 0.125,pct_of_total: 6.7  },
    { volume_type: 'st1',  before: 5_300,  after: 3_200,  savings: 2_100,  price_per_gb: 0.045,pct_of_total: 4.4  },
    { volume_type: 'sc1',  before: 3_400,  after: 2_650,  savings: 750,    price_per_gb: 0.025,pct_of_total: 1.6  },
  ],
  ou_savings: [
    { ou: 'Production',  savings: 21_500 },
    { ou: 'Development', savings: 12_500 },
    { ou: 'Staging',     savings: 5_700  },
    { ou: 'ML',          savings: 5_400  },
    { ou: 'Security',    savings: 3_300  },
    { ou: 'Shared Svcs', savings: 1_800  },
  ],
  donut: [
    { name: 'gp2',  value: 35_900 },
    { name: 'gp3',  value: 5_700  },
    { name: 'io1',  value: 3_200  },
    { name: 'st1',  value: 2_100  },
    { name: 'sc1',  value: 750    },
  ],
  volumes: [
    // --- Unattached (prime deletion targets) ---
    { volume_id: 'vol-0a1b2c3d4e5f60001', name: 'data-backup-jan',     size_gb: 500,  volume_type: 'gp2', region: 'us-east-1',      account_id: '345678901234', account_name: 'dev-sandbox',      attachment_state: 'unattached',      instance_id: null,           instance_type: null,       instance_state: null,      monthly_cost: 50.00, age_days: 312, has_recent_snapshot: false, az: 'us-east-1a', tags_name: 'data-backup-jan',     tags_env: 'dev',  tags_team: 'platform'  },
    { volume_id: 'vol-0a1b2c3d4e5f60002', name: 'jenkins-workspace',    size_gb: 200,  volume_type: 'gp2', region: 'us-east-1',      account_id: '345678901234', account_name: 'dev-sandbox',      attachment_state: 'unattached',      instance_id: null,           instance_type: null,       instance_state: null,      monthly_cost: 20.00, age_days: 187, has_recent_snapshot: false, az: 'us-east-1b', tags_name: 'jenkins-workspace',    tags_env: 'dev',  tags_team: 'devops'    },
    { volume_id: 'vol-0a1b2c3d4e5f60003', name: 'ml-training-data-v1',  size_gb: 2000, volume_type: 'st1', region: 'us-west-2',      account_id: '678901234567', account_name: 'ml-training',      attachment_state: 'unattached',      instance_id: null,           instance_type: null,       instance_state: null,      monthly_cost: 90.00, age_days: 421, has_recent_snapshot: true,  az: 'us-west-2a', tags_name: 'ml-training-data-v1',  tags_env: 'prod', tags_team: 'ml'        },
    { volume_id: 'vol-0a1b2c3d4e5f60004', name: 'prometheus-old',       size_gb: 100,  volume_type: 'gp3', region: 'eu-west-1',      account_id: '456789012345', account_name: 'staging-infra',    attachment_state: 'unattached',      instance_id: null,           instance_type: null,       instance_state: null,      monthly_cost:  8.00, age_days:  94, has_recent_snapshot: false, az: 'eu-west-1a', tags_name: 'prometheus-old',       tags_env: 'stg', tags_team: 'platform'  },
    { volume_id: 'vol-0a1b2c3d4e5f60005', name: 'log-archive-2024',     size_gb: 800,  volume_type: 'sc1', region: 'us-east-1',      account_id: '234567890123', account_name: 'prod-data',        attachment_state: 'unattached',      instance_id: null,           instance_type: null,       instance_state: null,      monthly_cost: 20.00, age_days: 536, has_recent_snapshot: true,  az: 'us-east-1c', tags_name: 'log-archive-2024',     tags_env: 'prod', tags_team: 'data'      },
    { volume_id: 'vol-0a1b2c3d4e5f60006', name: 'build-cache-node1',    size_gb:  50,  volume_type: 'gp2', region: 'us-east-1',      account_id: '345678901234', account_name: 'dev-sandbox',      attachment_state: 'unattached',      instance_id: null,           instance_type: null,       instance_state: null,      monthly_cost:  5.00, age_days:  62, has_recent_snapshot: false, az: 'us-east-1a', tags_name: 'build-cache-node1',    tags_env: 'dev',  tags_team: 'devops'    },
    { volume_id: 'vol-0a1b2c3d4e5f60007', name: 'kafka-data-replica',   size_gb: 1000, volume_type: 'io1', region: 'us-east-1',      account_id: '123456789012', account_name: 'prod-platform',    attachment_state: 'unattached',      instance_id: null,           instance_type: null,       instance_state: null,      monthly_cost: 125.00,age_days: 201, has_recent_snapshot: false, az: 'us-east-1b', tags_name: 'kafka-data-replica',   tags_env: 'prod', tags_team: 'platform'  },
    { volume_id: 'vol-0a1b2c3d4e5f60008', name: 'test-runner-scratch',  size_gb:  30,  volume_type: 'gp2', region: 'eu-central-1',   account_id: '890123456789', account_name: 'devops-shared',    attachment_state: 'unattached',      instance_id: null,           instance_type: null,       instance_state: null,      monthly_cost:  3.00, age_days:  28, has_recent_snapshot: false, az: 'eu-central-1a',tags_name: 'test-runner-scratch',  tags_env: 'dev',  tags_team: 'devops'    },

    // --- Attached to stopped EC2 (good candidates) ---
    { volume_id: 'vol-0b2c3d4e5f6a70001', name: 'analytics-worker-1',  size_gb: 300,  volume_type: 'gp2', region: 'us-east-1',      account_id: '567890123456', account_name: 'analytics-prod',   attachment_state: 'attached-stopped', instance_id: 'i-0deadbeef000001', instance_type: 'm5.2xlarge', instance_state: 'stopped', monthly_cost: 30.00, age_days: 145, has_recent_snapshot: true,  az: 'us-east-1a', tags_name: 'analytics-worker-1',  tags_env: 'prod', tags_team: 'analytics' },
    { volume_id: 'vol-0b2c3d4e5f6a70002', name: 'spark-master-root',   size_gb: 150,  volume_type: 'gp3', region: 'us-west-2',      account_id: '567890123456', account_name: 'analytics-prod',   attachment_state: 'attached-stopped', instance_id: 'i-0deadbeef000002', instance_type: 'r5.4xlarge', instance_state: 'stopped', monthly_cost: 12.00, age_days:  89, has_recent_snapshot: false, az: 'us-west-2b', tags_name: 'spark-master-root',   tags_env: 'prod', tags_team: 'data'      },
    { volume_id: 'vol-0b2c3d4e5f6a70003', name: 'bastion-host-euw1',   size_gb:  20,  volume_type: 'gp2', region: 'eu-west-1',      account_id: '789012345678', account_name: 'security-tooling', attachment_state: 'attached-stopped', instance_id: 'i-0deadbeef000003', instance_type: 't3.micro',   instance_state: 'stopped', monthly_cost:  2.00, age_days: 380, has_recent_snapshot: false, az: 'eu-west-1b', tags_name: 'bastion-host-euw1',   tags_env: 'prod', tags_team: 'security'  },
    { volume_id: 'vol-0b2c3d4e5f6a70004', name: 'ml-gpu-training',     size_gb: 500,  volume_type: 'io1', region: 'us-east-1',      account_id: '678901234567', account_name: 'ml-training',      attachment_state: 'attached-stopped', instance_id: 'i-0deadbeef000004', instance_type: 'p3.8xlarge', instance_state: 'stopped', monthly_cost: 62.50, age_days: 234, has_recent_snapshot: true,  az: 'us-east-1c', tags_name: 'ml-gpu-training',     tags_env: 'prod', tags_team: 'ml'        },
    { volume_id: 'vol-0b2c3d4e5f6a70005', name: 'dev-db-postgres',     size_gb: 100,  volume_type: 'gp2', region: 'us-east-1',      account_id: '345678901234', account_name: 'dev-sandbox',      attachment_state: 'attached-stopped', instance_id: 'i-0deadbeef000005', instance_type: 't3.large',   instance_state: 'stopped', monthly_cost: 10.00, age_days:  72, has_recent_snapshot: true,  az: 'us-east-1a', tags_name: 'dev-db-postgres',     tags_env: 'dev',  tags_team: 'backend'   },
    { volume_id: 'vol-0b2c3d4e5f6a70006', name: 'grafana-data',        size_gb:  80,  volume_type: 'gp3', region: 'ap-southeast-1', account_id: '456789012345', account_name: 'staging-infra',    attachment_state: 'attached-stopped', instance_id: 'i-0deadbeef000006', instance_type: 't3.medium',  instance_state: 'stopped', monthly_cost:  6.40, age_days: 155, has_recent_snapshot: false, az: 'ap-southeast-1a',tags_name: 'grafana-data',        tags_env: 'stg', tags_team: 'platform'  },

    // --- Attached to running EC2 (do not touch) ---
    { volume_id: 'vol-0c3d4e5f6a7b80001', name: 'prod-api-root',       size_gb: 100,  volume_type: 'gp3', region: 'us-east-1',      account_id: '123456789012', account_name: 'prod-platform',    attachment_state: 'attached-running', instance_id: 'i-0livebeef000001', instance_type: 'm5.xlarge',  instance_state: 'running',  monthly_cost:  8.00, age_days:  55, has_recent_snapshot: true,  az: 'us-east-1a', tags_name: 'prod-api-root',       tags_env: 'prod', tags_team: 'platform'  },
    { volume_id: 'vol-0c3d4e5f6a7b80002', name: 'prod-api-data',       size_gb: 500,  volume_type: 'gp3', region: 'us-east-1',      account_id: '123456789012', account_name: 'prod-platform',    attachment_state: 'attached-running', instance_id: 'i-0livebeef000001', instance_type: 'm5.xlarge',  instance_state: 'running',  monthly_cost: 40.00, age_days:  55, has_recent_snapshot: true,  az: 'us-east-1a', tags_name: 'prod-api-data',       tags_env: 'prod', tags_team: 'platform'  },
    { volume_id: 'vol-0c3d4e5f6a7b80003', name: 'kafka-broker-1',      size_gb: 2000, volume_type: 'io1', region: 'us-east-1',      account_id: '123456789012', account_name: 'prod-platform',    attachment_state: 'attached-running', instance_id: 'i-0livebeef000002', instance_type: 'r5.2xlarge', instance_state: 'running',  monthly_cost: 250.00,age_days: 182, has_recent_snapshot: true,  az: 'us-east-1b', tags_name: 'kafka-broker-1',      tags_env: 'prod', tags_team: 'platform'  },
    { volume_id: 'vol-0c3d4e5f6a7b80004', name: 'eks-node-data',       size_gb: 200,  volume_type: 'gp3', region: 'us-west-2',      account_id: '234567890123', account_name: 'prod-data',        attachment_state: 'attached-running', instance_id: 'i-0livebeef000003', instance_type: 'm5.2xlarge', instance_state: 'running',  monthly_cost: 16.00, age_days:  38, has_recent_snapshot: false, az: 'us-west-2a', tags_name: 'eks-node-data',       tags_env: 'prod', tags_team: 'data'      },
    { volume_id: 'vol-0c3d4e5f6a7b80005', name: 'redshift-leader',     size_gb: 1000, volume_type: 'io1', region: 'us-east-1',      account_id: '234567890123', account_name: 'prod-data',        attachment_state: 'attached-running', instance_id: 'i-0livebeef000004', instance_type: 'r5.4xlarge', instance_state: 'running',  monthly_cost: 125.00,age_days: 290, has_recent_snapshot: true,  az: 'us-east-1c', tags_name: 'redshift-leader',     tags_env: 'prod', tags_team: 'data'      },
  ],
};
