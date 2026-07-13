import { useState } from 'react';
import { Trash2, FileText, Clock, CheckCircle2, XCircle, Loader2 } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import type { HeureExterne } from '@/hooks/useParcoursLiberal';

interface Props {
  heures: HeureExterne[];
  onSupprimer: (id: string) => Promise<void>;
}

const STATUT_CONFIG: Record<HeureExterne['statut_validation'], { label: string; cls: string; Icon: typeof CheckCircle2 }> = {
  EN_ATTENTE: { label: 'En attente', cls: 'bg-warning/15 text-warning', Icon: Clock },
  VALIDE: { label: 'Validée', cls: 'bg-success/15 text-success', Icon: CheckCircle2 },
  REJETE: { label: 'Rejetée', cls: 'bg-destructive/15 text-destructive', Icon: XCircle },
};

export function ListeHeuresExternes({ heures, onSupprimer }: Props) {
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [openingId, setOpeningId] = useState<string | null>(null);

  if (heures.length === 0) {
    return <p className="text-sm text-muted-foreground text-center py-6">Aucune heure externe déclarée.</p>;
  }

  const ouvrirAttestation = async (id: string, path: string | null) => {
    if (!path) return;
    setOpeningId(id);
    try {
      const { data, error } = await supabase.storage
        .from(path.includes('/heures-externes/') ? 'jolene-documents' : 'attestations-heures-externes')
        .createSignedUrl(path, 3600);
      if (error || !data?.signedUrl) throw error || new Error('URL indisponible');
      window.open(data.signedUrl, '_blank', 'noopener,noreferrer');
    } catch {
      toast.error('Impossible d\'ouvrir l\'attestation.');
    } finally {
      setOpeningId(null);
    }
  };

  const supprimer = async (id: string) => {
    setDeletingId(id);
    try {
      await onSupprimer(id);
      toast.success('Déclaration supprimée.');
    } catch {
      toast.error('Impossible de supprimer.');
    } finally {
      setDeletingId(null);
    }
  };

  return (
    <div className="space-y-2">
      {heures.map(h => {
        const cfg = STATUT_CONFIG[h.statut_validation];
        const peutSupprimer = h.statut_validation === 'EN_ATTENTE';

        return (
          <div key={h.id} className="border border-border rounded-xl p-3 bg-card">
            <div className="flex items-start justify-between gap-3 flex-col sm:flex-row">
              <div className="flex-1 min-w-0 space-y-1">
                <p className="font-semibold text-foreground text-sm truncate">{h.etablissement_nom}</p>
                <p className="text-xs text-muted-foreground">
                  {format(new Date(h.date_debut), 'd MMM yyyy', { locale: fr })} → {format(new Date(h.date_fin), 'd MMM yyyy', { locale: fr })}
                </p>
                <p className="text-xs">
                  <strong className="text-foreground">{h.heures_declarees.toLocaleString('fr-FR')}h</strong>
                  {h.etablissement_type && <span className="text-muted-foreground"> · {h.etablissement_type.replace(/_/g, ' ').toLowerCase()}</span>}
                </p>
              </div>

              <div className="flex items-center gap-2 flex-wrap shrink-0">
                <span className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium ${cfg.cls}`}>
                  <cfg.Icon className="h-3 w-3" />
                  {cfg.label}
                </span>
                {h.attestation_url && (
                  <BoutonY2K
                    type="button"
                    size="sm"
                    variant="ghost"
                    onClick={() => ouvrirAttestation(h.id, h.attestation_url)}
                    disabled={openingId === h.id}
                    loading={openingId === h.id}
                    className="h-7 gap-1 text-xs"
                    iconeGauche={openingId === h.id ? undefined : <FileText className="h-3.5 w-3.5" />}
                  >
                    Voir
                  </BoutonY2K>
                )}
                {peutSupprimer && (
                  <BoutonY2K
                    type="button"
                    size="sm"
                    variant="ghost"
                    onClick={() => supprimer(h.id)}
                    disabled={deletingId === h.id}
                    loading={deletingId === h.id}
                    className="h-7 px-2 text-destructive hover:text-destructive hover:bg-destructive/10"
                    aria-label="Supprimer"
                  >
                    {deletingId !== h.id && <Trash2 className="h-3.5 w-3.5" />}
                  </BoutonY2K>
                )}
              </div>
            </div>

            {h.statut_validation === 'REJETE' && h.commentaire_validation && (
              <div className="mt-2 pt-2 border-t border-destructive/20 text-xs text-destructive">
                <strong>Motif du rejet :</strong> {h.commentaire_validation}
              </div>
            )}

            {h.statut_validation !== 'REJETE' && h.verifie_ia_le && (
              <div className="mt-2 pt-2 border-t border-border text-xs text-muted-foreground space-y-0.5">
                <p className="flex items-center gap-1">
                  <span aria-hidden>🤖</span>
                  <span>
                    Lecture IA :{' '}
                    {h.heures_extraites_ia != null
                      ? <strong className="text-foreground">{h.heures_extraites_ia.toLocaleString('fr-FR')}h lues</strong>
                      : 'heures non extraites'}
                    {h.coherence_ia === true && <span className="text-success"> · cohérent ✓</span>}
                    {h.coherence_ia === false && <span className="text-warning"> · écart à vérifier</span>}
                  </span>
                </p>
                {h.statut_validation === 'EN_ATTENTE' && h.commentaire_validation && (
                  <p>{h.commentaire_validation}</p>
                )}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
