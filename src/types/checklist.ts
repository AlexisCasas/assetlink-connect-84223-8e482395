export interface ChecklistResponseOption {
  id: string;
  label: string;
  value: string;
  score: number | null;
  isFailure: boolean;
  sequence: number;
  isActive: boolean;
}

export interface ChecklistTemplateItem {
  id: string;
  section: string | null;
  question: string;
  helpText: string | null;
  sequence: number;
  isRequired: boolean;
  isActive: boolean;
}

/** ITSE, "Inspección de techos", "Auditoría interna", etc. are all just
 * rows here — nothing about this type is ITSE-specific. See
 * docs/GENERIC_CHECKLISTS_INSPECTIONS.md. */
export interface ChecklistTemplate {
  id: string;
  name: string;
  description: string | null;
  category: string | null;
  isActive: boolean;
  items: ChecklistTemplateItem[];
  responseOptions: ChecklistResponseOption[];
}

export interface ChecklistTemplateInput {
  name: string;
  description?: string | null;
  category?: string | null;
  isActive?: boolean;
}

export interface ChecklistItemInput {
  templateId: string;
  question: string;
  section?: string | null;
  helpText?: string | null;
  sequence: number;
  isRequired?: boolean;
  isActive?: boolean;
}

export interface ChecklistOptionInput {
  templateId: string;
  label: string;
  value: string;
  score?: number | null;
  isFailure?: boolean;
  sequence: number;
  isActive?: boolean;
}
