export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "13.0.5"
  }
  public: {
    Tables: {
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
      chat_messages: {
        Row: {
          created_at: string
          id: string
          message: string
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
          quote_id?: string | null
          request_id?: string | null
          sender_email?: string | null
          sender_name?: string | null
          sender_type?: string
        }
        Relationships: [
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
      providers: {
        Row: {
          certified: boolean | null
          created_at: string
          email: string
          id: string
          name: string
          rating: number | null
          specialties: string[]
        }
        Insert: {
          certified?: boolean | null
          created_at?: string
          email: string
          id?: string
          name: string
          rating?: number | null
          specialties?: string[]
        }
        Update: {
          certified?: boolean | null
          created_at?: string
          email?: string
          id?: string
          name?: string
          rating?: number | null
          specialties?: string[]
        }
        Relationships: []
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
          client_observation: string | null
          created_at: string
          description: string
          id: string
          provider_id: string
          request_id: string
          status: string
          team_member_id: string
        }
        Insert: {
          amount: number
          approval_reason?: string | null
          client_observation?: string | null
          created_at?: string
          description: string
          id?: string
          provider_id: string
          request_id: string
          status?: string
          team_member_id: string
        }
        Update: {
          amount?: number
          approval_reason?: string | null
          client_observation?: string | null
          created_at?: string
          description?: string
          id?: string
          provider_id?: string
          request_id?: string
          status?: string
          team_member_id?: string
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
          city: string | null
          client_branch: string | null
          client_name: string | null
          created_at: string
          created_by: string
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
          priority: number
          quotes_closed: boolean
          request_number: string
          requires_visit: boolean | null
          service_type: Database["public"]["Enums"]["service_type"]
          start_time: string | null
          status: Database["public"]["Enums"]["request_status"]
          store: string | null
          visit_date: string | null
        }
        Insert: {
          asset: string
          branch?: string | null
          city?: string | null
          client_branch?: string | null
          client_name?: string | null
          created_at?: string
          created_by: string
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
          priority?: number
          quotes_closed?: boolean
          request_number: string
          requires_visit?: boolean | null
          service_type: Database["public"]["Enums"]["service_type"]
          start_time?: string | null
          status?: Database["public"]["Enums"]["request_status"]
          store?: string | null
          visit_date?: string | null
        }
        Update: {
          asset?: string
          branch?: string | null
          city?: string | null
          client_branch?: string | null
          client_name?: string | null
          created_at?: string
          created_by?: string
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
          priority?: number
          quotes_closed?: boolean
          request_number?: string
          requires_visit?: boolean | null
          service_type?: Database["public"]["Enums"]["service_type"]
          start_time?: string | null
          status?: Database["public"]["Enums"]["request_status"]
          store?: string | null
          visit_date?: string | null
        }
        Relationships: []
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
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
    }
    Enums: {
      assignment_status: "pending" | "accepted" | "rejected"
      notification_type:
        | "technical_visit"
        | "quote_received"
        | "assignment"
        | "general"
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
  public: {
    Enums: {
      assignment_status: ["pending", "accepted", "rejected"],
      notification_type: [
        "technical_visit",
        "quote_received",
        "assignment",
        "general",
      ],
      request_status: ["draft", "sent", "quoted", "completed", "anulado"],
      service_type: ["emergencia", "correctivo", "preventivo", "proyecto"],
    },
  },
} as const
