export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      activity_logs: {
        Row: {
          action: string
          actor_user_id: string | null
          created_at: string
          entity_id: string | null
          entity_type: string
          id: string
          metadata: Json
          organization_id: string
        }
        Insert: {
          action: string
          actor_user_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type: string
          id?: string
          metadata?: Json
          organization_id: string
        }
        Update: {
          action?: string
          actor_user_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string
          id?: string
          metadata?: Json
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "activity_logs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_categories: {
        Row: {
          created_at: string
          created_by_user_id: string | null
          description: string | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          parent_category_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by_user_id?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          organization_id: string
          parent_category_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by_user_id?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          organization_id?: string
          parent_category_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "asset_categories_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_categories_parent_category_id_fkey"
            columns: ["parent_category_id"]
            isOneToOne: false
            referencedRelation: "asset_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_criticality_assessment_answers: {
        Row: {
          assessment_id: string
          option_id: string | null
          option_label: string | null
          option_score: number
          parameter_id: string
          parameter_name: string
          weight: number
          weighted_score: number
        }
        Insert: {
          assessment_id: string
          option_id?: string | null
          option_label?: string | null
          option_score?: number
          parameter_id: string
          parameter_name: string
          weight: number
          weighted_score?: number
        }
        Update: {
          assessment_id?: string
          option_id?: string | null
          option_label?: string | null
          option_score?: number
          parameter_id?: string
          parameter_name?: string
          weight?: number
          weighted_score?: number
        }
        Relationships: [
          {
            foreignKeyName: "asset_criticality_assessment_answers_assessment_id_fkey"
            columns: ["assessment_id"]
            isOneToOne: false
            referencedRelation: "asset_criticality_assessments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_criticality_assessment_answers_option_id_fkey"
            columns: ["option_id"]
            isOneToOne: false
            referencedRelation: "criticality_parameter_options"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_criticality_assessment_answers_parameter_id_fkey"
            columns: ["parameter_id"]
            isOneToOne: false
            referencedRelation: "criticality_parameters"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_criticality_assessments: {
        Row: {
          asset_id: string
          calculated_criticality: string
          created_at: string
          created_by_user_id: string | null
          effective_criticality: string
          id: string
          manual_criticality: string | null
          notes: string | null
          organization_id: string
          score: number
          threshold_critical_min: number
          threshold_high_min: number
          threshold_medium_min: number
        }
        Insert: {
          asset_id: string
          calculated_criticality: string
          created_at?: string
          created_by_user_id?: string | null
          effective_criticality: string
          id?: string
          manual_criticality?: string | null
          notes?: string | null
          organization_id: string
          score?: number
          threshold_critical_min: number
          threshold_high_min: number
          threshold_medium_min: number
        }
        Update: {
          asset_id?: string
          calculated_criticality?: string
          created_at?: string
          created_by_user_id?: string | null
          effective_criticality?: string
          id?: string
          manual_criticality?: string | null
          notes?: string | null
          organization_id?: string
          score?: number
          threshold_critical_min?: number
          threshold_high_min?: number
          threshold_medium_min?: number
        }
        Relationships: [
          {
            foreignKeyName: "asset_criticality_assessments_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_criticality_assessments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_documents: {
        Row: {
          asset_id: string
          created_at: string
          document_type: string | null
          file_url: string | null
          id: string
          name: string
          organization_id: string
          storage_path: string | null
          uploaded_by_user_id: string | null
        }
        Insert: {
          asset_id: string
          created_at?: string
          document_type?: string | null
          file_url?: string | null
          id?: string
          name: string
          organization_id: string
          storage_path?: string | null
          uploaded_by_user_id?: string | null
        }
        Update: {
          asset_id?: string
          created_at?: string
          document_type?: string | null
          file_url?: string | null
          id?: string
          name?: string
          organization_id?: string
          storage_path?: string | null
          uploaded_by_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "asset_documents_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_documents_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_events: {
        Row: {
          asset_id: string
          created_at: string
          created_by_user_id: string | null
          description: string | null
          event_type: string
          id: string
          organization_id: string
          payload: Json
        }
        Insert: {
          asset_id: string
          created_at?: string
          created_by_user_id?: string | null
          description?: string | null
          event_type: string
          id?: string
          organization_id: string
          payload?: Json
        }
        Update: {
          asset_id?: string
          created_at?: string
          created_by_user_id?: string | null
          description?: string | null
          event_type?: string
          id?: string
          organization_id?: string
          payload?: Json
        }
        Relationships: [
          {
            foreignKeyName: "asset_events_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_meter_readings: {
        Row: {
          created_at: string
          created_by_user_id: string | null
          id: string
          meter_id: string
          notes: string | null
          recorded_at: string
          supersedes_reading_id: string | null
          value: number
          void_reason: string | null
          voided_at: string | null
          voided_by_user_id: string | null
        }
        Insert: {
          created_at?: string
          created_by_user_id?: string | null
          id?: string
          meter_id: string
          notes?: string | null
          recorded_at: string
          supersedes_reading_id?: string | null
          value: number
          void_reason?: string | null
          voided_at?: string | null
          voided_by_user_id?: string | null
        }
        Update: {
          created_at?: string
          created_by_user_id?: string | null
          id?: string
          meter_id?: string
          notes?: string | null
          recorded_at?: string
          supersedes_reading_id?: string | null
          value?: number
          void_reason?: string | null
          voided_at?: string | null
          voided_by_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "asset_meter_readings_meter_id_fkey"
            columns: ["meter_id"]
            isOneToOne: false
            referencedRelation: "asset_meters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_meter_readings_supersedes_reading_id_fkey"
            columns: ["supersedes_reading_id"]
            isOneToOne: false
            referencedRelation: "asset_meter_readings"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_meters: {
        Row: {
          asset_id: string
          created_at: string
          created_by_user_id: string | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          replaces_meter_id: string | null
          retired_at: string | null
          retirement_reason: string | null
          unit: string
          updated_at: string
        }
        Insert: {
          asset_id: string
          created_at?: string
          created_by_user_id?: string | null
          id?: string
          is_active?: boolean
          name: string
          organization_id: string
          replaces_meter_id?: string | null
          retired_at?: string | null
          retirement_reason?: string | null
          unit: string
          updated_at?: string
        }
        Update: {
          asset_id?: string
          created_at?: string
          created_by_user_id?: string | null
          id?: string
          is_active?: boolean
          name?: string
          organization_id?: string
          replaces_meter_id?: string | null
          retired_at?: string | null
          retirement_reason?: string | null
          unit?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "asset_meters_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_meters_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_meters_replaces_meter_id_fkey"
            columns: ["replaces_meter_id"]
            isOneToOne: false
            referencedRelation: "asset_meters"
            referencedColumns: ["id"]
          },
        ]
      }
      assets: {
        Row: {
          asset_category_id: string | null
          barcode: string | null
          branch_id: string | null
          code: string | null
          created_at: string
          created_by_user_id: string | null
          criticality: string | null
          default_responsible_member_id: string | null
          description: string | null
          id: string
          image_url: string | null
          location_text: string | null
          manufacturer: string | null
          metadata: Json
          model: string | null
          name: string
          node_type: string
          organization_id: string
          parent_asset_id: string | null
          purchase_date: string | null
          qr_code: string | null
          serial_number: string | null
          status: string
          technical_data: Json
          updated_at: string
          warranty_until: string | null
        }
        Insert: {
          asset_category_id?: string | null
          barcode?: string | null
          branch_id?: string | null
          code?: string | null
          created_at?: string
          created_by_user_id?: string | null
          criticality?: string | null
          default_responsible_member_id?: string | null
          description?: string | null
          id?: string
          image_url?: string | null
          location_text?: string | null
          manufacturer?: string | null
          metadata?: Json
          model?: string | null
          name: string
          node_type?: string
          organization_id: string
          parent_asset_id?: string | null
          purchase_date?: string | null
          qr_code?: string | null
          serial_number?: string | null
          status?: string
          technical_data?: Json
          updated_at?: string
          warranty_until?: string | null
        }
        Update: {
          asset_category_id?: string | null
          barcode?: string | null
          branch_id?: string | null
          code?: string | null
          created_at?: string
          created_by_user_id?: string | null
          criticality?: string | null
          default_responsible_member_id?: string | null
          description?: string | null
          id?: string
          image_url?: string | null
          location_text?: string | null
          manufacturer?: string | null
          metadata?: Json
          model?: string | null
          name?: string
          node_type?: string
          organization_id?: string
          parent_asset_id?: string | null
          purchase_date?: string | null
          qr_code?: string | null
          serial_number?: string | null
          status?: string
          technical_data?: Json
          updated_at?: string
          warranty_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "assets_asset_category_id_fkey"
            columns: ["asset_category_id"]
            isOneToOne: false
            referencedRelation: "asset_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assets_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "client_branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assets_default_responsible_member_id_fkey"
            columns: ["default_responsible_member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assets_parent_asset_id_fkey"
            columns: ["parent_asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
        ]
      }
      assignments: {
        Row: {
          approver_id: string | null
          approver_name: string | null
          assigned_at: string
          id: string
          max_deadline: string
          provider_id: string
          reason: string | null
          rejection_reason: string | null
          request_id: string
          responded_at: string | null
          reviewer_id: string | null
          reviewer_name: string | null
          status: Database["public"]["Enums"]["assignment_status"]
          team_member_id: string
          team_member_name: string
        }
        Insert: {
          approver_id?: string | null
          approver_name?: string | null
          assigned_at?: string
          id?: string
          max_deadline: string
          provider_id: string
          reason?: string | null
          rejection_reason?: string | null
          request_id: string
          responded_at?: string | null
          reviewer_id?: string | null
          reviewer_name?: string | null
          status?: Database["public"]["Enums"]["assignment_status"]
          team_member_id: string
          team_member_name: string
        }
        Update: {
          approver_id?: string | null
          approver_name?: string | null
          assigned_at?: string
          id?: string
          max_deadline?: string
          provider_id?: string
          reason?: string | null
          rejection_reason?: string | null
          request_id?: string
          responded_at?: string | null
          reviewer_id?: string | null
          reviewer_name?: string | null
          status?: Database["public"]["Enums"]["assignment_status"]
          team_member_id?: string
          team_member_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "assignments_approver_id_fkey"
            columns: ["approver_id"]
            isOneToOne: false
            referencedRelation: "team_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_provider_id_fkey"
            columns: ["provider_id"]
            isOneToOne: false
            referencedRelation: "providers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "team_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_team_member_id_fkey"
            columns: ["team_member_id"]
            isOneToOne: false
            referencedRelation: "team_members"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_logs: {
        Row: {
          action: string
          actor_user_id: string | null
          created_at: string
          id: string
          new_data: Json | null
          old_data: Json | null
          organization_id: string | null
          record_id: string | null
          table_name: string
        }
        Insert: {
          action: string
          actor_user_id?: string | null
          created_at?: string
          id?: string
          new_data?: Json | null
          old_data?: Json | null
          organization_id?: string | null
          record_id?: string | null
          table_name: string
        }
        Update: {
          action?: string
          actor_user_id?: string | null
          created_at?: string
          id?: string
          new_data?: Json | null
          old_data?: Json | null
          organization_id?: string | null
          record_id?: string | null
          table_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      chat_messages: {
        Row: {
          created_at: string
          id: string
          message: string
          parent_id: string | null
          quote_id: string | null
          request_id: string | null
          sender_email: string | null
          sender_name: string | null
          sender_type: string
        }
        Insert: {
          created_at?: string
          id?: string
          message: string
          parent_id?: string | null
          quote_id?: string | null
          request_id?: string | null
          sender_email?: string | null
          sender_name?: string | null
          sender_type: string
        }
        Update: {
          created_at?: string
          id?: string
          message?: string
          parent_id?: string | null
          quote_id?: string | null
          request_id?: string | null
          sender_email?: string | null
          sender_name?: string | null
          sender_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "chat_messages_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "chat_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_messages_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_messages_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      checklist_template_items: {
        Row: {
          created_at: string
          help_text: string | null
          id: string
          is_active: boolean
          is_required: boolean
          question: string
          section: string | null
          sequence: number
          template_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          help_text?: string | null
          id?: string
          is_active?: boolean
          is_required?: boolean
          question: string
          section?: string | null
          sequence?: number
          template_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          help_text?: string | null
          id?: string
          is_active?: boolean
          is_required?: boolean
          question?: string
          section?: string | null
          sequence?: number
          template_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "checklist_template_items_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "checklist_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      checklist_template_response_options: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          is_failure: boolean
          label: string
          score: number | null
          sequence: number
          template_id: string
          value: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          is_failure?: boolean
          label: string
          score?: number | null
          sequence?: number
          template_id: string
          value: string
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          is_failure?: boolean
          label?: string
          score?: number | null
          sequence?: number
          template_id?: string
          value?: string
        }
        Relationships: [
          {
            foreignKeyName: "checklist_template_response_options_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "checklist_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      checklist_templates: {
        Row: {
          category: string | null
          created_at: string
          created_by_user_id: string | null
          description: string | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          category?: string | null
          created_at?: string
          created_by_user_id?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          category?: string | null
          created_at?: string
          created_by_user_id?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "checklist_templates_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      client_approved_providers: {
        Row: {
          client_email: string
          created_at: string
          email: string
          id: string
          name: string
          phone: string | null
          specialty: string | null
          updated_at: string
        }
        Insert: {
          client_email: string
          created_at?: string
          email: string
          id?: string
          name: string
          phone?: string | null
          specialty?: string | null
          updated_at?: string
        }
        Update: {
          client_email?: string
          created_at?: string
          email?: string
          id?: string
          name?: string
          phone?: string | null
          specialty?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      client_branches: {
        Row: {
          address: string | null
          city: string
          client_email: string | null
          created_at: string
          id: string
          is_active: boolean
          name: string
          organization_id: string | null
          site: string
          updated_at: string
        }
        Insert: {
          address?: string | null
          city: string
          client_email?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          organization_id?: string | null
          site: string
          updated_at?: string
        }
        Update: {
          address?: string | null
          city?: string
          client_email?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          organization_id?: string | null
          site?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_branches_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      client_specialties: {
        Row: {
          client_email: string
          created_at: string
          id: string
          name: string
        }
        Insert: {
          client_email: string
          created_at?: string
          id?: string
          name: string
        }
        Update: {
          client_email?: string
          created_at?: string
          id?: string
          name?: string
        }
        Relationships: []
      }
      criticality_matrix_templates: {
        Row: {
          category: string | null
          created_at: string
          created_by_user_id: string | null
          critical_min: number | null
          description: string | null
          high_min: number | null
          id: string
          is_active: boolean
          medium_min: number | null
          name: string
          organization_id: string | null
          scope: string
          updated_at: string
        }
        Insert: {
          category?: string | null
          created_at?: string
          created_by_user_id?: string | null
          critical_min?: number | null
          description?: string | null
          high_min?: number | null
          id?: string
          is_active?: boolean
          medium_min?: number | null
          name: string
          organization_id?: string | null
          scope?: string
          updated_at?: string
        }
        Update: {
          category?: string | null
          created_at?: string
          created_by_user_id?: string | null
          critical_min?: number | null
          description?: string | null
          high_min?: number | null
          id?: string
          is_active?: boolean
          medium_min?: number | null
          name?: string
          organization_id?: string | null
          scope?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "criticality_matrix_templates_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      criticality_parameter_options: {
        Row: {
          code: string
          created_at: string
          id: string
          is_active: boolean
          label: string
          parameter_id: string
          score: number
          sequence: number
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          is_active?: boolean
          label: string
          parameter_id: string
          score?: number
          sequence?: number
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          is_active?: boolean
          label?: string
          parameter_id?: string
          score?: number
          sequence?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "criticality_parameter_options_parameter_id_fkey"
            columns: ["parameter_id"]
            isOneToOne: false
            referencedRelation: "criticality_parameters"
            referencedColumns: ["id"]
          },
        ]
      }
      criticality_parameters: {
        Row: {
          code: string
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          sequence: number
          updated_at: string
          weight: number
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          organization_id: string
          sequence?: number
          updated_at?: string
          weight?: number
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          organization_id?: string
          sequence?: number
          updated_at?: string
          weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "criticality_parameters_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      criticality_template_options: {
        Row: {
          code: string
          created_at: string
          id: string
          is_active: boolean
          label: string
          score: number
          sequence: number
          template_parameter_id: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          is_active?: boolean
          label: string
          score?: number
          sequence?: number
          template_parameter_id: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          is_active?: boolean
          label?: string
          score?: number
          sequence?: number
          template_parameter_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "criticality_template_options_template_parameter_id_fkey"
            columns: ["template_parameter_id"]
            isOneToOne: false
            referencedRelation: "criticality_template_parameters"
            referencedColumns: ["id"]
          },
        ]
      }
      criticality_template_parameters: {
        Row: {
          code: string
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
          sequence: number
          template_id: string
          updated_at: string
          weight: number
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          sequence?: number
          template_id: string
          updated_at?: string
          weight?: number
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          sequence?: number
          template_id?: string
          updated_at?: string
          weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "criticality_template_parameters_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "criticality_matrix_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      criticality_thresholds: {
        Row: {
          created_at: string
          critical_min: number
          high_min: number
          medium_min: number
          organization_id: string
          updated_at: string
          updated_by_user_id: string | null
        }
        Insert: {
          created_at?: string
          critical_min: number
          high_min: number
          medium_min: number
          organization_id: string
          updated_at?: string
          updated_by_user_id?: string | null
        }
        Update: {
          created_at?: string
          critical_min?: number
          high_min?: number
          medium_min?: number
          organization_id?: string
          updated_at?: string
          updated_by_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "criticality_thresholds_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      inspection_plan_alert_rules: {
        Row: {
          alert_type: string
          created_at: string
          days_before: number | null
          id: string
          is_active: boolean
          label: string | null
          organization_id: string
          plan_id: string
          updated_at: string
        }
        Insert: {
          alert_type: string
          created_at?: string
          days_before?: number | null
          id?: string
          is_active?: boolean
          label?: string | null
          organization_id: string
          plan_id: string
          updated_at?: string
        }
        Update: {
          alert_type?: string
          created_at?: string
          days_before?: number | null
          id?: string
          is_active?: boolean
          label?: string | null
          organization_id?: string
          plan_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inspection_plan_alert_rules_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_plan_alert_rules_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "inspection_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      inspection_plans: {
        Row: {
          area_asset_id: string | null
          asset_id: string | null
          branch_id: string | null
          created_at: string
          created_by_user_id: string | null
          custom_interval: number | null
          custom_unit: string | null
          description: string | null
          frequency: string
          id: string
          is_active: boolean
          next_due_at: string | null
          organization_id: string
          responsible_member_id: string | null
          start_date: string
          template_id: string
          title: string
          updated_at: string
        }
        Insert: {
          area_asset_id?: string | null
          asset_id?: string | null
          branch_id?: string | null
          created_at?: string
          created_by_user_id?: string | null
          custom_interval?: number | null
          custom_unit?: string | null
          description?: string | null
          frequency?: string
          id?: string
          is_active?: boolean
          next_due_at?: string | null
          organization_id: string
          responsible_member_id?: string | null
          start_date?: string
          template_id: string
          title: string
          updated_at?: string
        }
        Update: {
          area_asset_id?: string | null
          asset_id?: string | null
          branch_id?: string | null
          created_at?: string
          created_by_user_id?: string | null
          custom_interval?: number | null
          custom_unit?: string | null
          description?: string | null
          frequency?: string
          id?: string
          is_active?: boolean
          next_due_at?: string | null
          organization_id?: string
          responsible_member_id?: string | null
          start_date?: string
          template_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inspection_plans_area_asset_id_fkey"
            columns: ["area_asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_plans_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_plans_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "client_branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_plans_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_plans_responsible_member_id_fkey"
            columns: ["responsible_member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_plans_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "checklist_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      inspection_run_answers: {
        Row: {
          created_at: string
          id: string
          is_failure: boolean
          item_question: string
          observations: string | null
          response_label: string | null
          response_option_id: string | null
          response_value: string | null
          run_id: string
          template_item_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_failure?: boolean
          item_question: string
          observations?: string | null
          response_label?: string | null
          response_option_id?: string | null
          response_value?: string | null
          run_id: string
          template_item_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          is_failure?: boolean
          item_question?: string
          observations?: string | null
          response_label?: string | null
          response_option_id?: string | null
          response_value?: string | null
          run_id?: string
          template_item_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inspection_run_answers_response_option_id_fkey"
            columns: ["response_option_id"]
            isOneToOne: false
            referencedRelation: "checklist_template_response_options"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_run_answers_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "inspection_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_run_answers_template_item_id_fkey"
            columns: ["template_item_id"]
            isOneToOne: false
            referencedRelation: "checklist_template_items"
            referencedColumns: ["id"]
          },
        ]
      }
      inspection_run_evidences: {
        Row: {
          answer_id: string | null
          created_at: string
          file_name: string
          file_path: string | null
          file_url: string | null
          id: string
          mime_type: string | null
          notes: string | null
          run_id: string
          size_bytes: number | null
        }
        Insert: {
          answer_id?: string | null
          created_at?: string
          file_name: string
          file_path?: string | null
          file_url?: string | null
          id?: string
          mime_type?: string | null
          notes?: string | null
          run_id: string
          size_bytes?: number | null
        }
        Update: {
          answer_id?: string | null
          created_at?: string
          file_name?: string
          file_path?: string | null
          file_url?: string | null
          id?: string
          mime_type?: string | null
          notes?: string | null
          run_id?: string
          size_bytes?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "inspection_run_evidences_answer_id_fkey"
            columns: ["answer_id"]
            isOneToOne: false
            referencedRelation: "inspection_run_answers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_run_evidences_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "inspection_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      inspection_runs: {
        Row: {
          area_asset_id: string | null
          asset_id: string | null
          branch_id: string | null
          completed_at: string | null
          created_at: string
          created_by_user_id: string | null
          id: string
          notes: string | null
          organization_id: string
          plan_id: string | null
          responsible_member_id: string | null
          result: string | null
          scheduled_for: string | null
          started_at: string | null
          status: string
          template_id: string
          updated_at: string
        }
        Insert: {
          area_asset_id?: string | null
          asset_id?: string | null
          branch_id?: string | null
          completed_at?: string | null
          created_at?: string
          created_by_user_id?: string | null
          id?: string
          notes?: string | null
          organization_id: string
          plan_id?: string | null
          responsible_member_id?: string | null
          result?: string | null
          scheduled_for?: string | null
          started_at?: string | null
          status?: string
          template_id: string
          updated_at?: string
        }
        Update: {
          area_asset_id?: string | null
          asset_id?: string | null
          branch_id?: string | null
          completed_at?: string | null
          created_at?: string
          created_by_user_id?: string | null
          id?: string
          notes?: string | null
          organization_id?: string
          plan_id?: string | null
          responsible_member_id?: string | null
          result?: string | null
          scheduled_for?: string | null
          started_at?: string | null
          status?: string
          template_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inspection_runs_area_asset_id_fkey"
            columns: ["area_asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_runs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_runs_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "client_branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_runs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_runs_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "inspection_plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_runs_responsible_member_id_fkey"
            columns: ["responsible_member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspection_runs_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "checklist_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      maintenance_card_materials: {
        Row: {
          card_id: string
          created_at: string
          description: string
          id: string
          material_id: string | null
          notes: string | null
          quantity: number
          sequence: number
          unit: string
        }
        Insert: {
          card_id: string
          created_at?: string
          description: string
          id?: string
          material_id?: string | null
          notes?: string | null
          quantity: number
          sequence: number
          unit: string
        }
        Update: {
          card_id?: string
          created_at?: string
          description?: string
          id?: string
          material_id?: string | null
          notes?: string | null
          quantity?: number
          sequence?: number
          unit?: string
        }
        Relationships: [
          {
            foreignKeyName: "maintenance_card_materials_card_id_fkey"
            columns: ["card_id"]
            isOneToOne: false
            referencedRelation: "maintenance_cards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maintenance_card_materials_material_id_fkey"
            columns: ["material_id"]
            isOneToOne: false
            referencedRelation: "materials"
            referencedColumns: ["id"]
          },
        ]
      }
      maintenance_card_tasks: {
        Row: {
          card_id: string
          created_at: string
          description: string | null
          estimated_hours: number | null
          id: string
          is_required: boolean
          sequence: number
          title: string
        }
        Insert: {
          card_id: string
          created_at?: string
          description?: string | null
          estimated_hours?: number | null
          id?: string
          is_required?: boolean
          sequence: number
          title: string
        }
        Update: {
          card_id?: string
          created_at?: string
          description?: string | null
          estimated_hours?: number | null
          id?: string
          is_required?: boolean
          sequence?: number
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "maintenance_card_tasks_card_id_fkey"
            columns: ["card_id"]
            isOneToOne: false
            referencedRelation: "maintenance_cards"
            referencedColumns: ["id"]
          },
        ]
      }
      maintenance_cards: {
        Row: {
          category: string | null
          code: string
          created_at: string
          created_by_user_id: string | null
          description: string | null
          estimated_hours: number | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          procedure_notes: string | null
          safety_notes: string | null
          updated_at: string
        }
        Insert: {
          category?: string | null
          code: string
          created_at?: string
          created_by_user_id?: string | null
          description?: string | null
          estimated_hours?: number | null
          id?: string
          is_active?: boolean
          name: string
          organization_id: string
          procedure_notes?: string | null
          safety_notes?: string | null
          updated_at?: string
        }
        Update: {
          category?: string | null
          code?: string
          created_at?: string
          created_by_user_id?: string | null
          description?: string | null
          estimated_hours?: number | null
          id?: string
          is_active?: boolean
          name?: string
          organization_id?: string
          procedure_notes?: string | null
          safety_notes?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "maintenance_cards_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      maintenance_notice_counters: {
        Row: {
          last_number: number
          organization_id: string
          year: number
        }
        Insert: {
          last_number?: number
          organization_id: string
          year: number
        }
        Update: {
          last_number?: number
          organization_id?: string
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "maintenance_notice_counters_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      maintenance_notices: {
        Row: {
          asset_code_snapshot: string | null
          asset_id: string
          asset_name_snapshot: string | null
          asset_path_snapshot: string | null
          branch_id_snapshot: string | null
          branch_name_snapshot: string | null
          converted_at: string | null
          converted_by_user_id: string | null
          converted_request_id: string | null
          created_at: string
          description: string
          dismissal_reason: string | null
          dismissed_at: string | null
          dismissed_by_user_id: string | null
          id: string
          notice_number: string
          organization_id: string
          priority: string
          reported_at: string
          reported_by_user_id: string | null
          responsible_member_id: string | null
          source_id: string | null
          source_metadata: Json
          source_type: string
          status: string
          title: string
          triage_notes: string | null
          triaged_at: string | null
          triaged_by_user_id: string | null
          updated_at: string
        }
        Insert: {
          asset_code_snapshot?: string | null
          asset_id: string
          asset_name_snapshot?: string | null
          asset_path_snapshot?: string | null
          branch_id_snapshot?: string | null
          branch_name_snapshot?: string | null
          converted_at?: string | null
          converted_by_user_id?: string | null
          converted_request_id?: string | null
          created_at?: string
          description: string
          dismissal_reason?: string | null
          dismissed_at?: string | null
          dismissed_by_user_id?: string | null
          id?: string
          notice_number: string
          organization_id: string
          priority?: string
          reported_at?: string
          reported_by_user_id?: string | null
          responsible_member_id?: string | null
          source_id?: string | null
          source_metadata?: Json
          source_type?: string
          status?: string
          title: string
          triage_notes?: string | null
          triaged_at?: string | null
          triaged_by_user_id?: string | null
          updated_at?: string
        }
        Update: {
          asset_code_snapshot?: string | null
          asset_id?: string
          asset_name_snapshot?: string | null
          asset_path_snapshot?: string | null
          branch_id_snapshot?: string | null
          branch_name_snapshot?: string | null
          converted_at?: string | null
          converted_by_user_id?: string | null
          converted_request_id?: string | null
          created_at?: string
          description?: string
          dismissal_reason?: string | null
          dismissed_at?: string | null
          dismissed_by_user_id?: string | null
          id?: string
          notice_number?: string
          organization_id?: string
          priority?: string
          reported_at?: string
          reported_by_user_id?: string | null
          responsible_member_id?: string | null
          source_id?: string | null
          source_metadata?: Json
          source_type?: string
          status?: string
          title?: string
          triage_notes?: string | null
          triaged_at?: string | null
          triaged_by_user_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "maintenance_notices_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maintenance_notices_branch_id_snapshot_fkey"
            columns: ["branch_id_snapshot"]
            isOneToOne: false
            referencedRelation: "client_branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maintenance_notices_converted_request_id_fkey"
            columns: ["converted_request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maintenance_notices_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maintenance_notices_responsible_member_id_fkey"
            columns: ["responsible_member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
        ]
      }
      materials: {
        Row: {
          code: string
          created_at: string
          id: string
          is_active: boolean
          name: string
          organization_id: string
          stock: number
          unit: string
          updated_at: string
          warehouse_id: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          organization_id: string
          stock?: number
          unit: string
          updated_at?: string
          warehouse_id: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          organization_id?: string
          stock?: number
          unit?: string
          updated_at?: string
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "materials_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "materials_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          created_at: string
          id: string
          message: string
          quote_id: string | null
          read: boolean
          request_id: string | null
          title: string
          type: Database["public"]["Enums"]["notification_type"]
          user_email: string
        }
        Insert: {
          created_at?: string
          id?: string
          message: string
          quote_id?: string | null
          read?: boolean
          request_id?: string | null
          title: string
          type: Database["public"]["Enums"]["notification_type"]
          user_email: string
        }
        Update: {
          created_at?: string
          id?: string
          message?: string
          quote_id?: string | null
          read?: boolean
          request_id?: string | null
          title?: string
          type?: Database["public"]["Enums"]["notification_type"]
          user_email?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_invitations: {
        Row: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string
          invited_name: string | null
          last_send_attempt_at: string | null
          last_sent_at: string | null
          organization_id: string
          revoked_at: string | null
          revoked_by: string | null
          role: Database["public"]["Enums"]["organization_member_role"]
          send_count: number
          status: Database["public"]["Enums"]["organization_invitation_status"]
          token_hash: string | null
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email: string
          expires_at?: string
          id?: string
          invited_by: string
          invited_name?: string | null
          last_send_attempt_at?: string | null
          last_sent_at?: string | null
          organization_id: string
          revoked_at?: string | null
          revoked_by?: string | null
          role: Database["public"]["Enums"]["organization_member_role"]
          send_count?: number
          status?: Database["public"]["Enums"]["organization_invitation_status"]
          token_hash?: string | null
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string
          invited_name?: string | null
          last_send_attempt_at?: string | null
          last_sent_at?: string | null
          organization_id?: string
          revoked_at?: string | null
          revoked_by?: string | null
          role?: Database["public"]["Enums"]["organization_member_role"]
          send_count?: number
          status?: Database["public"]["Enums"]["organization_invitation_status"]
          token_hash?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_invitations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_members: {
        Row: {
          id: string
          invited_by: string | null
          is_active: boolean
          joined_at: string
          organization_id: string
          role: Database["public"]["Enums"]["organization_member_role"]
          updated_at: string
          user_id: string
        }
        Insert: {
          id?: string
          invited_by?: string | null
          is_active?: boolean
          joined_at?: string
          organization_id: string
          role?: Database["public"]["Enums"]["organization_member_role"]
          updated_at?: string
          user_id: string
        }
        Update: {
          id?: string
          invited_by?: string | null
          is_active?: boolean
          joined_at?: string
          organization_id?: string
          role?: Database["public"]["Enums"]["organization_member_role"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_members_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_notifications: {
        Row: {
          actor_user_id: string | null
          created_at: string
          entity_id: string | null
          entity_type: string | null
          id: string
          is_read: boolean
          message: string
          metadata: Json
          organization_id: string
          priority: string
          read_at: string | null
          recipient_member_id: string | null
          related_quote_id: string | null
          related_request_id: string | null
          title: string
          type: string
        }
        Insert: {
          actor_user_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          is_read?: boolean
          message: string
          metadata?: Json
          organization_id: string
          priority?: string
          read_at?: string | null
          recipient_member_id?: string | null
          related_quote_id?: string | null
          related_request_id?: string | null
          title: string
          type: string
        }
        Update: {
          actor_user_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          is_read?: boolean
          message?: string
          metadata?: Json
          organization_id?: string
          priority?: string
          read_at?: string | null
          recipient_member_id?: string | null
          related_quote_id?: string | null
          related_request_id?: string | null
          title?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_notifications_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_notifications_recipient_member_id_fkey"
            columns: ["recipient_member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_notifications_related_quote_id_fkey"
            columns: ["related_quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_notifications_related_request_id_fkey"
            columns: ["related_request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_profiles: {
        Row: {
          certification_notes: string | null
          certification_status: string
          commercial_name: string | null
          contact_email: string | null
          country: string
          created_at: string
          currency: string
          description: string | null
          employee_range: string | null
          founded_year: number | null
          legal_name: string | null
          logo_url: string | null
          organization_id: string
          phone: string | null
          presentation_file_url: string | null
          primary_clients: Json
          service_regions: string | null
          specialties: string[]
          tax_id: string | null
          timezone: string
          updated_at: string
          updated_by_user_id: string | null
          website: string | null
          whatsapp: string | null
        }
        Insert: {
          certification_notes?: string | null
          certification_status?: string
          commercial_name?: string | null
          contact_email?: string | null
          country?: string
          created_at?: string
          currency?: string
          description?: string | null
          employee_range?: string | null
          founded_year?: number | null
          legal_name?: string | null
          logo_url?: string | null
          organization_id: string
          phone?: string | null
          presentation_file_url?: string | null
          primary_clients?: Json
          service_regions?: string | null
          specialties?: string[]
          tax_id?: string | null
          timezone?: string
          updated_at?: string
          updated_by_user_id?: string | null
          website?: string | null
          whatsapp?: string | null
        }
        Update: {
          certification_notes?: string | null
          certification_status?: string
          commercial_name?: string | null
          contact_email?: string | null
          country?: string
          created_at?: string
          currency?: string
          description?: string | null
          employee_range?: string | null
          founded_year?: number | null
          legal_name?: string | null
          logo_url?: string | null
          organization_id?: string
          phone?: string | null
          presentation_file_url?: string | null
          primary_clients?: Json
          service_regions?: string | null
          specialties?: string[]
          tax_id?: string | null
          timezone?: string
          updated_at?: string
          updated_by_user_id?: string | null
          website?: string | null
          whatsapp?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_profiles_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_relationships: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          relationship_type: Database["public"]["Enums"]["organization_relationship_type"]
          source_organization_id: string
          status: Database["public"]["Enums"]["organization_relationship_status"]
          target_organization_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          relationship_type: Database["public"]["Enums"]["organization_relationship_type"]
          source_organization_id: string
          status?: Database["public"]["Enums"]["organization_relationship_status"]
          target_organization_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          relationship_type?: Database["public"]["Enums"]["organization_relationship_type"]
          source_organization_id?: string
          status?: Database["public"]["Enums"]["organization_relationship_status"]
          target_organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_relationships_source_organization_id_fkey"
            columns: ["source_organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_relationships_target_organization_id_fkey"
            columns: ["target_organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          legal_name: string | null
          name: string
          organization_type: Database["public"]["Enums"]["organization_type"]
          settings: Json
          status: string
          tax_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          legal_name?: string | null
          name: string
          organization_type: Database["public"]["Enums"]["organization_type"]
          settings?: Json
          status?: string
          tax_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          legal_name?: string | null
          name?: string
          organization_type?: Database["public"]["Enums"]["organization_type"]
          settings?: Json
          status?: string
          tax_id?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      preventive_maintenance_occurrences: {
        Row: {
          asset_id: string
          cancel_reason: string | null
          cancelled_at: string | null
          completed_at: string | null
          completion_meter_reading_id: string | null
          completion_meter_value: number | null
          created_at: string
          due_at: string | null
          due_meter_value: number | null
          id: string
          organization_id: string
          plan_id: string
          planned_at: string | null
          request_creation_id: string
          request_id: string | null
          scope_snapshot: Json
          sequence: number
          skip_reason: string | null
          skipped_at: string | null
          status: string
          updated_at: string
          work_order_id: string | null
        }
        Insert: {
          asset_id: string
          cancel_reason?: string | null
          cancelled_at?: string | null
          completed_at?: string | null
          completion_meter_reading_id?: string | null
          completion_meter_value?: number | null
          created_at?: string
          due_at?: string | null
          due_meter_value?: number | null
          id?: string
          organization_id: string
          plan_id: string
          planned_at?: string | null
          request_creation_id?: string
          request_id?: string | null
          scope_snapshot: Json
          sequence: number
          skip_reason?: string | null
          skipped_at?: string | null
          status?: string
          updated_at?: string
          work_order_id?: string | null
        }
        Update: {
          asset_id?: string
          cancel_reason?: string | null
          cancelled_at?: string | null
          completed_at?: string | null
          completion_meter_reading_id?: string | null
          completion_meter_value?: number | null
          created_at?: string
          due_at?: string | null
          due_meter_value?: number | null
          id?: string
          organization_id?: string
          plan_id?: string
          planned_at?: string | null
          request_creation_id?: string
          request_id?: string | null
          scope_snapshot?: Json
          sequence?: number
          skip_reason?: string | null
          skipped_at?: string | null
          status?: string
          updated_at?: string
          work_order_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "preventive_maintenance_occurre_completion_meter_reading_id_fkey"
            columns: ["completion_meter_reading_id"]
            isOneToOne: false
            referencedRelation: "asset_meter_readings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preventive_maintenance_occurrences_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preventive_maintenance_occurrences_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preventive_maintenance_occurrences_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "preventive_maintenance_plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preventive_maintenance_occurrences_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preventive_maintenance_occurrences_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      preventive_maintenance_plans: {
        Row: {
          asset_id: string
          baseline_reading_id: string | null
          baseline_value: number | null
          card_id: string
          created_at: string
          created_by_user_id: string | null
          custom_interval: number | null
          custom_unit: string | null
          default_request_type: string
          first_due_at: string | null
          frequency: string | null
          id: string
          interval_value: number | null
          is_active: boolean
          meter_id: string | null
          meter_lead_value: number | null
          organization_id: string
          planning_lead_days: number
          priority: string
          responsible_member_id: string | null
          trigger_type: string
          updated_at: string
        }
        Insert: {
          asset_id: string
          baseline_reading_id?: string | null
          baseline_value?: number | null
          card_id: string
          created_at?: string
          created_by_user_id?: string | null
          custom_interval?: number | null
          custom_unit?: string | null
          default_request_type?: string
          first_due_at?: string | null
          frequency?: string | null
          id?: string
          interval_value?: number | null
          is_active?: boolean
          meter_id?: string | null
          meter_lead_value?: number | null
          organization_id: string
          planning_lead_days?: number
          priority?: string
          responsible_member_id?: string | null
          trigger_type: string
          updated_at?: string
        }
        Update: {
          asset_id?: string
          baseline_reading_id?: string | null
          baseline_value?: number | null
          card_id?: string
          created_at?: string
          created_by_user_id?: string | null
          custom_interval?: number | null
          custom_unit?: string | null
          default_request_type?: string
          first_due_at?: string | null
          frequency?: string | null
          id?: string
          interval_value?: number | null
          is_active?: boolean
          meter_id?: string | null
          meter_lead_value?: number | null
          organization_id?: string
          planning_lead_days?: number
          priority?: string
          responsible_member_id?: string | null
          trigger_type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "preventive_maintenance_plans_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preventive_maintenance_plans_baseline_reading_id_fkey"
            columns: ["baseline_reading_id"]
            isOneToOne: false
            referencedRelation: "asset_meter_readings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preventive_maintenance_plans_card_id_fkey"
            columns: ["card_id"]
            isOneToOne: false
            referencedRelation: "maintenance_cards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preventive_maintenance_plans_meter_id_fkey"
            columns: ["meter_id"]
            isOneToOne: false
            referencedRelation: "asset_meters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preventive_maintenance_plans_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preventive_maintenance_plans_responsible_member_id_fkey"
            columns: ["responsible_member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          email: string
          id: string
          name: string | null
          provider_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          email: string
          id: string
          name?: string | null
          provider_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          email?: string
          id?: string
          name?: string | null
          provider_id?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      provider_commercial_clients: {
        Row: {
          business_name: string
          contact_person: string | null
          created_at: string
          email: string | null
          extension: string | null
          id: string
          phone: string | null
          provider_id: string
          updated_at: string
        }
        Insert: {
          business_name: string
          contact_person?: string | null
          created_at?: string
          email?: string | null
          extension?: string | null
          id?: string
          phone?: string | null
          provider_id: string
          updated_at?: string
        }
        Update: {
          business_name?: string
          contact_person?: string | null
          created_at?: string
          email?: string | null
          extension?: string | null
          id?: string
          phone?: string | null
          provider_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      provider_documents: {
        Row: {
          created_at: string
          document_type: string
          file_name: string
          file_url: string
          id: string
          provider_id: string
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          document_type: string
          file_name: string
          file_url: string
          id?: string
          provider_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          document_type?: string
          file_name?: string
          file_url?: string
          id?: string
          provider_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      provider_profiles: {
        Row: {
          business_name: string | null
          certification_status: Database["public"]["Enums"]["certification_status"]
          city: string | null
          commercial_name: string | null
          company_description: string | null
          contact_email: string | null
          contact_name: string | null
          country: string | null
          coverage_area: string | null
          created_at: string
          currency: string | null
          employee_range: string | null
          fiscal_address: string | null
          foundation_year: number | null
          industry: string | null
          logo_url: string | null
          owner_user_id: string
          phone: string | null
          position: string | null
          presentation_letter_name: string | null
          presentation_letter_url: string | null
          provider_id: string
          receive_all_invitations: boolean
          region: string | null
          tax_id: string | null
          timezone: string | null
          updated_at: string
          website: string | null
          whatsapp_phone: string | null
        }
        Insert: {
          business_name?: string | null
          certification_status?: Database["public"]["Enums"]["certification_status"]
          city?: string | null
          commercial_name?: string | null
          company_description?: string | null
          contact_email?: string | null
          contact_name?: string | null
          country?: string | null
          coverage_area?: string | null
          created_at?: string
          currency?: string | null
          employee_range?: string | null
          fiscal_address?: string | null
          foundation_year?: number | null
          industry?: string | null
          logo_url?: string | null
          owner_user_id: string
          phone?: string | null
          position?: string | null
          presentation_letter_name?: string | null
          presentation_letter_url?: string | null
          provider_id: string
          receive_all_invitations?: boolean
          region?: string | null
          tax_id?: string | null
          timezone?: string | null
          updated_at?: string
          website?: string | null
          whatsapp_phone?: string | null
        }
        Update: {
          business_name?: string | null
          certification_status?: Database["public"]["Enums"]["certification_status"]
          city?: string | null
          commercial_name?: string | null
          company_description?: string | null
          contact_email?: string | null
          contact_name?: string | null
          country?: string | null
          coverage_area?: string | null
          created_at?: string
          currency?: string | null
          employee_range?: string | null
          fiscal_address?: string | null
          foundation_year?: number | null
          industry?: string | null
          logo_url?: string | null
          owner_user_id?: string
          phone?: string | null
          position?: string | null
          presentation_letter_name?: string | null
          presentation_letter_url?: string | null
          provider_id?: string
          receive_all_invitations?: boolean
          region?: string | null
          tax_id?: string | null
          timezone?: string | null
          updated_at?: string
          website?: string | null
          whatsapp_phone?: string | null
        }
        Relationships: []
      }
      providers: {
        Row: {
          certified: boolean | null
          created_at: string
          email: string
          id: string
          name: string
          organization_id: string | null
          rating: number | null
          specialties: string[]
        }
        Insert: {
          certified?: boolean | null
          created_at?: string
          email: string
          id?: string
          name: string
          organization_id?: string | null
          rating?: number | null
          specialties?: string[]
        }
        Update: {
          certified?: boolean | null
          created_at?: string
          email?: string
          id?: string
          name?: string
          organization_id?: string | null
          rating?: number | null
          specialties?: string[]
        }
        Relationships: [
          {
            foreignKeyName: "providers_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      quote_templates: {
        Row: {
          created_at: string
          fields: Json
          id: string
          name: string
          percentage_fields: Json
          provider_id: string
          team_member_id: string | null
        }
        Insert: {
          created_at?: string
          fields?: Json
          id?: string
          name: string
          percentage_fields?: Json
          provider_id: string
          team_member_id?: string | null
        }
        Update: {
          created_at?: string
          fields?: Json
          id?: string
          name?: string
          percentage_fields?: Json
          provider_id?: string
          team_member_id?: string | null
        }
        Relationships: []
      }
      quotes: {
        Row: {
          amount: number
          approval_reason: string | null
          approved_at: string | null
          approved_by_user_id: string | null
          base_subtotal: number
          client_observation: string | null
          created_at: string
          created_by_user_id: string | null
          description: string
          emailed_at: string | null
          general_expenses_amount: number
          general_expenses_percentage: number
          id: string
          igv_amount: number
          provider_id: string | null
          provider_organization_id: string | null
          quote_sections: Json
          rejected_at: string | null
          rejected_by_user_id: string | null
          rejection_reason: string | null
          request_id: string
          sales_conditions: Json
          sent_at: string | null
          status: string
          subtotal: number
          team_member_id: string | null
          total_amount: number
          updated_at: string
          utilities_amount: number
          utilities_percentage: number
        }
        Insert: {
          amount: number
          approval_reason?: string | null
          approved_at?: string | null
          approved_by_user_id?: string | null
          base_subtotal?: number
          client_observation?: string | null
          created_at?: string
          created_by_user_id?: string | null
          description: string
          emailed_at?: string | null
          general_expenses_amount?: number
          general_expenses_percentage?: number
          id?: string
          igv_amount?: number
          provider_id?: string | null
          provider_organization_id?: string | null
          quote_sections?: Json
          rejected_at?: string | null
          rejected_by_user_id?: string | null
          rejection_reason?: string | null
          request_id: string
          sales_conditions?: Json
          sent_at?: string | null
          status?: string
          subtotal?: number
          team_member_id?: string | null
          total_amount?: number
          updated_at?: string
          utilities_amount?: number
          utilities_percentage?: number
        }
        Update: {
          amount?: number
          approval_reason?: string | null
          approved_at?: string | null
          approved_by_user_id?: string | null
          base_subtotal?: number
          client_observation?: string | null
          created_at?: string
          created_by_user_id?: string | null
          description?: string
          emailed_at?: string | null
          general_expenses_amount?: number
          general_expenses_percentage?: number
          id?: string
          igv_amount?: number
          provider_id?: string | null
          provider_organization_id?: string | null
          quote_sections?: Json
          rejected_at?: string | null
          rejected_by_user_id?: string | null
          rejection_reason?: string | null
          request_id?: string
          sales_conditions?: Json
          sent_at?: string | null
          status?: string
          subtotal?: number
          team_member_id?: string | null
          total_amount?: number
          updated_at?: string
          utilities_amount?: number
          utilities_percentage?: number
        }
        Relationships: [
          {
            foreignKeyName: "quotes_provider_id_fkey"
            columns: ["provider_id"]
            isOneToOne: false
            referencedRelation: "providers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_provider_organization_id_fkey"
            columns: ["provider_organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_team_member_id_fkey"
            columns: ["team_member_id"]
            isOneToOne: false
            referencedRelation: "team_members"
            referencedColumns: ["id"]
          },
        ]
      }
      request_chat_participants: {
        Row: {
          id: string
          joined_at: string | null
          last_read_at: string | null
          request_id: string
          user_email: string
          user_name: string | null
          user_role: string
        }
        Insert: {
          id?: string
          joined_at?: string | null
          last_read_at?: string | null
          request_id: string
          user_email: string
          user_name?: string | null
          user_role: string
        }
        Update: {
          id?: string
          joined_at?: string | null
          last_read_at?: string | null
          request_id?: string
          user_email?: string
          user_name?: string | null
          user_role?: string
        }
        Relationships: [
          {
            foreignKeyName: "request_chat_participants_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      request_details: {
        Row: {
          activities: string | null
          area: string | null
          attachment_urls: string[] | null
          created_at: string
          delegate_type: string | null
          equipment: string | null
          id: string
          observation: string | null
          quantity: number | null
          relevant_materials: string | null
          request_id: string
          responsible_user: string | null
          sub_area: string | null
          sub_equipment: string | null
          unit_measure: string | null
          updated_at: string
        }
        Insert: {
          activities?: string | null
          area?: string | null
          attachment_urls?: string[] | null
          created_at?: string
          delegate_type?: string | null
          equipment?: string | null
          id?: string
          observation?: string | null
          quantity?: number | null
          relevant_materials?: string | null
          request_id: string
          responsible_user?: string | null
          sub_area?: string | null
          sub_equipment?: string | null
          unit_measure?: string | null
          updated_at?: string
        }
        Update: {
          activities?: string | null
          area?: string | null
          attachment_urls?: string[] | null
          created_at?: string
          delegate_type?: string | null
          equipment?: string | null
          id?: string
          observation?: string | null
          quantity?: number | null
          relevant_materials?: string | null
          request_id?: string
          responsible_user?: string | null
          sub_area?: string | null
          sub_equipment?: string | null
          unit_measure?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "request_details_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      request_provider_access: {
        Row: {
          access_type: string
          created_at: string
          id: string
          invited_by_user_id: string | null
          provider_organization_id: string
          request_id: string
          status: string
          updated_at: string
        }
        Insert: {
          access_type?: string
          created_at?: string
          id?: string
          invited_by_user_id?: string | null
          provider_organization_id: string
          request_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          access_type?: string
          created_at?: string
          id?: string
          invited_by_user_id?: string | null
          provider_organization_id?: string
          request_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "request_provider_access_provider_organization_id_fkey"
            columns: ["provider_organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "request_provider_access_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      request_providers: {
        Row: {
          created_at: string
          id: string
          provider_id: string
          request_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          provider_id: string
          request_id: string
        }
        Update: {
          created_at?: string
          id?: string
          provider_id?: string
          request_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "request_providers_provider_id_fkey"
            columns: ["provider_id"]
            isOneToOne: false
            referencedRelation: "providers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "request_providers_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      requests: {
        Row: {
          asset: string
          asset_id: string | null
          branch: string | null
          branch_id: string | null
          city: string | null
          client_branch: string | null
          client_name: string | null
          coordination_contact_email: string | null
          coordination_contact_member_id: string | null
          coordination_contact_name: string | null
          created_at: string
          created_by: string
          created_by_email: string | null
          created_by_name: string | null
          created_by_user_id: string | null
          deadline: string
          description: string
          document_urls: string[] | null
          id: string
          image_urls: string[] | null
          internal_responsible_member_id: string | null
          is_public: boolean | null
          location: string
          min_quotes: number
          notified_at: string | null
          observations: string | null
          organization_id: string | null
          priority: number
          quotes_closed: boolean
          request_number: string
          request_type: string
          requires_visit: boolean | null
          service_address: string | null
          service_type: Database["public"]["Enums"]["service_type"]
          start_time: string | null
          status: Database["public"]["Enums"]["request_status"]
          store: string | null
          title: string | null
          updated_at: string
          visit_contact_member_id: string | null
          visit_date: string | null
          visit_schedule_mode: string | null
        }
        Insert: {
          asset: string
          asset_id?: string | null
          branch?: string | null
          branch_id?: string | null
          city?: string | null
          client_branch?: string | null
          client_name?: string | null
          coordination_contact_email?: string | null
          coordination_contact_member_id?: string | null
          coordination_contact_name?: string | null
          created_at?: string
          created_by: string
          created_by_email?: string | null
          created_by_name?: string | null
          created_by_user_id?: string | null
          deadline: string
          description: string
          document_urls?: string[] | null
          id?: string
          image_urls?: string[] | null
          internal_responsible_member_id?: string | null
          is_public?: boolean | null
          location: string
          min_quotes?: number
          notified_at?: string | null
          observations?: string | null
          organization_id?: string | null
          priority?: number
          quotes_closed?: boolean
          request_number: string
          request_type?: string
          requires_visit?: boolean | null
          service_address?: string | null
          service_type: Database["public"]["Enums"]["service_type"]
          start_time?: string | null
          status?: Database["public"]["Enums"]["request_status"]
          store?: string | null
          title?: string | null
          updated_at?: string
          visit_contact_member_id?: string | null
          visit_date?: string | null
          visit_schedule_mode?: string | null
        }
        Update: {
          asset?: string
          asset_id?: string | null
          branch?: string | null
          branch_id?: string | null
          city?: string | null
          client_branch?: string | null
          client_name?: string | null
          coordination_contact_email?: string | null
          coordination_contact_member_id?: string | null
          coordination_contact_name?: string | null
          created_at?: string
          created_by?: string
          created_by_email?: string | null
          created_by_name?: string | null
          created_by_user_id?: string | null
          deadline?: string
          description?: string
          document_urls?: string[] | null
          id?: string
          image_urls?: string[] | null
          internal_responsible_member_id?: string | null
          is_public?: boolean | null
          location?: string
          min_quotes?: number
          notified_at?: string | null
          observations?: string | null
          organization_id?: string | null
          priority?: number
          quotes_closed?: boolean
          request_number?: string
          request_type?: string
          requires_visit?: boolean | null
          service_address?: string | null
          service_type?: Database["public"]["Enums"]["service_type"]
          start_time?: string | null
          status?: Database["public"]["Enums"]["request_status"]
          store?: string | null
          title?: string | null
          updated_at?: string
          visit_contact_member_id?: string | null
          visit_date?: string | null
          visit_schedule_mode?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "requests_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "requests_coordination_contact_member_id_fkey"
            columns: ["coordination_contact_member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "requests_internal_responsible_member_id_fkey"
            columns: ["internal_responsible_member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "requests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "requests_visit_contact_member_id_fkey"
            columns: ["visit_contact_member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
        ]
      }
      team_members: {
        Row: {
          created_at: string
          email: string
          id: string
          name: string
          provider_id: string
        }
        Insert: {
          created_at?: string
          email: string
          id?: string
          name: string
          provider_id: string
        }
        Update: {
          created_at?: string
          email?: string
          id?: string
          name?: string
          provider_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "team_members_provider_id_fkey"
            columns: ["provider_id"]
            isOneToOne: false
            referencedRelation: "providers"
            referencedColumns: ["id"]
          },
        ]
      }
      technical_visit_documents: {
        Row: {
          assignment_id: string | null
          created_at: string
          file_urls: string[]
          id: string
          notes: string | null
          request_id: string
          team_member_id: string
        }
        Insert: {
          assignment_id?: string | null
          created_at?: string
          file_urls: string[]
          id?: string
          notes?: string | null
          request_id: string
          team_member_id: string
        }
        Update: {
          assignment_id?: string | null
          created_at?: string
          file_urls?: string[]
          id?: string
          notes?: string | null
          request_id?: string
          team_member_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "technical_visit_documents_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "technical_visit_documents_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "technical_visit_documents_team_member_id_fkey"
            columns: ["team_member_id"]
            isOneToOne: false
            referencedRelation: "team_members"
            referencedColumns: ["id"]
          },
        ]
      }
      technical_visits: {
        Row: {
          id: string
          provider_id: string
          request_id: string
          requested_at: string
        }
        Insert: {
          id?: string
          provider_id: string
          request_id: string
          requested_at?: string
        }
        Update: {
          id?: string
          provider_id?: string
          request_id?: string
          requested_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "technical_visits_provider_id_fkey"
            columns: ["provider_id"]
            isOneToOne: false
            referencedRelation: "providers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "technical_visits_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      warehouses: {
        Row: {
          branch_id: string | null
          created_at: string
          id: string
          is_active: boolean
          name: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          branch_id?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          branch_id?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "warehouses_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "client_branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warehouses_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      work_order_activities: {
        Row: {
          created_at: string
          created_by_user_id: string | null
          description: string
          due_at: string | null
          estimated_hours: number | null
          id: string
          organization_id: string
          sequence: number
          status: string
          updated_at: string
          work_order_id: string
        }
        Insert: {
          created_at?: string
          created_by_user_id?: string | null
          description: string
          due_at?: string | null
          estimated_hours?: number | null
          id?: string
          organization_id: string
          sequence?: number
          status?: string
          updated_at?: string
          work_order_id: string
        }
        Update: {
          created_at?: string
          created_by_user_id?: string | null
          description?: string
          due_at?: string | null
          estimated_hours?: number | null
          id?: string
          organization_id?: string
          sequence?: number
          status?: string
          updated_at?: string
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_order_activities_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_activities_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      work_order_activity_report_evidences: {
        Row: {
          created_at: string
          file_name: string
          file_path: string | null
          file_url: string | null
          id: string
          mime_type: string | null
          notes: string | null
          report_id: string
          size_bytes: number | null
        }
        Insert: {
          created_at?: string
          file_name: string
          file_path?: string | null
          file_url?: string | null
          id?: string
          mime_type?: string | null
          notes?: string | null
          report_id: string
          size_bytes?: number | null
        }
        Update: {
          created_at?: string
          file_name?: string
          file_path?: string | null
          file_url?: string | null
          id?: string
          mime_type?: string | null
          notes?: string | null
          report_id?: string
          size_bytes?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "work_order_activity_report_evidences_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "work_order_activity_reports"
            referencedColumns: ["id"]
          },
        ]
      }
      work_order_activity_report_materials: {
        Row: {
          created_at: string
          id: string
          material_id: string
          notes: string | null
          quantity_used: number
          report_id: string
          unit: string
          work_order_material_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          material_id: string
          notes?: string | null
          quantity_used?: number
          report_id: string
          unit: string
          work_order_material_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          material_id?: string
          notes?: string | null
          quantity_used?: number
          report_id?: string
          unit?: string
          work_order_material_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "work_order_activity_report_material_work_order_material_id_fkey"
            columns: ["work_order_material_id"]
            isOneToOne: false
            referencedRelation: "work_order_materials"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_activity_report_materials_material_id_fkey"
            columns: ["material_id"]
            isOneToOne: false
            referencedRelation: "materials"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_activity_report_materials_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "work_order_activity_reports"
            referencedColumns: ["id"]
          },
        ]
      }
      work_order_activity_reports: {
        Row: {
          activity_id: string
          actual_hours: number
          created_at: string
          final_status: string
          finished_at: string
          id: string
          member_id: string
          observations: string | null
          organization_id: string
          started_at: string
          updated_at: string
          work_order_id: string
        }
        Insert: {
          activity_id: string
          actual_hours?: number
          created_at?: string
          final_status?: string
          finished_at: string
          id?: string
          member_id: string
          observations?: string | null
          organization_id: string
          started_at: string
          updated_at?: string
          work_order_id: string
        }
        Update: {
          activity_id?: string
          actual_hours?: number
          created_at?: string
          final_status?: string
          finished_at?: string
          id?: string
          member_id?: string
          observations?: string | null
          organization_id?: string
          started_at?: string
          updated_at?: string
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_order_activity_reports_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "work_order_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_activity_reports_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_activity_reports_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_activity_reports_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      work_order_activity_technicians: {
        Row: {
          activity_id: string
          created_at: string
          is_primary: boolean
          member_id: string
        }
        Insert: {
          activity_id: string
          created_at?: string
          is_primary?: boolean
          member_id: string
        }
        Update: {
          activity_id?: string
          created_at?: string
          is_primary?: boolean
          member_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_order_activity_technicians_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "work_order_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_activity_technicians_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
        ]
      }
      work_order_materials: {
        Row: {
          created_at: string
          id: string
          material_id: string
          notes: string | null
          organization_id: string
          planned_quantity: number
          stock_snapshot: number
          updated_at: string
          used_quantity: number
          work_order_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          material_id: string
          notes?: string | null
          organization_id: string
          planned_quantity?: number
          stock_snapshot?: number
          updated_at?: string
          used_quantity?: number
          work_order_id: string
        }
        Update: {
          created_at?: string
          id?: string
          material_id?: string
          notes?: string | null
          organization_id?: string
          planned_quantity?: number
          stock_snapshot?: number
          updated_at?: string
          used_quantity?: number
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_order_materials_material_id_fkey"
            columns: ["material_id"]
            isOneToOne: false
            referencedRelation: "materials"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_materials_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_materials_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      work_order_work_logs: {
        Row: {
          created_at: string
          id: string
          member_id: string
          note: string
          organization_id: string
          status_from: string | null
          status_to: string | null
          work_order_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          member_id: string
          note: string
          organization_id: string
          status_from?: string | null
          status_to?: string | null
          work_order_id: string
        }
        Update: {
          created_at?: string
          id?: string
          member_id?: string
          note?: string
          organization_id?: string
          status_from?: string | null
          status_to?: string | null
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_order_work_logs_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_work_logs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_work_logs_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      work_orders: {
        Row: {
          asset_id: string | null
          assigned_member_id: string | null
          cancelled_at: string | null
          client_organization_id: string
          completed_at: string | null
          created_at: string
          created_by_user_id: string | null
          description: string | null
          due_at: string | null
          id: string
          observations: string | null
          planner_member_id: string | null
          priority: string
          provider_organization_id: string
          quote_id: string | null
          request_id: string
          scheduled_at: string | null
          started_at: string | null
          status: string
          title: string | null
          total_amount: number | null
          updated_at: string
          work_order_number: string
          work_order_type: string
        }
        Insert: {
          asset_id?: string | null
          assigned_member_id?: string | null
          cancelled_at?: string | null
          client_organization_id: string
          completed_at?: string | null
          created_at?: string
          created_by_user_id?: string | null
          description?: string | null
          due_at?: string | null
          id?: string
          observations?: string | null
          planner_member_id?: string | null
          priority?: string
          provider_organization_id: string
          quote_id?: string | null
          request_id: string
          scheduled_at?: string | null
          started_at?: string | null
          status?: string
          title?: string | null
          total_amount?: number | null
          updated_at?: string
          work_order_number: string
          work_order_type?: string
        }
        Update: {
          asset_id?: string | null
          assigned_member_id?: string | null
          cancelled_at?: string | null
          client_organization_id?: string
          completed_at?: string | null
          created_at?: string
          created_by_user_id?: string | null
          description?: string | null
          due_at?: string | null
          id?: string
          observations?: string | null
          planner_member_id?: string | null
          priority?: string
          provider_organization_id?: string
          quote_id?: string | null
          request_id?: string
          scheduled_at?: string | null
          started_at?: string | null
          status?: string
          title?: string | null
          total_amount?: number | null
          updated_at?: string
          work_order_number?: string
          work_order_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_orders_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_orders_assigned_member_id_fkey"
            columns: ["assigned_member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_orders_client_organization_id_fkey"
            columns: ["client_organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_orders_planner_member_id_fkey"
            columns: ["planner_member_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_orders_provider_organization_id_fkey"
            columns: ["provider_organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_orders_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: true
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_orders_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_organization_invitation: {
        Args: { p_invitation_id: string }
        Returns: {
          organization_id: string
          status: string
        }[]
      }
      apply_criticality_template: {
        Args: { p_organization_id: string; p_template_id: string }
        Returns: Json
      }
      approve_quote: { Args: { target_quote_id: string }; Returns: undefined }
      assert_valid_criticality_thresholds: {
        Args: {
          p_critical_min: number
          p_high_min: number
          p_medium_min: number
        }
        Returns: undefined
      }
      assign_work_order_technician: {
        Args: { target_member_id: string; target_work_order_id: string }
        Returns: {
          asset_id: string | null
          assigned_member_id: string | null
          cancelled_at: string | null
          client_organization_id: string
          completed_at: string | null
          created_at: string
          created_by_user_id: string | null
          description: string | null
          due_at: string | null
          id: string
          observations: string | null
          planner_member_id: string | null
          priority: string
          provider_organization_id: string
          quote_id: string | null
          request_id: string
          scheduled_at: string | null
          started_at: string | null
          status: string
          title: string | null
          total_amount: number | null
          updated_at: string
          work_order_number: string
          work_order_type: string
        }
        SetofOptions: {
          from: "*"
          to: "work_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      build_preventive_scope_snapshot: {
        Args: { p_plan_id: string }
        Returns: Json
      }
      bulk_calculate_asset_criticality: {
        Args: { p_organization_id: string; p_rows: Json }
        Returns: Json
      }
      calculate_asset_criticality: {
        Args: { p_answers: Json; p_asset_id: string; p_notes?: string }
        Returns: {
          asset_id: string
          calculated_criticality: string
          created_at: string
          created_by_user_id: string | null
          effective_criticality: string
          id: string
          manual_criticality: string | null
          notes: string | null
          organization_id: string
          score: number
          threshold_critical_min: number
          threshold_high_min: number
          threshold_medium_min: number
        }
        SetofOptions: {
          from: "*"
          to: "asset_criticality_assessments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      can_access_criticality_template: {
        Args: { p_template_id: string }
        Returns: boolean
      }
      can_manage_invitation_target: {
        Args: { p_email: string; p_organization_id: string }
        Returns: boolean
      }
      can_manage_maintenance_notice: {
        Args: { p_organization_id: string }
        Returns: boolean
      }
      can_manage_organization_role: {
        Args: {
          p_organization_id: string
          p_role: Database["public"]["Enums"]["organization_member_role"]
        }
        Returns: boolean
      }
      can_manage_preventive_maintenance: {
        Args: { p_organization_id: string }
        Returns: boolean
      }
      can_provider_quote_request: {
        Args: {
          target_provider_organization_id: string
          target_request_id: string
        }
        Returns: boolean
      }
      can_record_asset_meter_reading: {
        Args: { p_organization_id: string }
        Returns: boolean
      }
      can_report_maintenance_notice: {
        Args: { p_organization_id: string }
        Returns: boolean
      }
      can_user_manage_request_access: {
        Args: { _request_id: string }
        Returns: boolean
      }
      can_user_read_quote: {
        Args: { target_quote_id: string }
        Returns: boolean
      }
      can_user_read_request: { Args: { _request_id: string }; Returns: boolean }
      classify_criticality_score: {
        Args: {
          p_critical_min: number
          p_high_min: number
          p_medium_min: number
          p_score: number
        }
        Returns: string
      }
      clear_active_criticality_matrix: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      convert_maintenance_notice: {
        Args: { p_notice_id: string; p_request_id: string }
        Returns: {
          asset_code_snapshot: string | null
          asset_id: string
          asset_name_snapshot: string | null
          asset_path_snapshot: string | null
          branch_id_snapshot: string | null
          branch_name_snapshot: string | null
          converted_at: string | null
          converted_by_user_id: string | null
          converted_request_id: string | null
          created_at: string
          description: string
          dismissal_reason: string | null
          dismissed_at: string | null
          dismissed_by_user_id: string | null
          id: string
          notice_number: string
          organization_id: string
          priority: string
          reported_at: string
          reported_by_user_id: string | null
          responsible_member_id: string | null
          source_id: string | null
          source_metadata: Json
          source_type: string
          status: string
          title: string
          triage_notes: string | null
          triaged_at: string | null
          triaged_by_user_id: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "maintenance_notices"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      correct_asset_meter_reading: {
        Args: {
          p_notes?: string
          p_reading_id: string
          p_reason: string
          p_value: number
        }
        Returns: {
          created_at: string
          created_by_user_id: string | null
          id: string
          meter_id: string
          notes: string | null
          recorded_at: string
          supersedes_reading_id: string | null
          value: number
          void_reason: string | null
          voided_at: string | null
          voided_by_user_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "asset_meter_readings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_asset_meter: {
        Args: {
          p_asset_id: string
          p_initial_value?: number
          p_name: string
          p_notes?: string
          p_organization_id: string
          p_recorded_at?: string
          p_unit: string
        }
        Returns: {
          asset_id: string
          created_at: string
          created_by_user_id: string | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          replaces_meter_id: string | null
          retired_at: string | null
          retirement_reason: string | null
          unit: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "asset_meters"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_inspection_run_from_plan: {
        Args: { p_plan_id: string }
        Returns: {
          area_asset_id: string | null
          asset_id: string | null
          branch_id: string | null
          completed_at: string | null
          created_at: string
          created_by_user_id: string | null
          id: string
          notes: string | null
          organization_id: string
          plan_id: string | null
          responsible_member_id: string | null
          result: string | null
          scheduled_for: string | null
          started_at: string | null
          status: string
          template_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "inspection_runs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_internal_work_order_from_request: {
        Args: { target_assigned_member_id?: string; target_request_id: string }
        Returns: {
          asset_id: string | null
          assigned_member_id: string | null
          cancelled_at: string | null
          client_organization_id: string
          completed_at: string | null
          created_at: string
          created_by_user_id: string | null
          description: string | null
          due_at: string | null
          id: string
          observations: string | null
          planner_member_id: string | null
          priority: string
          provider_organization_id: string
          quote_id: string | null
          request_id: string
          scheduled_at: string | null
          started_at: string | null
          status: string
          title: string | null
          total_amount: number | null
          updated_at: string
          work_order_number: string
          work_order_type: string
        }
        SetofOptions: {
          from: "*"
          to: "work_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_maintenance_notice: {
        Args: {
          p_asset_id: string
          p_description: string
          p_organization_id: string
          p_priority?: string
          p_source_id?: string
          p_source_item_id?: string
          p_source_type?: string
          p_title: string
        }
        Returns: {
          asset_code_snapshot: string | null
          asset_id: string
          asset_name_snapshot: string | null
          asset_path_snapshot: string | null
          branch_id_snapshot: string | null
          branch_name_snapshot: string | null
          converted_at: string | null
          converted_by_user_id: string | null
          converted_request_id: string | null
          created_at: string
          description: string
          dismissal_reason: string | null
          dismissed_at: string | null
          dismissed_by_user_id: string | null
          id: string
          notice_number: string
          organization_id: string
          priority: string
          reported_at: string
          reported_by_user_id: string | null
          responsible_member_id: string | null
          source_id: string | null
          source_metadata: Json
          source_type: string
          status: string
          title: string
          triage_notes: string | null
          triaged_at: string | null
          triaged_by_user_id: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "maintenance_notices"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_notification_once: {
        Args: {
          p_actor_user_id: string
          p_entity_id: string
          p_entity_type: string
          p_message: string
          p_metadata?: Json
          p_organization_id: string
          p_priority?: string
          p_recipient_member_id: string
          p_title: string
          p_type: string
        }
        Returns: string
      }
      create_organization_invitation: {
        Args: {
          p_email: string
          p_invited_name?: string
          p_organization_id: string
          p_role: Database["public"]["Enums"]["organization_member_role"]
        }
        Returns: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string
          invited_name: string | null
          last_send_attempt_at: string | null
          last_sent_at: string | null
          organization_id: string
          revoked_at: string | null
          revoked_by: string | null
          role: Database["public"]["Enums"]["organization_member_role"]
          send_count: number
          status: Database["public"]["Enums"]["organization_invitation_status"]
          token_hash: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "organization_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_organization_notification: {
        Args: {
          target_actor_user_id: string
          target_entity_id: string
          target_entity_type: string
          target_message: string
          target_organization_id: string
          target_quote_id: string
          target_request_id: string
          target_title: string
          target_type: string
        }
        Returns: string
      }
      create_preventive_occurrence_locked: {
        Args: { p_due_at: string; p_due_meter_value: number; p_plan_id: string }
        Returns: {
          asset_id: string
          cancel_reason: string | null
          cancelled_at: string | null
          completed_at: string | null
          completion_meter_reading_id: string | null
          completion_meter_value: number | null
          created_at: string
          due_at: string | null
          due_meter_value: number | null
          id: string
          organization_id: string
          plan_id: string
          planned_at: string | null
          request_creation_id: string
          request_id: string | null
          scope_snapshot: Json
          sequence: number
          skip_reason: string | null
          skipped_at: string | null
          status: string
          updated_at: string
          work_order_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "preventive_maintenance_occurrences"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_template_from_current_matrix: {
        Args: {
          p_category?: string
          p_description?: string
          p_name: string
          p_organization_id: string
        }
        Returns: {
          category: string | null
          created_at: string
          created_by_user_id: string | null
          critical_min: number | null
          description: string | null
          high_min: number | null
          id: string
          is_active: boolean
          medium_min: number | null
          name: string
          organization_id: string | null
          scope: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "criticality_matrix_templates"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_work_order_from_quote: {
        Args: { target_quote_id: string }
        Returns: {
          asset_id: string | null
          assigned_member_id: string | null
          cancelled_at: string | null
          client_organization_id: string
          completed_at: string | null
          created_at: string
          created_by_user_id: string | null
          description: string | null
          due_at: string | null
          id: string
          observations: string | null
          planner_member_id: string | null
          priority: string
          provider_organization_id: string
          quote_id: string | null
          request_id: string
          scheduled_at: string | null
          started_at: string | null
          status: string
          title: string | null
          total_amount: number | null
          updated_at: string
          work_order_number: string
          work_order_type: string
        }
        SetofOptions: {
          from: "*"
          to: "work_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      criticality_active_score_range: {
        Args: { p_organization_id: string }
        Returns: {
          max_possible_score: number
          min_possible_score: number
          parameter_count: number
        }[]
      }
      criticality_default_thresholds: {
        Args: never
        Returns: {
          critical_min: number
          high_min: number
          medium_min: number
        }[]
      }
      criticality_label_es: { Args: { p_criticality: string }; Returns: string }
      criticality_slugify: { Args: { p_text: string }; Returns: string }
      criticality_thresholds_from_jsonb: {
        Args: { p_thresholds: Json }
        Returns: {
          critical_min: number
          high_min: number
          medium_min: number
        }[]
      }
      criticality_thresholds_payload: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      criticality_unreachable_categories: {
        Args: {
          p_critical_min: number
          p_high_min: number
          p_max_score: number
          p_medium_min: number
          p_min_score: number
        }
        Returns: string[]
      }
      dblink: { Args: { "": string }; Returns: Record<string, unknown>[] }
      dblink_cancel_query: { Args: { "": string }; Returns: string }
      dblink_close: { Args: { "": string }; Returns: string }
      dblink_connect: { Args: { "": string }; Returns: string }
      dblink_connect_u: { Args: { "": string }; Returns: string }
      dblink_current_query: { Args: never; Returns: string }
      dblink_disconnect:
        | { Args: never; Returns: string }
        | { Args: { "": string }; Returns: string }
      dblink_error_message: { Args: { "": string }; Returns: string }
      dblink_exec: { Args: { "": string }; Returns: string }
      dblink_fdw_validator: {
        Args: { catalog: unknown; options: string[] }
        Returns: undefined
      }
      dblink_get_connections: { Args: never; Returns: string[] }
      dblink_get_notify:
        | { Args: { conname: string }; Returns: Record<string, unknown>[] }
        | { Args: never; Returns: Record<string, unknown>[] }
      dblink_get_pkey: {
        Args: { "": string }
        Returns: Database["public"]["CompositeTypes"]["dblink_pkey_results"][]
        SetofOptions: {
          from: "*"
          to: "dblink_pkey_results"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      dblink_get_result: {
        Args: { "": string }
        Returns: Record<string, unknown>[]
      }
      dblink_is_busy: { Args: { "": string }; Returns: number }
      delete_work_order_activity: {
        Args: { p_activity_id: string }
        Returns: undefined
      }
      delete_work_order_material: {
        Args: { p_work_order_material_id: string }
        Returns: undefined
      }
      dismiss_maintenance_notice: {
        Args: { p_notice_id: string; p_reason: string }
        Returns: {
          asset_code_snapshot: string | null
          asset_id: string
          asset_name_snapshot: string | null
          asset_path_snapshot: string | null
          branch_id_snapshot: string | null
          branch_name_snapshot: string | null
          converted_at: string | null
          converted_by_user_id: string | null
          converted_request_id: string | null
          created_at: string
          description: string
          dismissal_reason: string | null
          dismissed_at: string | null
          dismissed_by_user_id: string | null
          id: string
          notice_number: string
          organization_id: string
          priority: string
          reported_at: string
          reported_by_user_id: string | null
          responsible_member_id: string | null
          source_id: string | null
          source_metadata: Json
          source_type: string
          status: string
          title: string
          triage_notes: string | null
          triaged_at: string | null
          triaged_by_user_id: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "maintenance_notices"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      generate_inspection_due_notifications: { Args: never; Returns: undefined }
      generate_operational_due_notifications: {
        Args: never
        Returns: undefined
      }
      get_activity_report_form_data: {
        Args: { p_activity_id: string }
        Returns: Json
      }
      get_activity_reports_for_work_order: {
        Args: { p_work_order_id: string }
        Returns: {
          activity_description: string
          activity_id: string
          actual_hours: number
          created_at: string
          estimated_hours: number
          evidences: Json
          final_status: string
          finished_at: string
          hours_difference: number
          id: string
          materials: Json
          member_id: string
          observations: string
          started_at: string
          technician_email: string
          technician_name: string
        }[]
      }
      get_asset_criticality_assessments: {
        Args: { p_asset_id: string }
        Returns: {
          answers: Json
          asset_id: string
          calculated_criticality: string
          created_at: string
          created_by_name: string
          created_by_user_id: string
          effective_criticality: string
          id: string
          manual_criticality: string
          notes: string
          organization_id: string
          score: number
          threshold_critical_min: number
          threshold_high_min: number
          threshold_medium_min: number
        }[]
      }
      get_asset_integrated_history: {
        Args: { p_asset_id: string }
        Returns: {
          actor_email: string
          actor_name: string
          description: string
          event_date: string
          event_label: string
          event_type: string
          id: string
          metadata: Json
          source_id: string
          source_table: string
          status: string
          title: string
        }[]
      }
      get_asset_integrated_history_before_preventive: {
        Args: { p_asset_id: string }
        Returns: {
          actor_email: string
          actor_name: string
          description: string
          event_date: string
          event_label: string
          event_type: string
          id: string
          metadata: Json
          source_id: string
          source_table: string
          status: string
          title: string
        }[]
      }
      get_asset_meters: {
        Args: { p_asset_id: string; p_include_inactive?: boolean }
        Returns: Json
      }
      get_asset_traffic_light: {
        Args: { p_organization_id: string }
        Returns: {
          asset_code: string
          asset_id: string
          asset_name: string
          branch_id: string
          causing_asset_ids: string[]
          criticality: string
          direct_color: string
          direct_reasons: Json
          direct_severity: number
          node_type: string
          organization_id: string
          parent_asset_id: string
          rollup_color: string
          rollup_reasons: Json
          rollup_severity: number
          status: string
          updated_at: string
        }[]
      }
      get_assignable_planners: {
        Args: { p_organization_id: string }
        Returns: {
          email: string
          member_id: string
          name: string
          user_id: string
        }[]
      }
      get_assignable_technicians: {
        Args: { p_organization_id: string }
        Returns: {
          email: string
          member_id: string
          name: string
          user_id: string
        }[]
      }
      get_auth_user_state_by_email: {
        Args: { p_email: string }
        Returns: {
          email_confirmed: boolean
          exists_flag: boolean
          user_id: string
        }[]
      }
      get_branch_traffic_light: {
        Args: { p_organization_id: string }
        Returns: {
          branch_id: string
          branch_name: string
          causing_asset_ids: string[]
          rollup_color: string
          rollup_reasons: Json
          rollup_severity: number
        }[]
      }
      get_checklist_templates: {
        Args: { p_include_inactive?: boolean; p_organization_id: string }
        Returns: Json
      }
      get_coordination_contacts: {
        Args: { p_organization_id: string }
        Returns: {
          email: string
          member_id: string
          name: string
          user_id: string
        }[]
      }
      get_criticality_matrix: {
        Args: { p_include_inactive?: boolean; p_organization_id: string }
        Returns: Json
      }
      get_criticality_template: {
        Args: { p_template_id: string }
        Returns: Json
      }
      get_criticality_templates: {
        Args: { p_organization_id: string }
        Returns: {
          category: string
          created_at: string
          description: string
          id: string
          is_active: boolean
          name: string
          option_count: number
          organization_id: string
          parameter_count: number
          scope: string
          total_weight: number
        }[]
      }
      get_criticality_thresholds: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_dashboard_metrics: {
        Args: { p_organization_id: string }
        Returns: {
          actual_hours: number
          critical_assets: number
          open_requests: number
          open_work_orders: number
          overdue_inspections: number
          overdue_work_orders: number
          planned_hours: number
          total_assets: number
          upcoming_inspections: number
          updated_at: string
        }[]
      }
      get_effective_criticality_thresholds: {
        Args: { p_organization_id: string }
        Returns: {
          critical_min: number
          high_min: number
          is_default: boolean
          medium_min: number
        }[]
      }
      get_efficiency_activity_metrics: {
        Args: {
          p_end_date?: string
          p_organization_id: string
          p_start_date?: string
        }
        Returns: {
          activity_description: string
          activity_id: string
          activity_status: string
          actual_hours: number
          asset_id: string
          asset_name: string
          deviation_hours: number
          deviation_percent: number
          first_started_at: string
          last_finished_at: string
          period_date: string
          planned_hours: number
          reports_count: number
          technician_member_id: string
          technician_name: string
          work_order_id: string
          work_order_number: string
          work_order_status: string
        }[]
      }
      get_efficiency_summary: {
        Args: {
          p_end_date?: string
          p_organization_id: string
          p_start_date?: string
        }
        Returns: {
          activities_count: number
          actual_hours_total: number
          completed_work_orders: number
          deviation_hours_total: number
          deviation_percent_total: number
          overdue_work_orders: number
          pending_work_orders: number
          planned_hours_total: number
          reported_activities_count: number
        }[]
      }
      get_inspection_plan_alert_rules: {
        Args: { p_plan_id: string }
        Returns: {
          alert_type: string
          days_before: number
          id: string
          is_active: boolean
          label: string
          plan_id: string
        }[]
      }
      get_inspection_plans: {
        Args: { p_include_inactive?: boolean; p_organization_id: string }
        Returns: {
          alert_rules: Json
          area_asset_id: string
          area_asset_name: string
          asset_id: string
          asset_name: string
          branch_id: string
          branch_name: string
          created_at: string
          custom_interval: number
          custom_unit: string
          description: string
          frequency: string
          id: string
          is_active: boolean
          next_due_at: string
          responsible_member_id: string
          responsible_name: string
          start_date: string
          template_id: string
          template_name: string
          title: string
        }[]
      }
      get_inspection_run_detail: { Args: { p_run_id: string }; Returns: Json }
      get_inspection_runs: {
        Args: { p_organization_id: string; p_status?: string }
        Returns: {
          area_asset_name: string
          asset_name: string
          branch_name: string
          completed_at: string
          id: string
          organization_id: string
          plan_id: string
          responsible_member_id: string
          responsible_name: string
          result: string
          scheduled_for: string
          started_at: string
          status: string
          template_id: string
          template_name: string
        }[]
      }
      get_inventory_catalog: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_maintenance_cards: {
        Args: { p_include_inactive?: boolean; p_organization_id: string }
        Returns: Json
      }
      get_maintenance_notices: {
        Args: { p_organization_id: string }
        Returns: {
          asset_code_snapshot: string
          asset_current_criticality: string
          asset_id: string
          asset_name_snapshot: string
          asset_path_snapshot: string
          branch_id_snapshot: string
          branch_name_snapshot: string
          converted_at: string
          converted_by_name: string
          converted_request_id: string
          converted_request_number: string
          created_at: string
          description: string
          dismissal_reason: string
          dismissed_at: string
          dismissed_by_name: string
          id: string
          notice_number: string
          organization_id: string
          priority: string
          reported_at: string
          reported_by_name: string
          reported_by_user_id: string
          responsible_member_id: string
          responsible_name: string
          source_id: string
          source_metadata: Json
          source_type: string
          status: string
          title: string
          triage_notes: string
          triaged_at: string
          triaged_by_name: string
        }[]
      }
      get_my_organization_invitation: {
        Args: { p_invitation_id: string }
        Returns: {
          effective_status: string
          expires_at: string
          invitation_id: string
          invited_name: string
          organization_id: string
          organization_name: string
          role: Database["public"]["Enums"]["organization_member_role"]
        }[]
      }
      get_my_pending_invitations: {
        Args: never
        Returns: {
          expires_at: string
          invitation_id: string
          invited_name: string
          organization_id: string
          organization_name: string
          role: Database["public"]["Enums"]["organization_member_role"]
        }[]
      }
      get_my_technician_work_orders: {
        Args: never
        Returns: {
          activities: Json
          asset_id: string
          asset_name: string
          asset_path: string
          due_at: string
          id: string
          location: string
          materials: Json
          organization_id: string
          priority: string
          request_id: string
          scheduled_at: string
          status: string
          title: string
          work_order_number: string
          work_order_type: string
        }[]
      }
      get_preventive_maintenance_occurrences: {
        Args: {
          p_asset_id?: string
          p_organization_id: string
          p_status?: string
        }
        Returns: Json
      }
      get_preventive_maintenance_plans: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_provider_relationship_directory: {
        Args: { p_client_organization_id: string }
        Returns: {
          organization_id: string
          organization_name: string
          organization_type: Database["public"]["Enums"]["organization_type"]
          relationship_id: string
          relationship_status: Database["public"]["Enums"]["organization_relationship_status"]
          relationship_type: Database["public"]["Enums"]["organization_relationship_type"]
          specialties: string[]
        }[]
      }
      get_user_organizations: {
        Args: never
        Returns: {
          created_at: string
          created_by: string | null
          id: string
          legal_name: string | null
          name: string
          organization_type: Database["public"]["Enums"]["organization_type"]
          settings: Json
          status: string
          tax_id: string | null
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "organizations"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      get_work_order_activities: {
        Args: { p_work_order_id: string }
        Returns: {
          created_at: string
          description: string
          due_at: string
          estimated_hours: number
          id: string
          sequence: number
          status: string
          technicians: Json
          updated_at: string
          work_order_id: string
        }[]
      }
      get_work_order_materials: {
        Args: { p_work_order_id: string }
        Returns: {
          created_at: string
          current_stock: number
          id: string
          material_code: string
          material_id: string
          material_name: string
          material_unit: string
          notes: string
          planned_quantity: number
          stock_snapshot: number
          updated_at: string
          used_quantity: number
          warehouse_id: string
          warehouse_name: string
          warning_status: string
        }[]
      }
      get_work_order_work_logs: {
        Args: { p_work_order_id: string }
        Returns: {
          created_at: string
          id: string
          member_email: string
          member_name: string
          note: string
          status_from: string
          status_to: string
        }[]
      }
      has_organization_role: {
        Args: {
          _organization_id: string
          _roles: Database["public"]["Enums"]["organization_member_role"][]
        }
        Returns: boolean
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_eligible_follow_up_responsible: {
        Args: { p_member_id: string; p_organization_id: string }
        Returns: boolean
      }
      is_organization_member: {
        Args: { _organization_id: string }
        Returns: boolean
      }
      is_platform_admin: { Args: never; Returns: boolean }
      is_provider_facing_organization: {
        Args: { _organization_id: string }
        Returns: boolean
      }
      list_organization_access: {
        Args: { p_organization_id: string }
        Returns: {
          accepted_at: string
          created_at: string
          effective_status: string
          email: string
          expires_at: string
          id: string
          invited_name: string
          is_active: boolean
          joined_at: string
          kind: string
          last_sent_at: string
          name: string
          revoked_at: string
          role: Database["public"]["Enums"]["organization_member_role"]
          send_count: number
          user_id: string
        }[]
      }
      map_request_priority_to_work_order_priority: {
        Args: { request_priority: number }
        Returns: string
      }
      mark_invitation_sent: {
        Args: { p_invitation_id: string }
        Returns: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string
          invited_name: string | null
          last_send_attempt_at: string | null
          last_sent_at: string | null
          organization_id: string
          revoked_at: string | null
          revoked_by: string | null
          role: Database["public"]["Enums"]["organization_member_role"]
          send_count: number
          status: Database["public"]["Enums"]["organization_invitation_status"]
          token_hash: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "organization_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      member_display_name: { Args: { p_member_id: string }; Returns: string }
      next_maintenance_notice_number: {
        Args: { p_organization_id: string }
        Returns: string
      }
      notify_member: {
        Args: {
          p_actor_user_id: string
          p_entity_id: string
          p_entity_type: string
          p_member_id: string
          p_message: string
          p_metadata?: Json
          p_priority?: string
          p_title: string
          p_type: string
        }
        Returns: undefined
      }
      notify_preventive_occurrence: {
        Args: {
          p_event_type: string
          p_message: string
          p_occurrence_id: string
          p_title: string
        }
        Returns: undefined
      }
      notify_role_members: {
        Args: {
          p_actor_user_id: string
          p_entity_id: string
          p_entity_type: string
          p_message: string
          p_metadata?: Json
          p_organization_id: string
          p_priority?: string
          p_roles: Database["public"]["Enums"]["organization_member_role"][]
          p_title: string
          p_type: string
        }
        Returns: undefined
      }
      plan_preventive_maintenance_occurrence: {
        Args: { p_occurrence_id: string; p_request_id: string }
        Returns: {
          asset_id: string
          cancel_reason: string | null
          cancelled_at: string | null
          completed_at: string | null
          completion_meter_reading_id: string | null
          completion_meter_value: number | null
          created_at: string
          due_at: string | null
          due_meter_value: number | null
          id: string
          organization_id: string
          plan_id: string
          planned_at: string | null
          request_creation_id: string
          request_id: string | null
          scope_snapshot: Json
          sequence: number
          skip_reason: string | null
          skipped_at: string | null
          status: string
          updated_at: string
          work_order_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "preventive_maintenance_occurrences"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      preventive_frequency_interval: {
        Args: {
          p_custom_interval?: number
          p_custom_unit?: string
          p_frequency: string
        }
        Returns: string
      }
      preview_bulk_asset_criticality: {
        Args: { p_organization_id: string; p_rows: Json }
        Returns: {
          asset_code: string
          asset_id: string
          asset_name: string
          calculated_criticality: string
          errors: Json
          row_number: number
          score: number
          valid: boolean
          warnings: Json
        }[]
      }
      record_asset_meter_reading: {
        Args: {
          p_meter_id: string
          p_notes?: string
          p_recorded_at?: string
          p_value: number
        }
        Returns: {
          created_at: string
          created_by_user_id: string | null
          id: string
          meter_id: string
          notes: string | null
          recorded_at: string
          supersedes_reading_id: string | null
          value: number
          void_reason: string | null
          voided_at: string | null
          voided_by_user_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "asset_meter_readings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      reject_quote: {
        Args: { reason?: string; target_quote_id: string }
        Returns: undefined
      }
      replace_asset_meter: {
        Args: {
          p_initial_value: number
          p_meter_id: string
          p_name: string
          p_notes?: string
          p_reason: string
          p_recorded_at: string
          p_unit: string
        }
        Returns: {
          asset_id: string
          created_at: string
          created_by_user_id: string | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          replaces_meter_id: string | null
          retired_at: string | null
          retirement_reason: string | null
          unit: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "asset_meters"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      replace_criticality_configuration: {
        Args: { p_matrix: Json; p_organization_id: string; p_thresholds?: Json }
        Returns: Json
      }
      replace_criticality_matrix: {
        Args: { p_matrix: Json; p_organization_id: string }
        Returns: Json
      }
      replace_inspection_plan_alert_rules: {
        Args: { p_plan_id: string; p_rules: Json }
        Returns: {
          alert_type: string
          created_at: string
          days_before: number | null
          id: string
          is_active: boolean
          label: string | null
          organization_id: string
          plan_id: string
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "inspection_plan_alert_rules"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      resend_organization_invitation: {
        Args: { p_invitation_id: string }
        Returns: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string
          invited_name: string | null
          last_send_attempt_at: string | null
          last_sent_at: string | null
          organization_id: string
          revoked_at: string | null
          revoked_by: string | null
          role: Database["public"]["Enums"]["organization_member_role"]
          send_count: number
          status: Database["public"]["Enums"]["organization_invitation_status"]
          token_hash: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "organization_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      resolve_asset_branch: { Args: { p_asset_id: string }; Returns: string }
      resolve_asset_path: { Args: { p_asset_id: string }; Returns: string }
      resolve_caller_planner_member: {
        Args: { p_organization_id: string }
        Returns: string
      }
      retire_asset_meter: {
        Args: { p_meter_id: string; p_reason: string }
        Returns: {
          asset_id: string
          created_at: string
          created_by_user_id: string | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          replaces_meter_id: string | null
          retired_at: string | null
          retirement_reason: string | null
          unit: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "asset_meters"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      revoke_organization_invitation: {
        Args: { p_invitation_id: string }
        Returns: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string
          invited_name: string | null
          last_send_attempt_at: string | null
          last_sent_at: string | null
          organization_id: string
          revoked_at: string | null
          revoked_by: string | null
          role: Database["public"]["Enums"]["organization_member_role"]
          send_count: number
          status: Database["public"]["Enums"]["organization_invitation_status"]
          token_hash: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "organization_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      save_maintenance_card: {
        Args: {
          p_card_id?: string
          p_category?: string
          p_code: string
          p_description?: string
          p_estimated_hours?: number
          p_materials?: Json
          p_name: string
          p_organization_id: string
          p_procedure_notes?: string
          p_safety_notes?: string
          p_tasks?: Json
        }
        Returns: {
          category: string | null
          code: string
          created_at: string
          created_by_user_id: string | null
          description: string | null
          estimated_hours: number | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          procedure_notes: string | null
          safety_notes: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "maintenance_cards"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      save_preventive_maintenance_plan: {
        Args: {
          p_asset_id: string
          p_baseline_reading_id?: string
          p_card_id: string
          p_custom_interval?: number
          p_custom_unit?: string
          p_default_request_type?: string
          p_first_due_at?: string
          p_frequency?: string
          p_interval_value?: number
          p_meter_id?: string
          p_meter_lead_value?: number
          p_organization_id: string
          p_plan_id?: string
          p_planning_lead_days?: number
          p_priority?: string
          p_responsible_member_id?: string
          p_trigger_type: string
        }
        Returns: {
          asset_id: string
          baseline_reading_id: string | null
          baseline_value: number | null
          card_id: string
          created_at: string
          created_by_user_id: string | null
          custom_interval: number | null
          custom_unit: string | null
          default_request_type: string
          first_due_at: string | null
          frequency: string | null
          id: string
          interval_value: number | null
          is_active: boolean
          meter_id: string | null
          meter_lead_value: number | null
          organization_id: string
          planning_lead_days: number
          priority: string
          responsible_member_id: string | null
          trigger_type: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "preventive_maintenance_plans"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_checklist_response_option_active: {
        Args: { p_is_active: boolean; p_option_id: string }
        Returns: {
          created_at: string
          id: string
          is_active: boolean
          is_failure: boolean
          label: string
          score: number | null
          sequence: number
          template_id: string
          value: string
        }
        SetofOptions: {
          from: "*"
          to: "checklist_template_response_options"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_checklist_template_item_active: {
        Args: { p_is_active: boolean; p_item_id: string }
        Returns: {
          created_at: string
          help_text: string | null
          id: string
          is_active: boolean
          is_required: boolean
          question: string
          section: string | null
          sequence: number
          template_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "checklist_template_items"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_criticality_option_active: {
        Args: { p_is_active: boolean; p_option_id: string }
        Returns: {
          code: string
          created_at: string
          id: string
          is_active: boolean
          label: string
          parameter_id: string
          score: number
          sequence: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "criticality_parameter_options"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_criticality_parameter_active: {
        Args: { p_is_active: boolean; p_parameter_id: string }
        Returns: {
          code: string
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          sequence: number
          updated_at: string
          weight: number
        }
        SetofOptions: {
          from: "*"
          to: "criticality_parameters"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_criticality_thresholds: {
        Args: {
          p_critical_min: number
          p_high_min: number
          p_medium_min: number
          p_organization_id: string
        }
        Returns: Json
      }
      set_inspection_plan_alert_rule_active: {
        Args: { p_is_active: boolean; p_rule_id: string }
        Returns: {
          alert_type: string
          created_at: string
          days_before: number | null
          id: string
          is_active: boolean
          label: string | null
          organization_id: string
          plan_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "inspection_plan_alert_rules"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_maintenance_card_active: {
        Args: { p_card_id: string; p_is_active: boolean }
        Returns: {
          category: string | null
          code: string
          created_at: string
          created_by_user_id: string | null
          description: string | null
          estimated_hours: number | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          procedure_notes: string | null
          safety_notes: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "maintenance_cards"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_preventive_maintenance_plan_active: {
        Args: { p_is_active: boolean; p_plan_id: string; p_reason?: string }
        Returns: {
          asset_id: string
          baseline_reading_id: string | null
          baseline_value: number | null
          card_id: string
          created_at: string
          created_by_user_id: string | null
          custom_interval: number | null
          custom_unit: string | null
          default_request_type: string
          first_due_at: string | null
          frequency: string | null
          id: string
          interval_value: number | null
          is_active: boolean
          meter_id: string | null
          meter_lead_value: number | null
          organization_id: string
          planning_lead_days: number
          priority: string
          responsible_member_id: string | null
          trigger_type: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "preventive_maintenance_plans"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_provider_relationship_status: {
        Args: {
          p_client_organization_id: string
          p_status: Database["public"]["Enums"]["organization_relationship_status"]
          p_target_organization_id: string
        }
        Returns: {
          created_at: string
          created_by: string | null
          id: string
          relationship_type: Database["public"]["Enums"]["organization_relationship_type"]
          source_organization_id: string
          status: Database["public"]["Enums"]["organization_relationship_status"]
          target_organization_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "organization_relationships"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_request_audience: {
        Args: {
          p_is_public: boolean
          p_provider_organization_ids?: string[]
          p_request_id: string
        }
        Returns: {
          is_public: boolean
          provider_organization_ids: string[]
        }[]
      }
      skip_preventive_maintenance_occurrence: {
        Args: { p_occurrence_id: string; p_reason: string }
        Returns: {
          asset_id: string
          cancel_reason: string | null
          cancelled_at: string | null
          completed_at: string | null
          completion_meter_reading_id: string | null
          completion_meter_value: number | null
          created_at: string
          due_at: string | null
          due_meter_value: number | null
          id: string
          organization_id: string
          plan_id: string
          planned_at: string | null
          request_creation_id: string
          request_id: string | null
          scope_snapshot: Json
          sequence: number
          skip_reason: string | null
          skipped_at: string | null
          status: string
          updated_at: string
          work_order_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "preventive_maintenance_occurrences"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      storage_request_id_from_name: {
        Args: { object_name: string }
        Returns: string
      }
      submit_activity_report: {
        Args: {
          p_activity_id: string
          p_evidences?: Json
          p_final_status?: string
          p_finished_at: string
          p_materials?: Json
          p_observations?: string
          p_started_at: string
        }
        Returns: {
          activity_id: string
          actual_hours: number
          created_at: string
          final_status: string
          finished_at: string
          id: string
          member_id: string
          observations: string | null
          organization_id: string
          started_at: string
          updated_at: string
          work_order_id: string
        }
        SetofOptions: {
          from: "*"
          to: "work_order_activity_reports"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      submit_inspection_run: {
        Args: {
          p_answers: Json
          p_completed_at: string
          p_evidences?: Json
          p_notes?: string
          p_run_id: string
          p_started_at: string
        }
        Returns: {
          area_asset_id: string | null
          asset_id: string | null
          branch_id: string | null
          completed_at: string | null
          created_at: string
          created_by_user_id: string | null
          id: string
          notes: string | null
          organization_id: string
          plan_id: string | null
          responsible_member_id: string | null
          result: string | null
          scheduled_for: string | null
          started_at: string | null
          status: string
          template_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "inspection_runs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      technician_update_work_order_progress: {
        Args: { p_notes?: string; p_status?: string; p_work_order_id: string }
        Returns: {
          asset_id: string | null
          assigned_member_id: string | null
          cancelled_at: string | null
          client_organization_id: string
          completed_at: string | null
          created_at: string
          created_by_user_id: string | null
          description: string | null
          due_at: string | null
          id: string
          observations: string | null
          planner_member_id: string | null
          priority: string
          provider_organization_id: string
          quote_id: string | null
          request_id: string
          scheduled_at: string | null
          started_at: string | null
          status: string
          title: string | null
          total_amount: number | null
          updated_at: string
          work_order_number: string
          work_order_type: string
        }
        SetofOptions: {
          from: "*"
          to: "work_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      triage_maintenance_notice: {
        Args: {
          p_clear_responsible?: boolean
          p_notice_id: string
          p_priority?: string
          p_responsible_member_id?: string
          p_triage_notes?: string
        }
        Returns: {
          asset_code_snapshot: string | null
          asset_id: string
          asset_name_snapshot: string | null
          asset_path_snapshot: string | null
          branch_id_snapshot: string | null
          branch_name_snapshot: string | null
          converted_at: string | null
          converted_by_user_id: string | null
          converted_request_id: string | null
          created_at: string
          description: string
          dismissal_reason: string | null
          dismissed_at: string | null
          dismissed_by_user_id: string | null
          id: string
          notice_number: string
          organization_id: string
          priority: string
          reported_at: string
          reported_by_user_id: string | null
          responsible_member_id: string | null
          source_id: string | null
          source_metadata: Json
          source_type: string
          status: string
          title: string
          triage_notes: string | null
          triaged_at: string | null
          triaged_by_user_id: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "maintenance_notices"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_organization_member: {
        Args: {
          p_is_active?: boolean
          p_membership_id: string
          p_role?: Database["public"]["Enums"]["organization_member_role"]
        }
        Returns: {
          id: string
          invited_by: string | null
          is_active: boolean
          joined_at: string
          organization_id: string
          role: Database["public"]["Enums"]["organization_member_role"]
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "organization_members"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_work_order_operations: {
        Args: {
          target_assigned_member_id: string
          target_due_at: string
          target_observations: string
          target_planner_member_id: string
          target_priority: string
          target_scheduled_at: string
          target_status: string
          target_work_order_id: string
        }
        Returns: {
          asset_id: string | null
          assigned_member_id: string | null
          cancelled_at: string | null
          client_organization_id: string
          completed_at: string | null
          created_at: string
          created_by_user_id: string | null
          description: string | null
          due_at: string | null
          id: string
          observations: string | null
          planner_member_id: string | null
          priority: string
          provider_organization_id: string
          quote_id: string | null
          request_id: string
          scheduled_at: string | null
          started_at: string | null
          status: string
          title: string | null
          total_amount: number | null
          updated_at: string
          work_order_number: string
          work_order_type: string
        }
        SetofOptions: {
          from: "*"
          to: "work_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_checklist_response_option: {
        Args: {
          p_is_active?: boolean
          p_is_failure?: boolean
          p_label: string
          p_option_id?: string
          p_score?: number
          p_sequence?: number
          p_template_id: string
          p_value: string
        }
        Returns: {
          created_at: string
          id: string
          is_active: boolean
          is_failure: boolean
          label: string
          score: number | null
          sequence: number
          template_id: string
          value: string
        }
        SetofOptions: {
          from: "*"
          to: "checklist_template_response_options"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_checklist_template: {
        Args: {
          p_category?: string
          p_description?: string
          p_is_active?: boolean
          p_name: string
          p_organization_id: string
          p_template_id?: string
        }
        Returns: {
          category: string | null
          created_at: string
          created_by_user_id: string | null
          description: string | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "checklist_templates"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_checklist_template_item: {
        Args: {
          p_help_text?: string
          p_is_active?: boolean
          p_is_required?: boolean
          p_item_id?: string
          p_question: string
          p_section?: string
          p_sequence?: number
          p_template_id: string
        }
        Returns: {
          created_at: string
          help_text: string | null
          id: string
          is_active: boolean
          is_required: boolean
          question: string
          section: string | null
          sequence: number
          template_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "checklist_template_items"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_criticality_option: {
        Args: {
          p_is_active?: boolean
          p_label: string
          p_option_id?: string
          p_parameter_id: string
          p_score?: number
          p_sequence?: number
        }
        Returns: {
          code: string
          created_at: string
          id: string
          is_active: boolean
          label: string
          parameter_id: string
          score: number
          sequence: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "criticality_parameter_options"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_criticality_parameter: {
        Args: {
          p_description?: string
          p_is_active?: boolean
          p_name: string
          p_organization_id: string
          p_parameter_id?: string
          p_sequence?: number
          p_weight?: number
        }
        Returns: {
          code: string
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          sequence: number
          updated_at: string
          weight: number
        }
        SetofOptions: {
          from: "*"
          to: "criticality_parameters"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_inspection_plan: {
        Args: {
          p_area_asset_id?: string
          p_asset_id?: string
          p_branch_id?: string
          p_custom_interval?: number
          p_custom_unit?: string
          p_description?: string
          p_frequency?: string
          p_is_active?: boolean
          p_next_due_at?: string
          p_organization_id: string
          p_plan_id?: string
          p_responsible_member_id?: string
          p_start_date?: string
          p_template_id: string
          p_title: string
        }
        Returns: {
          area_asset_id: string | null
          asset_id: string | null
          branch_id: string | null
          created_at: string
          created_by_user_id: string | null
          custom_interval: number | null
          custom_unit: string | null
          description: string | null
          frequency: string
          id: string
          is_active: boolean
          next_due_at: string | null
          organization_id: string
          responsible_member_id: string | null
          start_date: string
          template_id: string
          title: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "inspection_plans"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_inspection_plan_alert_rule: {
        Args: {
          p_alert_type: string
          p_days_before?: number
          p_is_active?: boolean
          p_label?: string
          p_plan_id: string
          p_rule_id?: string
        }
        Returns: {
          alert_type: string
          created_at: string
          days_before: number | null
          id: string
          is_active: boolean
          label: string | null
          organization_id: string
          plan_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "inspection_plan_alert_rules"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_material: {
        Args: {
          p_code: string
          p_is_active?: boolean
          p_material_id?: string
          p_name: string
          p_organization_id: string
          p_stock?: number
          p_unit: string
          p_warehouse_id: string
        }
        Returns: {
          code: string
          created_at: string
          id: string
          is_active: boolean
          name: string
          organization_id: string
          stock: number
          unit: string
          updated_at: string
          warehouse_id: string
        }
        SetofOptions: {
          from: "*"
          to: "materials"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_warehouse: {
        Args: {
          p_branch_id?: string
          p_is_active?: boolean
          p_name: string
          p_organization_id: string
          p_warehouse_id?: string
        }
        Returns: {
          branch_id: string | null
          created_at: string
          id: string
          is_active: boolean
          name: string
          organization_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "warehouses"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_work_order_activity: {
        Args: {
          p_activity_id?: string
          p_description: string
          p_due_at?: string
          p_estimated_hours?: number
          p_sequence?: number
          p_status?: string
          p_technician_member_ids?: string[]
          p_work_order_id: string
        }
        Returns: {
          created_at: string
          created_by_user_id: string | null
          description: string
          due_at: string | null
          estimated_hours: number | null
          id: string
          organization_id: string
          sequence: number
          status: string
          updated_at: string
          work_order_id: string
        }
        SetofOptions: {
          from: "*"
          to: "work_order_activities"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_work_order_material: {
        Args: {
          p_material_id: string
          p_notes?: string
          p_planned_quantity?: number
          p_used_quantity?: number
          p_work_order_id: string
          p_work_order_material_id?: string
        }
        Returns: {
          created_at: string
          id: string
          material_id: string
          notes: string | null
          organization_id: string
          planned_quantity: number
          stock_snapshot: number
          updated_at: string
          used_quantity: number
          work_order_id: string
        }
        SetofOptions: {
          from: "*"
          to: "work_order_materials"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      validate_and_score_asset_criticality: {
        Args: {
          p_answers: Json
          p_asset_id: string
          p_expected_organization_id?: string
        }
        Returns: Json
      }
      write_criticality_thresholds: {
        Args: {
          p_critical_min: number
          p_high_min: number
          p_medium_min: number
          p_organization_id: string
        }
        Returns: undefined
      }
    }
    Enums: {
      app_role: "cliente" | "proveedor" | "team_member"
      assignment_status: "pending" | "accepted" | "rejected"
      certification_status:
        | "not_started"
        | "in_review"
        | "certified"
        | "rejected"
      notification_type:
        | "technical_visit"
        | "quote_received"
        | "assignment"
        | "general"
      organization_invitation_status:
        | "pending"
        | "accepted"
        | "revoked"
        | "expired"
      organization_member_role:
        | "owner"
        | "admin"
        | "manager"
        | "requester"
        | "quote_manager"
        | "technician"
        | "operator"
        | "viewer"
      organization_relationship_status:
        | "pending"
        | "active"
        | "suspended"
        | "ended"
      organization_relationship_type:
        | "provider"
        | "facility_management"
        | "subcontracting"
      organization_type:
        | "client_company"
        | "provider_company"
        | "facility_manager"
        | "subcontractor_company"
        | "platform_admin"
      request_status: "draft" | "sent" | "quoted" | "completed" | "anulado"
      service_type: "emergencia" | "correctivo" | "preventivo" | "proyecto"
    }
    CompositeTypes: {
      dblink_pkey_results: {
        position: number | null
        colname: string | null
      }
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      app_role: ["cliente", "proveedor", "team_member"],
      assignment_status: ["pending", "accepted", "rejected"],
      certification_status: [
        "not_started",
        "in_review",
        "certified",
        "rejected",
      ],
      notification_type: [
        "technical_visit",
        "quote_received",
        "assignment",
        "general",
      ],
      organization_invitation_status: [
        "pending",
        "accepted",
        "revoked",
        "expired",
      ],
      organization_member_role: [
        "owner",
        "admin",
        "manager",
        "requester",
        "quote_manager",
        "technician",
        "operator",
        "viewer",
      ],
      organization_relationship_status: [
        "pending",
        "active",
        "suspended",
        "ended",
      ],
      organization_relationship_type: [
        "provider",
        "facility_management",
        "subcontracting",
      ],
      organization_type: [
        "client_company",
        "provider_company",
        "facility_manager",
        "subcontractor_company",
        "platform_admin",
      ],
      request_status: ["draft", "sent", "quoted", "completed", "anulado"],
      service_type: ["emergencia", "correctivo", "preventivo", "proyecto"],
    },
  },
} as const
