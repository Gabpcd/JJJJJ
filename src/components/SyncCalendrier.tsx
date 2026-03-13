import React, { useState } from 'react';
import { Apple, Download, Calendar } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';

export function SyncCalendrier() {
  const { user } = useAuth();
  const [open, setOpen] = useState(false);

  if (!user) return null;

  const baseUrl = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/calendar-feed?uid=${user.id}`;
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
      a.download = 'missions-soin-direct.ics';
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
