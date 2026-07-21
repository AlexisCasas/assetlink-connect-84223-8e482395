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
          expires_at: string | null
          id: string
          invited_by: string
          organization_id: string
          revoked_at: string | null
          role: Database["public"]["Enums"]["organization_member_role"]
          status: Database["public"]["Enums"]["organization_invitation_status"]
          token_hash: string | null
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email: string
          expires_at?: string | null
          id?: string
          invited_by: string
          organization_id: string
          revoked_at?: string | null
          role: Database["public"]["Enums"]["organization_member_role"]
          status?: Database["public"]["Enums"]["organization_invitation_status"]
          token_hash?: string | null
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email?: string
          expires_at?: string | null
          id?: string
          invited_by?: string
          organization_id?: string
          revoked_at?: string | null
          role?: Database["public"]["Enums"]["organization_member_role"]
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
          organization_id: string
          read_at: string | null
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
          organization_id: string
          read_at?: string | null
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
          organization_id?: string
          read_at?: string | null
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
          branch: string | null
          branch_id: string | null
          city: string | null
          client_branch: string | null
          client_name: string | null
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
          is_public: boolean | null
          location: string
          min_quotes: number
          notified_at: string | null
          observations: string | null
          organization_id: string | null
          priority: number
          quotes_closed: boolean
          request_number: string
          requires_visit: boolean | null
          service_type: Database["public"]["Enums"]["service_type"]
          start_time: string | null
          status: Database["public"]["Enums"]["request_status"]
          store: string | null
          title: string | null
          updated_at: string
          visit_date: string | null
        }
        Insert: {
          asset: string
          branch?: string | null
          branch_id?: string | null
          city?: string | null
          client_branch?: string | null
          client_name?: string | null
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
          is_public?: boolean | null
          location: string
          min_quotes?: number
          notified_at?: string | null
          observations?: string | null
          organization_id?: string | null
          priority?: number
          quotes_closed?: boolean
          request_number: string
          requires_visit?: boolean | null
          service_type: Database["public"]["Enums"]["service_type"]
          start_time?: string | null
          status?: Database["public"]["Enums"]["request_status"]
          store?: string | null
          title?: string | null
          updated_at?: string
          visit_date?: string | null
        }
        Update: {
          asset?: string
          branch?: string | null
          branch_id?: string | null
          city?: string | null
          client_branch?: string | null
          client_name?: string | null
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
          is_public?: boolean | null
          location?: string
          min_quotes?: number
          notified_at?: string | null
          observations?: string | null
          organization_id?: string | null
          priority?: number
          quotes_closed?: boolean
          request_number?: string
          requires_visit?: boolean | null
          service_type?: Database["public"]["Enums"]["service_type"]
          start_time?: string | null
          status?: Database["public"]["Enums"]["request_status"]
          store?: string | null
          title?: string | null
          updated_at?: string
          visit_date?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "requests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
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
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      approve_quote: { Args: { target_quote_id: string }; Returns: undefined }
      can_provider_quote_request: {
        Args: {
          target_provider_organization_id: string
          target_request_id: string
        }
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
      is_organization_member: {
        Args: { _organization_id: string }
        Returns: boolean
      }
      is_platform_admin: { Args: never; Returns: boolean }
      is_provider_facing_organization: {
        Args: { _organization_id: string }
        Returns: boolean
      }
      reject_quote: {
        Args: { reason?: string; target_quote_id: string }
        Returns: undefined
      }
      storage_request_id_from_name: {
        Args: { object_name: string }
        Returns: string
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
      [_ in never]: never
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
