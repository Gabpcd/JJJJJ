import React, { useState, useEffect } from 'react';
import { Apple, Download, Calendar, CalendarPlus } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { telechargerOuPartager } from '@/lib/telechargement';
import { downloadMissionIcs, type MissionCalendrier } from '@/lib/ics-mission';

/** Small button to add a single mission to calendar */
export function BoutonAjouterCalendrier({ mission }: { mission: MissionCalendrier }) {
  return (
    <button
      onClick={(e) => { e.stopPropagation(); void downloadMissionIcs(mission); }}
      className="inline-flex items-center gap-1 text-xs text-primary hover:underline"
      title="Ajouter au calendrier"
    >
      <CalendarPlus className="h-3.5 w-3.5" /> Agenda
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
