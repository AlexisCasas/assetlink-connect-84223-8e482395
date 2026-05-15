import type {
  QuoteSection,
  QuoteSectionItem,
  QuoteSalesConditions,
  QuoteCalculationSummary,
} from '@/types/request';

export const IGV_RATE = 0.18;

export const DEFAULT_SECTION_NAMES = [
  'Actividades',
  'Materiales',
  'Equipos',
  'Movilización',
];

export const createEmptyItem = (): QuoteSectionItem => ({
  id: crypto.randomUUID(),
  description: '',
  quantity: 0,
  unitMeasure: '',
  totalPrice: 0,
});

export const createSection = (name: string, order: number): QuoteSection => ({
  id: crypto.randomUUID(),
  name,
  type: 'line_items',
  order,
  enabled: true,
  items: [createEmptyItem()],
  subtotal: 0,
});

export const createDefaultSections = (): QuoteSection[] =>
  DEFAULT_SECTION_NAMES.map((n, i) => createSection(n, i));

export const createGeneralSection = (): QuoteSection[] => [
  createSection('General', 0),
];

export const DEFAULT_SALES_CONDITIONS: QuoteSalesConditions = {
  validityDays: 15,
  warrantyMonths: 12,
  deliveryDays: 30,
  paymentTerms: '50% anticipo, 50% contra entrega',
  additionalNotes: '',
};

const safeNum = (n: any): number => {
  const v = typeof n === 'number' ? n : parseFloat(n);
  return Number.isFinite(v) ? v : 0;
};

export const calcSectionSubtotal = (section: QuoteSection): number =>
  section.items.reduce((s, i) => s + safeNum(i.totalPrice), 0);

export const calculateQuote = (
  sections: QuoteSection[],
  generalExpensesPercentage: number,
  utilitiesPercentage: number,
  generalExpensesEnabled: boolean,
  utilitiesEnabled: boolean,
): QuoteCalculationSummary => {
  const enabledSections = sections.filter((s) => s.enabled);
  const baseSubtotal = enabledSections.reduce(
    (s, sec) => s + calcSectionSubtotal(sec),
    0,
  );
  const gPct = generalExpensesEnabled ? safeNum(generalExpensesPercentage) : 0;
  const uPct = utilitiesEnabled ? safeNum(utilitiesPercentage) : 0;
  const generalExpensesAmount = (baseSubtotal * gPct) / 100;
  const utilitiesAmount =
    ((baseSubtotal + generalExpensesAmount) * uPct) / 100;
  const subtotal = baseSubtotal + generalExpensesAmount + utilitiesAmount;
  const igvAmount = subtotal * IGV_RATE;
  const totalAmount = subtotal + igvAmount;

  return {
    baseSubtotal,
    generalExpensesPercentage: gPct,
    generalExpensesAmount,
    utilitiesPercentage: uPct,
    utilitiesAmount,
    subtotal,
    igvAmount,
    totalAmount,
  };
};

export const formatSoles = (n: any): string => {
  const v = safeNum(n);
  return `S/ ${v.toFixed(2)}`;
};
