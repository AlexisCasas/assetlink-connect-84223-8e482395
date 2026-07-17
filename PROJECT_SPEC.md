# Project Specification: Facility Management Platform (Request & Work Order Subsystem)

## 1. Executive Summary & Vision
This document outlines the comprehensive technical and functional specifications for the Request and Work Order Subsystem of the Facility Management Platform. The subsystem serves as a multi-sided marketplace and workflow automation tool connecting **Clients**, internal **Team Members**, and external **Providers**. It streamlines the entire asset maintenance lifecycle—from identifying an issue on an asset to drafting a request, sourcing vendor quotes, coordinating technical site visits, navigating internal approval limits, executing work orders, and archiving completions.

The interface and directory structure have been engineered to ensure modularity, clear separation of concerns, and immediate alignment with a scalable backend (e.g., Supabase).

---

## 2. System Architecture & Component Directory
The front-end structure is highly modularized under `src/components/requests/`, establishing clear abstractions for data filtering, form interaction, workflow dialogs, and role-based views.

### 2.1 File Map & Component Responsibilities
*   **`RequestForm.tsx` / `OrderForm.tsx`**: Core submission engines. Handles data orchestration for creating/editing service requests, picking priorities, mapping assets, and assigning initial bounds.
*   **`DraftList.tsx`**: Localized or server-cached list management for incomplete requests (`Status: Draft`). Allows offline-first saving or standard transient states.
*   **`PublicRequestList.tsx`**: Marketplace view exposed to verified external providers seeking new work requests or biddable jobs.
*   **`ProviderRequestList.tsx`**: Focused dashboard tailored for an individual provider to track requests they have bid on, are under negotiation for, or have been awarded.
*   **`TeamMemberView.tsx`**: Internal management console giving administrators and operations team members an overarching view of all incoming traffic, system health, and cross-organization routing.
*   **`OrderFilters.tsx`**: Multi-dimensional filtering logic (by date, priority, asset tier, branch, status) applied across all list views.
*   **`AssetTree.tsx` & `AssetDetail.tsx`**: Structural asset components allowing users to drill down into a hierarchical tree (e.g., *Sede Central -> Piso 2 -> Servidor RACK-A*) and review physical details before binding an order.
*   **`BranchesList.tsx`**: Organizational boundary picker to filter assets and requests by physical corporate branches or geographical locations.
*   **`TemplateSelector.tsx` & `SaveTemplateDialog.tsx`**: Blueprint components allowing quick replication of recurring preventative maintenance tasks or common corrective configurations.

### 2.2 Dialogue & Workflow Overlays
*   **`TechnicalVisitDialog.tsx`**: Orchestrates site-survey requests where a provider must inspect the machinery physically before supplying a final quote.
*   **`QuoteForm.tsx` & `QuoteListDialog.tsx`**: Bidding interface where providers declare line items, labor costs, estimated durations, and terms.
*   **`ApprovalDialog.tsx`**: Internal corporate routing block checking request limits and allowing budget holders to clear or reject specific job funding.
*   **`AssignmentDialog.tsx`**: Post-approval mechanic allowing a team member or system rule to officially dispatch a provider to a work order.
*   **`AcceptRejectDialog.tsx`**: Final formalization mechanism for accepting/rejecting bids or confirming completions.
*   **`ForumQADialog.tsx`**, `QuoteChatDialog.tsx`, & `RequestChatDialog.tsx`: Communication channels handling public clarification boards, private bid negotiations, and real-time operational execution chat respectively.

---

## 3. Request Lifecycle & State Machine
The lifecycle transitions through clear logical milestones. Every state shift enforces database audits and changes visibility permissions across roles.

```
 [ Draft ] ──> [ Public / Pending Quote ] ──> [ In Negotiation / Bidding ]
                                                       │
 [ Approved / Assigned ] <── [ Pending Approval ] <───┴──> [ Technical Visit ]
          │
          └──> [ In Execution ] ──> [ Completed / Archived ]
```

### 3.1 State Dictionary
1.  **Draft**: Request is under construction by the client or team member. Invisible to providers. No validation constraints enforced on sub-components.
2.  **Public / Pending Quote**: Request is broadcasted. Open for public clarification questions via `ForumQADialog`. Providers can view high-level asset details and branches.
3.  **In Negotiation**: Active bids are received via `QuoteForm`. Visible items appear in `QuoteListDialog`. Conversations split into private `QuoteChatDialog` channels per bidding vendor.
4.  **Technical Visit Required**: If standard descriptions are insufficient, the workflow pauses for scheduling a physical inspection using `TechnicalVisitDialog`.
5.  **Pending Approval & Assignment**: A specific quote is chosen. If it exceeds predefined corporate tiers, `ApprovalDialog` locks it until authorized. Once approved, `AssignmentDialog` transfers ownership to the provider.
6.  **In Execution**: The order becomes an active work ticket. Managed via `RequestChatDialog` for operational updates, attachments, and progress logs.
7.  **Completed / Closed**: Service validated by client, final invoices prepared, asset log updated.

