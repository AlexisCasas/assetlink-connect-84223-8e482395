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
      assets: {
        Row: {
          asset_category_id: string | null
          barcode: string | null
          branch_id: string | null
          code: string | null
          created_at: string
          created_by_user_id: string | null
          criticality: string | null
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
          asset_id?: string | null
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
          asset_id?: string | null
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
            foreignKeyName: "requests_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
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
      approve_quote: { Args: { target_quote_id: string }; Returns: undefined }
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
      delete_work_order_activity: {
        Args: { p_activity_id: string }
        Returns: undefined
      }
      delete_work_order_material: {
        Args: { p_work_order_material_id: string }
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
      get_inventory_catalog: {
        Args: { p_organization_id: string }
        Returns: Json
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
      is_organization_member: {
        Args: { _organization_id: string }
        Returns: boolean
      }
      is_platform_admin: { Args: never; Returns: boolean }
      is_provider_facing_organization: {
        Args: { _organization_id: string }
        Returns: boolean
      }
      map_request_priority_to_work_order_priority: {
        Args: { request_priority: number }
        Returns: string
      }
      reject_quote: {
        Args: { reason?: string; target_quote_id: string }
        Returns: undefined
      }
      resolve_asset_path: { Args: { p_asset_id: string }; Returns: string }
      resolve_caller_planner_member: {
        Args: { p_organization_id: string }
        Returns: string
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
