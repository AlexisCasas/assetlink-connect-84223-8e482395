const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim();
const supabaseKey = (
  import.meta.env.VITE_SUPABASE_ANON_KEY
  ?? import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY
)?.trim();

const missingSupabaseVariables = [
  !supabaseUrl && 'VITE_SUPABASE_URL',
  !supabaseKey && 'VITE_SUPABASE_ANON_KEY',
].filter(Boolean) as string[];

export const supabaseEnvironment = {
  url: supabaseUrl,
  key: supabaseKey,
};

export const supabaseConfigurationError = missingSupabaseVariables.length > 0
  ? `Faltan variables de configuración: ${missingSupabaseVariables.join(', ')}.`
  : null;

if (import.meta.env.DEV && supabaseConfigurationError) {
  console.error(
    `[One Facility] ${supabaseConfigurationError} Define las variables en .env.local; nunca subas ese archivo al repositorio.`,
  );
}
