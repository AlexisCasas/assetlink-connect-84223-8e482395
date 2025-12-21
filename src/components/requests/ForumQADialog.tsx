import { useState, useEffect, useRef } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { ScrollArea } from '@/components/ui/scroll-area';
import { supabase } from '@/integrations/supabase/client';
import { Send } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/contexts/AuthContext';
import { format } from 'date-fns';
import { es } from 'date-fns/locale';

interface ForumQADialogProps {
  open: boolean;
  onClose: () => void;
  requestId: string;
  requestNumber: string;
}

interface ForumMessage {
  id: string;
  sender_type: 'client' | 'provider';
  sender_name: string | null;
  message: string;
  created_at: string;
  parent_id?: string | null;
}

interface QuestionThread {
  question: ForumMessage;
  answer: ForumMessage | null;
}

// Preguntas de ejemplo aleatorias relacionadas con servicios
const SAMPLE_QUESTIONS = [
  "¿Cuál es el horario disponible para realizar el servicio?",
  "¿Se requiere algún material específico para el trabajo?",
  "¿Cuántas personas del equipo técnico asistirán?",
  "¿El servicio incluye garantía? ¿Por cuánto tiempo?",
  "¿Necesitan acceso a algún sistema eléctrico especial?",
  "¿Cuál es el tiempo estimado de duración del trabajo?",
  "¿Se puede realizar el servicio en horario nocturno?",
  "¿Requieren estacionamiento para vehículos de la empresa?",
  "¿El área debe estar desocupada durante el servicio?",
  "¿Se generará ruido o interrupciones durante el trabajo?",
  "¿Cuáles son las medidas de seguridad que implementan?",
  "¿Pueden enviar un técnico para una inspección previa?",
  "¿El presupuesto incluye limpieza posterior al trabajo?",
  "¿Tienen certificaciones para este tipo de servicio?",
  "¿Cuál es la disponibilidad para iniciar el proyecto?"
];

const SAMPLE_ANSWERS = [
  "Estamos disponibles de lunes a viernes de 8am a 6pm.",
  "Todo el material está incluido en el presupuesto.",
  "Asistirán 3 técnicos especializados.",
  "Sí, ofrecemos 6 meses de garantía en mano de obra.",
  "Sí, necesitamos acceso al tablero principal.",
  "El trabajo tomará aproximadamente 4 horas.",
  "Sí, podemos coordinar trabajo nocturno con recargo.",
  "Sí, necesitamos 2 espacios de estacionamiento.",
  "Solo parcialmente, pueden continuar trabajando en otras áreas.",
  "Habrá ruido moderado durante 2 horas aproximadamente.",
  "Usamos equipos de protección personal y señalización.",
  "Sí, podemos agendar una visita técnica previa sin costo.",
  "Sí, dejamos el área completamente limpia.",
  "Contamos con certificación ISO 9001.",
  "Podemos iniciar la próxima semana."
];

