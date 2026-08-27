/** Deliberately neutral formatting — "desviación vs. plan" / "variación",
 * never "mejor"/"peor" or any comparative judgment. See §"No ranking
 * técnico" in docs/EFFICIENCY_DEVIATIONS.md. */
export const formatDeviationHours = (hours: number): string => {
  const sign = hours > 0 ? '+' : hours < 0 ? '' : '±';
  return `${sign}${hours} h`;
};

export const formatDeviationPercent = (percent: number | null): string => {
  if (percent === null) return 'N/D';
  const sign = percent > 0 ? '+' : percent < 0 ? '' : '±';
  return `${sign}${percent} %`;
};

/** Neutral color: only flags magnitude (large deviation either direction
 * draws attention), never "good"/"bad" technician framing. */
export const deviationColorClass = (percent: number | null): string => {
  if (percent === null) return 'text-muted-foreground';
  const magnitude = Math.abs(percent);
  if (magnitude >= 30) return 'text-orange-600';
  if (magnitude >= 10) return 'text-amber-600';
  return 'text-muted-foreground';
};
