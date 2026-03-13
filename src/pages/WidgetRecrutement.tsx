import React, { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { MapPin, Clock, HeartPulse } from 'lucide-react';
import { Badge } from '@/components/ui/badge';

export default function WidgetRecrutement() {
  const [searchParams] = useSearchParams();
  const etabId = searchParams.get('etab');
  const [missions, setMissions] = useState<any[]>([]);
  const [etabNom, setEtabNom] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!etabId) { setLoading(false); return; }

    Promise.all([
      supabase.from('etablissements').select('nom, adresse_ville').eq('id', etabId).single(),
      supabase.from('missions').select('id, intitule, profession_requise, debut_le, fin_le, taux_horaire_base, service')
        .eq('etablissement_id', etabId).eq('statut', 'OUVERTE').order('debut_le').limit(10),
    ]).then(([etabRes, missionsRes]) => {
      if (etabRes.data) setEtabNom(etabRes.data.nom);
      if (missionsRes.data) setMissions(missionsRes.data);
      setLoading(false);
    });
  }, [etabId]);

  if (!etabId) return <div className="p-4 text-sm text-muted-foreground">Paramètre etab manquant.</div>;

  const formatDate = (d: string) => new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short' });
  const formatHeure = (d: string) => new Date(d).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });

  return (
    <div className="max-w-lg mx-auto font-sans">
      {/* Header */}
      <div className="bg-[hsl(187,75%,40%)] text-white px-4 py-3 rounded-t-xl flex items-center gap-2">
        <HeartPulse className="h-5 w-5" />
        <div>
          <p className="font-semibold text-sm">{etabNom || 'Établissement'}</p>
          <p className="text-[11px] opacity-80">Missions disponibles sur Soin Direct</p>
        </div>
      </div>

      {/* Missions */}
      <div className="border border-t-0 rounded-b-xl divide-y divide-border bg-card">
        {loading ? (
          <div className="p-6 text-center text-sm text-muted-foreground">Chargement…</div>
        ) : missions.length === 0 ? (
          <div className="p-6 text-center text-sm text-muted-foreground">Aucune mission ouverte actuellement.</div>
        ) : (
          missions.map((m) => (
            <div key={m.id} className="px-4 py-3 space-y-1.5">
              <div className="flex items-start justify-between gap-2">
                <div>
                  <p className="font-medium text-foreground text-sm">{m.intitule}</p>
                  <div className="flex items-center gap-2 mt-1">
                    <Badge variant="secondary" className="text-[10px]">{m.profession_requise}</Badge>
                    {m.service && <span className="text-[11px] text-muted-foreground">{m.service}</span>}
                  </div>
                </div>
                <span className="text-sm font-bold text-primary whitespace-nowrap">{m.taux_horaire_base} €/h</span>
              </div>
              <div className="flex items-center gap-3 text-[11px] text-muted-foreground">
                <span className="flex items-center gap-1"><Clock className="h-3 w-3" />{formatDate(m.debut_le)} {formatHeure(m.debut_le)} – {formatHeure(m.fin_le)}</span>
              </div>
            </div>
          ))
        )}
        {/* CTA */}
        <div className="px-4 py-3 text-center">
          <a
            href="/inscription/soignant"
            target="_top"
            className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-semibold text-white bg-[hsl(187,75%,40%)] hover:bg-[hsl(187,75%,33%)] transition-colors"
          >
            Postuler sur Soin Direct
          </a>
        </div>
      </div>
    </div>
  );
}
