-- Modificar tabla chat_messages para soportar chats por solicitud
ALTER TABLE chat_messages 
ADD COLUMN request_id uuid REFERENCES requests(id) ON DELETE CASCADE,
ADD COLUMN sender_email text,
ADD COLUMN sender_name text;

-- Hacer quote_id opcional
ALTER TABLE chat_messages 
ALTER COLUMN quote_id DROP NOT NULL;

-- Agregar restricción para que tenga request_id O quote_id
ALTER TABLE chat_messages
ADD CONSTRAINT check_has_request_or_quote CHECK (
  (request_id IS NOT NULL AND quote_id IS NULL) OR 
  (request_id IS NULL AND quote_id IS NOT NULL)
);

-- Crear índice para búsquedas rápidas
CREATE INDEX idx_chat_messages_request_id ON chat_messages(request_id);
CREATE INDEX idx_chat_messages_sender_email ON chat_messages(sender_email);

-- Tabla de participantes del chat
CREATE TABLE request_chat_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid REFERENCES requests(id) ON DELETE CASCADE NOT NULL,
  user_email text NOT NULL,
  user_name text,
  user_role text NOT NULL CHECK (user_role IN ('client', 'provider', 'team_member')),
  joined_at timestamp with time zone DEFAULT now(),
  last_read_at timestamp with time zone DEFAULT now(),
  UNIQUE(request_id, user_email)
);

-- Índices para participantes
CREATE INDEX idx_chat_participants_user_email ON request_chat_participants(user_email);
CREATE INDEX idx_chat_participants_request_id ON request_chat_participants(request_id);

-- Enable RLS para request_chat_participants
ALTER TABLE request_chat_participants ENABLE ROW LEVEL SECURITY;

-- Policy para que cualquiera pueda ver participantes
CREATE POLICY "Anyone can view chat participants"
ON request_chat_participants FOR SELECT
USING (true);

-- Policy para insertar participantes
CREATE POLICY "Anyone can insert chat participants"
ON request_chat_participants FOR INSERT
WITH CHECK (true);

-- Policy para actualizar participantes (para last_read_at)
CREATE POLICY "Anyone can update chat participants"
ON request_chat_participants FOR UPDATE
USING (true);

-- Actualizar policy de chat_messages para incluir request_id
DROP POLICY IF EXISTS "Anyone can view chat messages" ON chat_messages;
CREATE POLICY "Anyone can view chat messages"
ON chat_messages FOR SELECT
USING (true);

DROP POLICY IF EXISTS "Anyone can insert chat messages" ON chat_messages;
CREATE POLICY "Anyone can insert chat messages"
ON chat_messages FOR INSERT
WITH CHECK (true);

-- Función para agregar participantes automáticamente cuando se asigna una solicitud
CREATE OR REPLACE FUNCTION add_chat_participants_on_assignment()
RETURNS TRIGGER AS $$
BEGIN
  -- Agregar al cliente (si no existe)
  INSERT INTO request_chat_participants (request_id, user_email, user_name, user_role)
  SELECT 
    NEW.request_id,
    r.created_by,
    COALESCE(r.client_name, r.created_by),
    'client'
  FROM requests r
  WHERE r.id = NEW.request_id
  ON CONFLICT (request_id, user_email) DO NOTHING;
  
  -- Agregar al proveedor (si existe)
  INSERT INTO request_chat_participants (request_id, user_email, user_name, user_role)
  SELECT 
    NEW.request_id,
    p.email,
    p.name,
    'provider'
  FROM providers p
  WHERE p.id = NEW.provider_id
  ON CONFLICT (request_id, user_email) DO NOTHING;
  
  -- Agregar al miembro del equipo
  INSERT INTO request_chat_participants (request_id, user_email, user_name, user_role)
  VALUES (
    NEW.request_id,
    (SELECT email FROM team_members WHERE id = NEW.team_member_id),
    NEW.team_member_name,
    'team_member'
  )
  ON CONFLICT (request_id, user_email) DO NOTHING;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear trigger
CREATE TRIGGER trigger_add_chat_participants
AFTER INSERT OR UPDATE ON assignments
FOR EACH ROW
EXECUTE FUNCTION add_chat_participants_on_assignment();

-- Habilitar realtime para las tablas de chat
ALTER PUBLICATION supabase_realtime ADD TABLE chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE request_chat_participants;