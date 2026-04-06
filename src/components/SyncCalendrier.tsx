import React, { useState, useEffect } from 'react';
import { Apple, Download, Calendar, CalendarPlus } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { format } from 'date-fns';

/** Generate a single-event .ics file for adding to any calendar app */
export function generateMissionIcs(mission: { intitule: string; debut_le: string; fin_le: string; etablissements?: { nom?: string; adresse_ville?: string; adresse_rue?: string } | null }): string {
  const start = new Date(mission.debut_le).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
  const end = new Date(mission.fin_le).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
  const location = [mission.etablissements?.adresse_rue, mission.etablissements?.adresse_ville].filter(Boolean).join(', ');
  const summary = mission.intitule.replace(/[,;\\]/g, ' ');
  const desc = `Mission Jolene — ${mission.etablissements?.nom || ''}`;

  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Jolene//Missions//FR',
    'BEGIN:VEVENT',
    `DTSTART:${start}`,
    `DTEND:${end}`,
    `SUMMARY:${summary}`,
    `DESCRIPTION:${desc}`,
    location ? `LOCATION:${location}` : '',
    `UID:${mission.debut_le}-jolene@app.jolene.app`,
    'END:VEVENT',
    'END:VCALENDAR',
  ].filter(Boolean).join('\r\n');
}

/** Download a single mission as .ics */
export function downloadMissionIcs(mission: Parameters<typeof generateMissionIcs>[0]) {
  const ics = generateMissionIcs(mission);
  const blob = new Blob([ics], { type: 'text/calendar;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `mission-jolene-${format(new Date(mission.debut_le), 'yyyy-MM-dd')}.ics`;
  a.click();
  URL.revokeObjectURL(url);
}

/** Small button to add a single mission to calendar */
export function BoutonAjouterCalendrier({ mission }: { mission: Parameters<typeof generateMissionIcs>[0] }) {
  return (
    <button
      onClick={(e) => { e.stopPropagation(); downloadMissionIcs(mission); }}
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
      const blob = new Blob([text], { type: 'text/calendar' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'missions-jolene.ics';
      a.click();
      URL.revokeObjectURL(url);
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
