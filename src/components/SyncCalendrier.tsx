import React, { useState, useEffect } from 'react';
import { Apple, Download, Calendar, CalendarPlus, LoaderCircle } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { telechargerOuPartager } from '@/lib/telechargement';
import { ouvrirMissionDansCalendrier, type MissionCalendrier } from '@/lib/ics-mission';

/** Small button to add a single mission to calendar */
export function BoutonAjouterCalendrier({ mission }: { mission: MissionCalendrier }) {
  const [ouverture, setOuverture] = useState(false);

  async function ouvrirCalendrier(e: React.MouseEvent<HTMLButtonElement>) {
    e.stopPropagation();
    if (ouverture) return;
    setOuverture(true);
    try {
      await ouvrirMissionDansCalendrier(mission);
    } catch (erreur) {
      const message = erreur instanceof Error ? erreur.message : '';
      if (!/cancel(?:ed|led)|annul/i.test(message)) {
        toast.error("Impossible d'ouvrir le calendrier pour le moment.");
      }
    } finally {
      setOuverture(false);
    }
  }

  return (
    <button
      type="button"
      onClick={ouvrirCalendrier}
      disabled={ouverture}
      className="inline-flex min-h-11 min-w-11 shrink-0 items-center justify-center gap-1 rounded-xl px-2 text-xs font-medium text-primary transition-colors hover:bg-primary/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50 disabled:opacity-60"
      title="Ajouter ce créneau au calendrier"
      aria-label="Ajouter ce créneau au calendrier"
    >
      {ouverture
        ? <LoaderCircle className="h-4 w-4 animate-spin" aria-hidden="true" />
        : <CalendarPlus className="h-4 w-4" aria-hidden="true" />}
      <span>Agenda</span>
    </button>
  );
}

export function SyncCalendrier() {
  const { user } = useAuth();
  const [open, setOpen] = useState(false);
  const [token, setToken] = useState<string | null>(null);

  useEffect(() => {
    if (!user) return;
    supabase.rpc('fn_mon_token_calendrier' as any).then(({ data }) => {
      if (data) setToken(data as string);
    });
  }, [user]);

  if (!user || !token) return null;

  const baseUrl = `${SUPABASE_URL}/functions/v1/calendar-feed?uid=${user.id}&token=${token}`;
  const webcalUrl = baseUrl.replace(/^https?:\/\//, 'webcal://');
  const googleUrl = `https://calendar.google.com/calendar/r?cid=${encodeURIComponent(webcalUrl)}`;

  async function handleDownloadIcs() {
    try {
      const res = await fetch(baseUrl);
      const text = await res.text();
      await telechargerOuPartager(text, 'missions-jolene.ics', 'text/calendar');
    } catch {
      // silent
    }
    setOpen(false);
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button variant="outline" size="sm" className="gap-2">
          <Calendar className="h-4 w-4" />
          Synchroniser
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-64 p-2" align="end">
        <div className="space-y-1">
          <a href={webcalUrl}
            className="flex items-center gap-2 px-3 py-2 rounded-lg text-sm hover:bg-muted transition-colors text-foreground">
            <Apple className="h-4 w-4 text-muted-foreground" />
            Apple Calendar
          </a>
          <a href={googleUrl} target="_blank" rel="noopener noreferrer"
            className="flex items-center gap-2 px-3 py-2 rounded-lg text-sm hover:bg-muted transition-colors text-foreground">
            <Calendar className="h-4 w-4 text-muted-foreground" />
            Google Calendar
          </a>
          <button onClick={handleDownloadIcs}
            className="flex items-center gap-2 px-3 py-2 rounded-lg text-sm hover:bg-muted transition-colors w-full text-left text-foreground">
            <Download className="h-4 w-4 text-muted-foreground" />
            Télécharger .ics
          </button>
        </div>
      </PopoverContent>
    </Popover>
  );
}
