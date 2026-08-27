import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type {
  ChecklistItemInput,
  ChecklistOptionInput,
  ChecklistTemplate,
  ChecklistTemplateInput,
} from '@/types/checklist';

interface RawOption {
  id: string;
  label: string;
  value: string;
  score: number | null;
  is_failure: boolean;
  sequence: number;
  is_active: boolean;
}

interface RawItem {
  id: string;
  section: string | null;
  question: string;
  help_text: string | null;
  sequence: number;
  is_required: boolean;
  is_active: boolean;
}

interface RawTemplate {
  id: string;
  name: string;
  description: string | null;
  category: string | null;
  is_active: boolean;
  items: RawItem[];
  response_options: RawOption[];
}

const toItem = (row: RawItem) => ({
  id: row.id,
  section: row.section,
  question: row.question,
  helpText: row.help_text,
  sequence: row.sequence,
  isRequired: row.is_required,
  isActive: row.is_active,
});

const toOption = (row: RawOption) => ({
  id: row.id,
  label: row.label,
  value: row.value,
  score: row.score,
  isFailure: row.is_failure,
  sequence: row.sequence,
  isActive: row.is_active,
});

const toTemplate = (row: RawTemplate): ChecklistTemplate => ({
  id: row.id,
  name: row.name,
  description: row.description,
  category: row.category,
  isActive: row.is_active,
  items: (row.items ?? []).map(toItem),
  responseOptions: (row.response_options ?? []).map(toOption),
});

/**
 * Generic checklist-template engine for one organization — ITSE is just
 * one row here ("Plantilla ITSE"), never a separate module. Always fetches
 * with include_inactive=true (the management view needs to see and
 * reactivate deactivated items/options); consumers that only need active
 * items for an execution (InspectionRunDialog) filter client-side. See
 * docs/GENERIC_CHECKLISTS_INSPECTIONS.md.
 */
export function useChecklistTemplates(organizationId: string | null | undefined) {
  const [templates, setTemplates] = useState<ChecklistTemplate[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!organizationId) {
      setTemplates([]);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_checklist_templates', {
        p_organization_id: organizationId,
        p_include_inactive: true,
      });
      if (rpcError) throw rpcError;
      setTemplates(((data ?? []) as unknown as RawTemplate[]).map(toTemplate));
    } catch (err) {
      setTemplates([]);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar las plantillas de checklist.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  const saveTemplate = useCallback(async (input: ChecklistTemplateInput, templateId?: string): Promise<boolean> => {
    if (!organizationId) return false;
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('upsert_checklist_template', {
        p_organization_id: organizationId,
        p_name: input.name,
        p_description: input.description ?? null,
        p_category: input.category ?? null,
        p_template_id: templateId ?? null,
        p_is_active: input.isActive ?? true,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar la plantilla.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [organizationId, refresh]);

  const saveItem = useCallback(async (input: ChecklistItemInput, itemId?: string): Promise<boolean> => {
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('upsert_checklist_template_item', {
        p_template_id: input.templateId,
        p_question: input.question,
        p_section: input.section ?? null,
        p_help_text: input.helpText ?? null,
        p_sequence: input.sequence,
        p_is_required: input.isRequired ?? true,
        p_item_id: itemId ?? null,
        p_is_active: input.isActive ?? true,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar el ítem.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  const toggleItemActive = useCallback(async (itemId: string, isActive: boolean): Promise<boolean> => {
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('set_checklist_template_item_active', {
        p_item_id: itemId,
        p_is_active: isActive,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo actualizar el ítem.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  const saveOption = useCallback(async (input: ChecklistOptionInput, optionId?: string): Promise<boolean> => {
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('upsert_checklist_response_option', {
        p_template_id: input.templateId,
        p_label: input.label,
        p_value: input.value,
        p_score: input.score ?? null,
        p_is_failure: input.isFailure ?? false,
        p_sequence: input.sequence,
        p_option_id: optionId ?? null,
        p_is_active: input.isActive ?? true,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar la opción.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  const toggleOptionActive = useCallback(async (optionId: string, isActive: boolean): Promise<boolean> => {
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('set_checklist_response_option_active', {
        p_option_id: optionId,
        p_is_active: isActive,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo actualizar la opción.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  return {
    templates,
    activeTemplates: templates.filter((template) => template.isActive),
    loading,
    saving,
    error,
    refresh,
    saveTemplate,
    saveItem,
    toggleItemActive,
    saveOption,
    toggleOptionActive,
  };
}

export type UseChecklistTemplatesResult = ReturnType<typeof useChecklistTemplates>;