export const ForumQADialog = ({ open, onClose, requestId, requestNumber }: ForumQADialogProps) => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [threads, setThreads] = useState<QuestionThread[]>([]);
  const [loading, setLoading] = useState(true);
  const [replyingTo, setReplyingTo] = useState<string | null>(null);
  const [replyText, setReplyText] = useState('');
  const [sending, setSending] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (open && requestId) {
      loadMessages();

      // Subscribe to new messages
      const channel = supabase
        .channel(`forum_${requestId}`)
        .on(
          'postgres_changes',
          {
            event: 'INSERT',
            schema: 'public',
            table: 'chat_messages',
            filter: `request_id=eq.${requestId}`
          },
          () => {
            loadMessages();
          }
        )
        .subscribe();

      return () => {
        supabase.removeChannel(channel);
      };
    }
  }, [open, requestId]);

  const loadMessages = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('chat_messages')
        .select('*')
        .eq('request_id', requestId)
        .order('created_at', { ascending: true });

      if (error) throw error;

      const messages = (data || []) as ForumMessage[];
      
      // Si no hay mensajes, generar datos de ejemplo
      if (messages.length === 0) {
        await generateSampleData();
        return;
      }

      // Organizar en hilos (pregunta -> respuesta)
      const questionThreads: QuestionThread[] = [];
      const answeredQuestions = new Set<string>();

      // Primero encontrar todas las respuestas y sus preguntas padre
      messages.forEach(msg => {
        if (msg.sender_type === 'client' && msg.parent_id) {
          answeredQuestions.add(msg.parent_id);
        }
      });

      // Construir los hilos
      messages.forEach(msg => {
        if (msg.sender_type === 'provider') {
          // Es una pregunta de proveedor
          const answer = messages.find(
            m => m.sender_type === 'client' && m.parent_id === msg.id
          );
          questionThreads.push({
            question: msg,
            answer: answer || null
          });
        }
      });

      setThreads(questionThreads);
    } catch (error) {
      console.error('Error loading messages:', error);
    } finally {
      setLoading(false);
    }
  };

  const generateSampleData = async () => {
    try {
      // Generar entre 3 y 6 preguntas aleatorias
      const numQuestions = Math.floor(Math.random() * 4) + 3;
      const shuffledQuestions = [...SAMPLE_QUESTIONS].sort(() => Math.random() - 0.5);
      const shuffledAnswers = [...SAMPLE_ANSWERS].sort(() => Math.random() - 0.5);
      
      const selectedQuestions = shuffledQuestions.slice(0, numQuestions);
      
      // Crear las preguntas
      for (let i = 0; i < selectedQuestions.length; i++) {
        const question = selectedQuestions[i];
        
        // Insertar pregunta del proveedor (anónima)
        const { data: questionData, error: questionError } = await supabase
          .from('chat_messages')
          .insert({
            request_id: requestId,
            sender_type: 'provider',
            sender_name: 'Anónimo',
            message: question
          })
          .select()
          .single();

        if (questionError) throw questionError;

        // Aleatoriamente responder algunas preguntas (70% de probabilidad)
        if (Math.random() < 0.7 && questionData) {
          await supabase
            .from('chat_messages')
            .insert({
              request_id: requestId,
              sender_type: 'client',
              sender_name: user?.name || 'Cliente',
              message: shuffledAnswers[i] || 'Gracias por su consulta, nos pondremos en contacto.',
              parent_id: questionData.id
            } as any);
        }
      }

      // Recargar mensajes
      await loadMessages();
    } catch (error) {
      console.error('Error generating sample data:', error);
    }
  };

  const handleReply = async (questionId: string) => {
    if (!replyText.trim() || !user) return;

    try {
      setSending(true);
      
      const { error } = await supabase
        .from('chat_messages')
        .insert({
          request_id: requestId,
          sender_type: 'client',
          sender_name: user.name || user.email,
          sender_email: user.email,
          message: replyText.trim(),
          parent_id: questionId
        } as any);

      if (error) throw error;

      setReplyText('');
      setReplyingTo(null);
      toast({
        title: 'Respuesta enviada',
        description: 'Tu respuesta ha sido publicada correctamente.',
      });
    } catch (error) {
      console.error('Error sending reply:', error);
      toast({
        title: 'Error',
        description: 'No se pudo enviar la respuesta.',
        variant: 'destructive',
      });
    } finally {
      setSending(false);
    }
  };

  const formatDate = (dateString: string) => {
    return format(new Date(dateString), "dd/MM/yyyy HH:mm", { locale: es });
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-3xl max-h-[80vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>Foro de Preguntas - {requestNumber}</DialogTitle>
          <p className="text-sm text-muted-foreground">
            Período de participación activo
          </p>
        </DialogHeader>

        <ScrollArea className="flex-1 pr-4" ref={scrollRef}>
          <div className="space-y-4">
            {loading ? (
              <p className="text-center text-muted-foreground py-8">
                Cargando preguntas...
              </p>
            ) : threads.length === 0 ? (
              <p className="text-center text-muted-foreground py-8">
                No hay preguntas aún. Los proveedores podrán enviar sus consultas aquí.
              </p>
            ) : (
              threads.map((thread) => (
                <div key={thread.question.id} className="space-y-2">
                  {/* Pregunta del proveedor (anónima) */}
                  <div className="bg-muted rounded-lg overflow-hidden">
                    <div className="bg-gray-600 text-white px-4 py-2 flex justify-between items-center">
                      <span className="font-medium">Anónimo</span>
                      <span className="text-xs opacity-80">
                        {formatDate(thread.question.created_at)}
                      </span>
                    </div>
                    <div className="px-4 py-3">
                      <p className="text-sm">{thread.question.message}</p>
                    </div>
                  </div>

                  {/* Respuesta del cliente */}
                  {thread.answer ? (
                    <div className="ml-6 bg-green-50 dark:bg-green-900/20 rounded-lg overflow-hidden border border-green-200 dark:border-green-800">
                      <div className="bg-green-600 text-white px-4 py-2 flex justify-between items-center">
                        <span className="font-medium">{thread.answer.sender_name || 'Cliente'}</span>
                        <span className="text-xs opacity-80">
                          {formatDate(thread.answer.created_at)}
                        </span>
                      </div>
                      <div className="px-4 py-3">
                        <p className="text-sm">{thread.answer.message}</p>
                      </div>
                    </div>
                  ) : (
                    /* Formulario para responder */
                    <div className="ml-6">
                      {replyingTo === thread.question.id ? (
                        <div className="space-y-2 bg-muted/50 p-3 rounded-lg">
                          <Textarea
                            value={replyText}
                            onChange={(e) => setReplyText(e.target.value)}
                            placeholder="Escribe tu respuesta..."
                            rows={3}
                            className="resize-none"
                          />
                          <div className="flex gap-2 justify-end">
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => {
                                setReplyingTo(null);
                                setReplyText('');
                              }}
                            >
                              Cancelar
                            </Button>
                            <Button
                              size="sm"
                              onClick={() => handleReply(thread.question.id)}
                              disabled={sending || !replyText.trim()}
                            >
                              <Send className="h-4 w-4 mr-2" />
                              Enviar respuesta
                            </Button>
                          </div>
                        </div>
                      ) : (
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => setReplyingTo(thread.question.id)}
                          className="text-green-600 border-green-600 hover:bg-green-50"
                        >
                          Responder pregunta
                        </Button>
                      )}
                    </div>
                  )}
                </div>
              ))
            )}
          </div>
        </ScrollArea>
      </DialogContent>
    </Dialog>
  );
};