---

## 4. User Roles & Permission Matrix

| Component / Action | Client User | Team Member (Admin/Ops) | External Provider |
| :--- | :--- | :--- | :--- |
| **`RequestForm` / Templates** | Create, Update, Delete Drafts | Complete Overrides & Templates | View Only (Once Public) |
| **`DraftList`** | Read / Write own | Read / Write All | No Access |
| **`PublicRequestList`** | Read own | Full Global Read | Read open rows / Submit bids |
| **`ApprovalDialog`** | View Status | Approve / Reject according to authorization tier | No Access |
| **`ForumQADialog`** | Read & Answer questions | Global Moderation | Ask Clarification Questions |
| **`QuoteChatDialog`** | Read / Write (with selected vendor) | Monitor / Moderate | Read / Write with Client |
| **`TechnicalVisitDialog`** | Approve Date | Schedule / Coordinate | Request / Propose Date |

---

## 5. Subsystem Core Specifications

### 5.1 Asset Hierarchy Integration (`AssetTree.tsx` & `AssetDetail.tsx`)
*   **Functional Goal**: Prevent unanchored service requests. Every request must cleanly map to a node in the asset tree.
*   **Data Injection**: When selecting an asset, the form must inherit its branch ID, historical breakdown logs, and warranty limits automatically to avoid dual data entry.

### 5.2 Multi-Tiered Communication Subsystems
The architecture isolates chat types to preserve privacy boundaries and avoid data leakage:
1.  **Public QA Board (`ForumQADialog`)**: One-to-many. Anonymized provider handles asking questions about a public project. Answers are visible to all prospective bidders.
2.  **Bid Negotiation Room (`QuoteChatDialog`)**: One-to-one-to-many (Client, Admin, single Provider). Completely private room for reviewing lines of credit, specific materials, or adjusting costs.
3.  **Operational Ticket Thread (`RequestChatDialog`)**: One-to-one-to-one (Client contact on-site, Admin, assigned Provider field tech). Used exclusively for coordination ("I am outside", upload photo of fixed machine).

---

## 6. Recommended Supabase Schema & Data Layout

To fully power this frontend architecture, the database layers should map to the following structure utilizing Row Level Security (RLS) policies:

### 6.1 `requests` Table
*   `id` (uuid, PK)
*   `title` (varchar)
*   `description` (text)
*   `status` (enum: draft, public, negotiation, pending_approval, assigned, execution, completed)
*   `priority` (enum: low, medium, high, critical)
*   `asset_id` (uuid, FK -> assets.id)
*   `branch_id` (uuid, FK -> branches.id)
*   `created_by` (uuid, FK -> auth.users)
*   `assigned_provider_id` (uuid, FK -> providers.id, nullable)
*   `created_at`, `updated_at` (timestamps)

### 6.2 `quotes` Table
*   `id` (uuid, PK)
*   `request_id` (uuid, FK -> requests.id)
*   `provider_id` (uuid, FK -> providers.id)
*   `total_amount` (numeric)
*   `breakdown` (jsonb: material costs, labor, overhead)
*   `estimated_duration_days` (integer)
*   `status` (enum: pending, short_listed, approved, rejected)

### 6.3 `messages` Table (Polymorphic Routing)
*   `id` (uuid, PK)
*   `context_type` (enum: forum, quote, request)
*   `context_id` (uuid - points to request_id or quote_id depending on context)
*   `sender_id` (uuid, FK -> auth.users)
*   `message_body` (text)
*   `attachments` (array of text urls to storage buckets)
*   `created_at` (timestamp)

---

## 7. Immediate Next Steps & Engineering Runway
1.  **Type Mapping Validation**: Verify that `src/types/` fully supports unified TypeScript interfaces that bind `quotes`, `assets`, and `messages` perfectly to the schema.
2.  **RLS Policies Implementation**: Write secure Supabase policies ensuring providers can only view chats associated with their specific `provider_id`, while public forum messages are visible to any authenticated user under the provider role.
3.  **Approval Limits Wireframe**: Wire up `ApprovalDialog` to checking profile-level budget authority values to dynamically render the confirmation actions.
