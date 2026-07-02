import { useEffect, useState } from 'react';
import { Trophy, User, RotateCcw } from 'lucide-react';
import { BoutonFavori } from '@/components/BoutonFavori';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

interface TopSoignant {
  id: string;
  prenom: string;
  nom: string;
  score_fiabilite: number;
  count: number;
  avatar_url?: string | null;
  derniere_mission_id?: string | null;
}

interface Props {
  soignants: TopSoignant[];
  etablissementId: string;
  onSelectSoignant?: (soignantId: string) => void;
}

const medalColors = ['text-warning', 'text-muted-foreground', 'text-primary'];

/** 7e-2 (F2) : datetime-local pré-rempli — mêmes horaires que la mission
 *  modèle, décalés à J+7 (modifiables). Objectif : re-booker en 2 taps. */
function versDatetimeLocal(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/* Re-booking 2 taps : nouvelle mission copiée de la dernière mission du soignant
   + proposition directe (notification CANDIDATURE_PROPOSEE). */
export function ModalRebook({ soignant, onClose }: { soignant: TopSoignant; onClose: () => void }) {
  const [debut, setDebut] = useState('');
  const [fin, setFin] = useState('');
  const [envoi, setEnvoi] = useState(false);

  // Pré-remplissage depuis la mission modèle : mêmes horaires, semaine suivante.
  useEffect(() => {
    if (!soignant.derniere_mission_id) return;
    let annule = false;
    supabase
      .from('missions')
      .select('debut_le, fin_le')
      .eq('id', soignant.derniere_mission_id)
      .maybeSingle()
      .then(({ data }) => {
        if (annule || !data?.debut_le || !data?.fin_le) return;
        const dureeMs = new Date(data.fin_le).getTime() - new Date(data.debut_le).getTime();
        const base = new Date(data.debut_le);
        const prochain = new Date();
        prochain.setDate(prochain.getDate() + 7);
        prochain.setHours(base.getHours(), base.getMinutes(), 0, 0);
        setDebut(versDatetimeLocal(prochain));
        setFin(versDatetimeLocal(new Date(prochain.getTime() + dureeMs)));
      });
    return () => { annule = true; };
  }, [soignant.derniere_mission_id]);

  const rebooker = async () => {
    if (!debut || !fin) { toast.error('Renseignez les dates.'); return; }
    setEnvoi(true);
    try {
      const { data, error } = await supabase.rpc('fn_rebooker_soignant' as any, {
        p_soignant_id: soignant.id,
        p_mission_modele_id: soignant.derniere_mission_id,
        p_debut: new Date(debut).toISOString(),
        p_fin: new Date(fin).toISOString(),
      });
      if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Re-booking impossible.'); return; }
      toast.success(`Mission créée et proposée à ${soignant.prenom} — il/elle est notifié(e) en priorité. ⭐`);
      onClose();
    } finally {
      setEnvoi(false);
    }
  };

  return (
    <Dialog open onOpenChange={v => { if (!v) onClose(); }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Re-booker {soignant.prenom} {soignant.nom}</DialogTitle>
          <DialogDescription>
            Une nouvelle mission identique à la dernière sera créée aux dates choisies et
            proposée directement à ce soignant (notifié en premier).
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3 mt-2">
          <div>
            <label className="text-xs font-medium text-foreground mb-1 block">Début</label>
            <Input type="datetime-local" value={debut} onChange={e => setDebut(e.target.value)} />
          </div>
          <div>
            <label className="text-xs font-medium text-foreground mb-1 block">Fin</label>
            <Input type="datetime-local" value={fin} onChange={e => setFin(e.target.value)} />
          </div>
        </div>
        <div className="flex justify-end gap-2 mt-4">
          <BoutonY2K variant="secondary" onClick={onClose} disabled={envoi}>Annuler</BoutonY2K>
          <BoutonY2K onClick={rebooker} disabled={envoi || !debut || !fin} loading={envoi}>
            Créer et proposer
          </BoutonY2K>
        </div>
      </DialogContent>
    </Dialog>
  );
}

export function TopSoignants({ soignants, etablissementId, onSelectSoignant }: Props) {
  const [rebook, setRebook] = useState<TopSoignant | null>(null);

  if (soignants.length === 0) return null;

  return (
    <div className="rounded-xl border border-border bg-card p-4">
      <div className="flex items-center gap-2 mb-3">
        <Trophy className="h-4 w-4 text-warning" />
        <h3 className="text-sm font-semibold text-foreground">Top soignants</h3>
      </div>
      <div className="space-y-3">
        {soignants.map((s, i) => (
          <div
            key={s.id}
            className={`flex items-center gap-3 ${onSelectSoignant ? 'cursor-pointer rounded-lg px-1 py-1 hover:bg-muted/40 transition-colors' : ''}`}
            onClick={onSelectSoignant ? () => onSelectSoignant(s.id) : undefined}
          >
            <span className={`text-lg font-bold w-6 text-center ${medalColors[i] || 'text-muted-foreground'}`}>
              {i + 1}
            </span>
            <div className="rounded-full bg-muted p-2 shrink-0">
              <User className="h-4 w-4 text-muted-foreground" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-foreground truncate">{s.prenom} {s.nom}</p>
              <div className="flex items-center gap-2">
                <span className="text-xs text-muted-foreground">{s.count} mission{s.count > 1 ? 's' : ''}</span>
                <span className="text-xs px-1.5 py-0.5 rounded-full bg-primary/10 text-primary font-medium">
                  {s.score_fiabilite}/100
                </span>
              </div>
            </div>
            <div className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
              {s.derniere_mission_id && (
                <button
                  onClick={() => setRebook(s)}
                  title="Re-booker ce soignant (nouvelle mission identique + proposition directe)"
                  className="text-xs inline-flex items-center gap-1 px-2 py-1 rounded-lg bg-primary/10 text-primary hover:bg-primary/20 transition-colors font-medium"
                >
                  <RotateCcw className="h-3 w-3" /> Re-booker
                </button>
              )}
              <BoutonFavori soignantId={s.id} etablissementId={etablissementId} />
            </div>
          </div>
        ))}
      </div>
      {rebook && <ModalRebook soignant={rebook} onClose={() => setRebook(null)} />}
    </div>
  );
}
