export function formatCurrency(value: number, decimals = 0): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(value);
}

export function formatPercent(value: number, decimals = 1): string {
  return `${value.toFixed(decimals)}%`;
}

export function formatNumber(value: number): string {
  return new Intl.NumberFormat('en-US').format(value);
}

export function formatMonth(yyyyMM: string): string {
  const [year, month] = yyyyMM.split('-');
  return new Date(Number(year), Number(month) - 1).toLocaleString('en-US', {
    month: 'short',
    year: 'numeric',
  });
}
