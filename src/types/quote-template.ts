export interface QuoteTableItem {
  id: string;
  description: string;
  unit: string;
  quantity: number;
  unitPrice: number;
  total: number;
}

export interface QuoteField {
  id: string;
  title: string;
  items: QuoteTableItem[];
  order: number;
}

export interface PercentageField {
  id: string;
  name: string;
  percentage: number;
  order: number;
}

export interface QuoteTemplate {
  id: string;
  name: string;
  provider_id: string;
  team_member_id?: string;
  fields: QuoteField[];
  percentage_fields: PercentageField[];
  created_at: string;
}

export interface QuoteSummaryData {
  fields: Array<{ title: string; total: number }>;
  subtotal: number;
  percentageFields: Array<{ name: string; amount: number }>;
  igv: number;
  total: number;
}
