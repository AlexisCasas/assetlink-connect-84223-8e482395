import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { QuoteTemplate } from '@/types/quote-template';
import { useToast } from '@/hooks/use-toast';

export const useQuoteTemplates = (providerId: string, teamMemberId?: string) => {
  const [templates, setTemplates] = useState<QuoteTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const { toast } = useToast();

  const loadTemplates = async () => {
    try {
      setLoading(true);
      let query = supabase
        .from('quote_templates')
        .select('*')
        .eq('provider_id', providerId);

      if (teamMemberId) {
        query = query.or(`team_member_id.eq.${teamMemberId},team_member_id.is.null`);
      }

      const { data, error } = await query.order('created_at', { ascending: false });

      if (error) throw error;
      setTemplates((data || []) as unknown as QuoteTemplate[]);
    } catch (error) {
      console.error('Error loading templates:', error);
      toast({
        title: "Error",
        description: "No se pudieron cargar las plantillas",
        variant: "destructive",
      });
    } finally {
      setLoading(false);
    }
  };

  const saveTemplate = async (
    name: string,
    fields: QuoteTemplate['fields'],
    percentageFields: QuoteTemplate['percentage_fields']
  ) => {
    try {
      const { error } = await supabase.from('quote_templates').insert({
        name,
        provider_id: providerId,
        team_member_id: teamMemberId || null,
        fields: fields as any,
        percentage_fields: percentageFields as any,
      });

      if (error) throw error;

      toast({
        title: "Éxito",
        description: "Plantilla guardada correctamente",
      });

      await loadTemplates();
      return true;
    } catch (error) {
      console.error('Error saving template:', error);
      toast({
        title: "Error",
        description: "No se pudo guardar la plantilla",
        variant: "destructive",
      });
      return false;
    }
  };

  const deleteTemplate = async (templateId: string) => {
    try {
      const { error } = await supabase
        .from('quote_templates')
        .delete()
        .eq('id', templateId);

      if (error) throw error;

      toast({
        title: "Éxito",
        description: "Plantilla eliminada correctamente",
      });

      await loadTemplates();
    } catch (error) {
      console.error('Error deleting template:', error);
      toast({
        title: "Error",
        description: "No se pudo eliminar la plantilla",
        variant: "destructive",
      });
    }
  };

  useEffect(() => {
    loadTemplates();
  }, [providerId, teamMemberId]);

  return {
    templates,
    loading,
    saveTemplate,
    deleteTemplate,
    reloadTemplates: loadTemplates,
  };
};
