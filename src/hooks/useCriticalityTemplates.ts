import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toCriticalityCategories, toThresholdValues } from '@/lib/criticalityThresholds';
import type {
  CriticalityTemplateDetail,
  CriticalityTemplateScope,
  CriticalityTemplateSummary,
} from '@/types/criticalityMatrix';

/**
 * Criticality matrix templates (get_criticality_templates /
 * get_criticality_template / apply_criticality_template /
 * create_template_from_current_matrix — all SECURITY DEFINER).
 *
 * Deliberately separate from useCriticalityMatrix: that hook owns the live
 * matrix and per-asset evaluation, this one owns the template catalogue.
 * Visibility is decided server-side — a 'system' template is readable by any
 * authenticated member, an 'organization' template only by its own tenant
 * (see docs/CRITICALITY_V2_TEMPLATES_EXCEL.md); nothing here filters by
 * organization client-side.
 */
export function useCriticalityTemplates(organizationId: string | null | undefined) {
  const [templates, setTemplates] = useState<CriticalityTemplateSummary[]>([]);
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
      const { data, error: rpcError } = await supabase.rpc('get_criticality_templates', {
        p_organization_id: organizationId,
      });
      if (rpcError) throw rpcError;
      setTemplates((data ?? []).map((row) => ({
        id: row.id,
        organizationId: row.organization_id,
        scope: row.scope as CriticalityTemplateScope,
        name: row.name,
        description: row.description,
        category: row.category,
        isActive: row.is_active ?? true,
        parameterCount: row.parameter_count ?? 0,
        optionCount: row.option_count ?? 0,
        totalWeight: Number(row.total_weight ?? 0),
        createdAt: row.created_at,
      })));
    } catch (err) {
      setTemplates([]);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar las plantillas de criticidad.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  const loadTemplate = useCallback(async (templateId: string): Promise<CriticalityTemplateDetail | null> => {
    try {
      const { data, error: rpcError } = await supabase.rpc('get_criticality_template', {
        p_template_id: templateId,
      });
      if (rpcError) throw rpcError;
      if (!data) return null;
      const raw = data as unknown as {
        id: string;
        organization_id: string | null;
        scope: string;
        name: string;
        description: string | null;
        category: string | null;
        is_active: boolean;
        created_at: string;
        thresholds: { medium_min: number; high_min: number; critical_min: number } | null;
        min_possible_score: number | string | null;
        max_possible_score: number | string | null;
        unreachable_categories: string[] | null;
        parameters: Array<{
          id: string; code: string; name: string; description: string | null;
          weight: number; sequence: number; is_active: boolean;
          options: Array<{ id: string; code: string; label: string; score: number; sequence: number; is_active: boolean }>;
        }>;
      };
      return {
        id: raw.id,
        organizationId: raw.organization_id,
        scope: raw.scope as CriticalityTemplateScope,
        name: raw.name,
        description: raw.description,
        category: raw.category,
        isActive: raw.is_active,
        createdAt: raw.created_at,
        thresholds: raw.thresholds ? toThresholdValues(raw.thresholds) : null,
        minPossibleScore: raw.min_possible_score === null ? null : Number(raw.min_possible_score),
        maxPossibleScore: raw.max_possible_score === null ? null : Number(raw.max_possible_score),
        unreachableCategories: toCriticalityCategories(raw.unreachable_categories),
        parameters: (raw.parameters ?? []).map((parameter) => ({
          id: parameter.id,
          code: parameter.code,
          name: parameter.name,
          description: parameter.description,
          weight: Number(parameter.weight),
          sequence: parameter.sequence,
          isActive: parameter.is_active,
          options: (parameter.options ?? []).map((option) => ({
            id: option.id,
            code: option.code,
            label: option.label,
            score: Number(option.score),
            sequence: option.sequence,
            isActive: option.is_active,
          })),
        })),
      };
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo cargar la plantilla.');
      return null;
    }
  }, []);

  /** Replaces the organization's active matrix with the template's content —
   * and its thresholds, when the template carries them (legacy templates keep
   * the current thresholds) — in a single transaction. The previous
   * configuration is deactivated, never deleted, and historical assessments
   * stay untouched. */
  const applyTemplate = useCallback(async (templateId: string): Promise<boolean> => {
    if (!organizationId) return false;
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('apply_criticality_template', {
        p_organization_id: organizationId,
        p_template_id: templateId,
      });
      if (rpcError) throw rpcError;
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo aplicar la plantilla.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [organizationId]);

  const saveCurrentMatrixAsTemplate = useCallback(async (
    name: string,
    description?: string | null,
    category?: string | null,
  ): Promise<boolean> => {
    if (!organizationId) return false;
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('create_template_from_current_matrix', {
        p_organization_id: organizationId,
        p_name: name,
        p_description: description ?? null,
        p_category: category ?? null,
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

  return { templates, loading, saving, error, refresh, loadTemplate, applyTemplate, saveCurrentMatrixAsTemplate };
}
