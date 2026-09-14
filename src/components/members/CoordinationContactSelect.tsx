import { useMemo, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';
import { Check, ChevronsUpDown, Loader2, User } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useCoordinationContacts } from '@/hooks/useCoordinationContacts';

interface CoordinationContactSelectProps {
  organizationId: string | null | undefined;
  /** Selected organization_members.id, or null when unset. */
  value: string | null;
  onChange: (memberId: string | null, contact: { name: string; email: string } | null) => void;
  disabled?: boolean;
  label?: string;
}

/**
 * Searchable picker over the active members of the given organization (any
 * role) via useCoordinationContacts() -> get_coordination_contacts RPC.
 * Reused for both "Contacto de coordinación" and "Contacto de visita".
 */
export function CoordinationContactSelect({
  organizationId,
  value,
  onChange,
  disabled,
  label = 'Contacto de coordinación',
}: CoordinationContactSelectProps) {
  const { contacts, loading, error } = useCoordinationContacts(organizationId);
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');

  const selected = useMemo(
    () => (value ? contacts.find((contact) => contact.memberId === value) ?? null : null),
    [contacts, value],
  );

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();
    if (!term) return contacts;
    return contacts.filter((contact) =>
      contact.name.toLowerCase().includes(term) || contact.email.toLowerCase().includes(term));
  }, [contacts, search]);

  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>
          <Button
            type="button"
            variant="outline"
            role="combobox"
            aria-expanded={open}
            disabled={disabled || loading || !organizationId}
            className="w-full justify-between font-normal"
          >
            {loading ? (
              <span className="flex items-center text-muted-foreground">
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Cargando contactos…
              </span>
            ) : selected ? (
              <span className="flex items-center gap-2 truncate">
                <User className="h-4 w-4 shrink-0 text-muted-foreground" />
                <span className="truncate">{selected.name}</span>
                <span className="truncate text-xs text-muted-foreground">{selected.email}</span>
              </span>
            ) : (
              <span className="text-muted-foreground">Selecciona un contacto</span>
            )}
            <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-[--radix-popover-trigger-width] p-0" align="start">
          <Command shouldFilter={false}>
            <CommandInput placeholder="Buscar por nombre o correo…" value={search} onValueChange={setSearch} />
            <CommandList>
              <CommandEmpty>No se encontraron contactos.</CommandEmpty>
              <CommandGroup>
                {filtered.map((contact) => (
                  <CommandItem
                    key={contact.memberId}
                    value={contact.memberId}
                    onSelect={() => {
                      onChange(contact.memberId, { name: contact.name, email: contact.email });
                      setOpen(false);
                    }}
                  >
                    <Check className={cn('mr-2 h-4 w-4 shrink-0', value === contact.memberId ? 'opacity-100' : 'opacity-0')} />
                    <span className="flex min-w-0 flex-col">
                      <span className="truncate">{contact.name}</span>
                      <span className="truncate text-xs text-muted-foreground">{contact.email}</span>
                    </span>
                  </CommandItem>
                ))}
              </CommandGroup>
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>
      {!loading && !error && organizationId && contacts.length === 0 && (
        <p className="text-xs text-muted-foreground">Esta organización todavía no tiene miembros activos.</p>
      )}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  );
}
