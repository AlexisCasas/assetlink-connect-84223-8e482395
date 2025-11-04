-- Add reviewer and approver columns to assignments table
ALTER TABLE assignments 
ADD COLUMN reviewer_id uuid REFERENCES team_members(id),
ADD COLUMN reviewer_name text,
ADD COLUMN approver_id uuid REFERENCES team_members(id),
ADD COLUMN approver_name text;

-- Create indexes for better query performance
CREATE INDEX idx_assignments_reviewer_id ON assignments(reviewer_id);
CREATE INDEX idx_assignments_approver_id ON assignments(approver_id);

-- Add comments for documentation
COMMENT ON COLUMN assignments.reviewer_id IS 'Miembro del equipo que revisará la cotización';
COMMENT ON COLUMN assignments.reviewer_name IS 'Nombre del revisor';
COMMENT ON COLUMN assignments.approver_id IS 'Miembro del equipo que aprobará/validará la cotización';
COMMENT ON COLUMN assignments.approver_name IS 'Nombre del aprobador';

-- Update the trigger function to add reviewer and approver as chat participants
CREATE OR REPLACE FUNCTION public.add_chat_participants_on_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Agregar al cliente
  INSERT INTO request_chat_participants (request_id, user_email, user_name, user_role)
  SELECT 
    NEW.request_id,
    r.created_by,
    COALESCE(r.client_name, r.created_by),
    'client'
  FROM requests r
  WHERE r.id = NEW.request_id
  ON CONFLICT (request_id, user_email) DO NOTHING;
  
  -- Agregar al proveedor
  INSERT INTO request_chat_participants (request_id, user_email, user_name, user_role)
  SELECT 
    NEW.request_id,
    p.email,
    p.name,
    'provider'
  FROM providers p
  WHERE p.id = NEW.provider_id
  ON CONFLICT (request_id, user_email) DO NOTHING;
  
  -- Agregar al cotizador (team member)
  INSERT INTO request_chat_participants (request_id, user_email, user_name, user_role)
  SELECT
    NEW.request_id,
    tm.email,
    NEW.team_member_name,
    'team_member'
  FROM team_members tm
  WHERE tm.id = NEW.team_member_id
  ON CONFLICT (request_id, user_email) DO NOTHING;
  
  -- Agregar al revisor si existe y es diferente al cotizador
  IF NEW.reviewer_id IS NOT NULL AND NEW.reviewer_id != NEW.team_member_id THEN
    INSERT INTO request_chat_participants (request_id, user_email, user_name, user_role)
    SELECT
      NEW.request_id,
      tm.email,
      NEW.reviewer_name,
      'team_member'
    FROM team_members tm
    WHERE tm.id = NEW.reviewer_id
    ON CONFLICT (request_id, user_email) DO NOTHING;
  END IF;
  
  -- Agregar al aprobador si existe y es diferente al cotizador y revisor
  IF NEW.approver_id IS NOT NULL 
     AND NEW.approver_id != NEW.team_member_id 
     AND (NEW.reviewer_id IS NULL OR NEW.approver_id != NEW.reviewer_id) THEN
    INSERT INTO request_chat_participants (request_id, user_email, user_name, user_role)
    SELECT
      NEW.request_id,
      tm.email,
      NEW.approver_name,
      'team_member'
    FROM team_members tm
    WHERE tm.id = NEW.approver_id
    ON CONFLICT (request_id, user_email) DO NOTHING;
  END IF;
  
  RETURN NEW;
END;
$$;