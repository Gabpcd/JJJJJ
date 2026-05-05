import { useState } from 'react';
import { Landmark, Loader2, ExternalLink, RefreshCw, Copy, CheckCircle, ChevronDown, ChevronUp, FileText, Clock, AlertTriangle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { capturerErreurSentry } from '@/lib/sentry';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { toast } from 'sonner';

interface Props {
  facture: any;
  onUpdate: () => void;
}

const CHORUS_STATUT_STYLES: Record<string, string> = {
  NON_APPLICABLE: 'bg-muted text-muted-foreground',
  A_DEPOSER: 'bg-warning/10 text-warning',
  DEPOSEE: 'bg-primary/10 text-primary',
  ACCEPTEE: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  REJETEE: 'bg-destructive/10 text-destructive',
  MISE_EN_PAIEMENT: 'bg-green-200 text-green-800 dark:bg-green-900/50 dark:text-green-300',
};

const CHORUS_STATUT_LABELS: Record<string, string> = {
  NON_APPLICABLE: '—',
  A_DEPOSER: 'À déposer',
  DEPOSEE: 'Déposée',
  ACCEPTEE: 'Acceptée',
  REJETEE: 'Rejetée',
  MISE_EN_PAIEMENT: 'Mise en paiement',
};

const ETAPES_DEPOT = [
  {
    num: 1,
    titre: 'Connectez-vous à Chorus Pro',
    desc: 'Rendez-vous sur chorus-pro.gouv.fr avec vos identifiants.',
  },
  {
    num: 2,
    titre: 'Créez une facture',
    desc: 'Menu "Factures émises" → "Déposer facture" → Saisissez les informations ci-dessous.',
  },
  {
    num: 3,
    titre: 'Renseignez les références',
    desc: 'Copiez le numéro de facture et le montant TTC indiqués ci-dessous.',
  },
  {
    num: 4,
    titre: 'Déposez et notez le numéro de flux',
    desc: 'Après validation, Chorus Pro vous attribue un numéro de flux. Saisissez-le ici pour le suivi.',
  },
];

function copier(texte: string, label: string) {
  navigator.clipboard.writeText(texte);
  toast.success(`${label} copié`);
}

export function FactureChorus({ facture, onUpdate }: Props) {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(false);
  const [checkingStatus, setCheckingStatus] = useState(false);
  const [open, setOpen] = useState(false);
  const [guideOpen, setGuideOpen] = useState(false);
  const [numeroFlux, setNumeroFlux] = useState('');
  const [confirmRejet, setConfirmRejet] = useState(false);

  const statut = facture.chorus_pro_statut || 'A_DEPOSER';

  const marquerDeposee = async () => {
    if (!numeroFlux.trim()) {
      toast.error('Saisissez le numéro de flux Chorus Pro');
      return;
    }
    setLoading(true);
    try {
      const now = new Date().toISOString();
      const { error } = await supabase
        .from('factures')
        .update({
          chorus_pro_statut: 'DEPOSEE',
          chorus_pro_deposee_le: now,
          chorus_pro_date_depot: now,
          chorus_pro_numero_flux: numeroFlux.trim(),
        } as any)
        .eq('id', facture.id);
      if (error) throw error;
      afficherNotification({ type: 'succes', message: 'Facture marquée comme déposée sur Chorus Pro' });
      setOpen(false);
      setNumeroFlux('');
      onUpdate();
    } catch (err: any) {
      capturerErreurSentry(err, 'FactureChorus', 'marquer_deposee');
      afficherNotification({ type: 'erreur', message: 'Erreur lors de la mise à jour' });
    } finally {
      setLoading(false);
    }
  };

  const mettreAJourStatut = async (nouveauStatut: string) => {
    setCheckingStatus(true);
    try {
      const updates: Record<string, any> = { chorus_pro_statut: nouveauStatut };
      if (nouveauStatut === 'ACCEPTEE') {
        updates.chorus_pro_date_acceptation = new Date().toISOString();
      }
      if (nouveauStatut === 'MISE_EN_PAIEMENT') {
        updates.statut = 'PAYEE';
        updates.date_paiement = new Date().toISOString();
        updates.methode_paiement = 'CHORUS_PRO';
      }
      const { error } = await supabase
        .from('factures')
        .update(updates as any)
        .eq('id', facture.id);
      if (error) throw error;
      afficherNotification({
        type: 'succes',
        message: `Statut mis à jour : ${CHORUS_STATUT_LABELS[nouveauStatut]}`,
      });
      setConfirmRejet(false);
      onUpdate();
    } catch (err: any) {
      capturerErreurSentry(err, 'FactureChorus', 'maj_statut');
      afficherNotification({ type: 'erreur', message: 'Erreur lors de la mise à jour' });
    } finally {
      setCheckingStatus(false);
    }
  };

  // --- Statuts finaux ou en cours ---

  if (statut === 'MISE_EN_PAIEMENT') {
    return (
      <div className="flex items-center gap-2 flex-wrap">
        <span className={`px-2.5 py-1 rounded-full text-xs font-bold ${CHORUS_STATUT_STYLES.MISE_EN_PAIEMENT}`}>
          <Landmark className="h-3 w-3 inline mr-1" />
          Mise en paiement
        </span>
        <span className="text-xs text-muted-foreground">Paiement en cours de traitement par le Trésor public</span>
      </div>
    );
  }

  if (statut === 'ACCEPTEE') {
    return (
      <div className="space-y-2">
        <div className="flex items-center gap-2 flex-wrap">
          <span className={`px-2.5 py-1 rounded-full text-xs font-bold ${CHORUS_STATUT_STYLES.ACCEPTEE}`}>
            <CheckCircle className="h-3 w-3 inline mr-1" />
            Acceptée par l'ordonnateur
          </span>
        </div>
        <p className="text-xs text-muted-foreground">
          La facture a été validée. Le paiement interviendra sous 30 jours (délai légal).
        </p>
        <div className="flex gap-2">
          <Button size="sm" variant="outline" onClick={() => mettreAJourStatut('MISE_EN_PAIEMENT')} disabled={checkingStatus} className="text-xs gap-1">
            {checkingStatus ? <Loader2 className="h-3 w-3 animate-spin" /> : <CheckCircle className="h-3 w-3" />}
            Marquer "Mise en paiement"
          </Button>
        </div>
      </div>
    );
  }

  if (statut === 'DEPOSEE') {
    return (
      <div className="space-y-3">
        <div className="flex items-center gap-2 flex-wrap">
          <span className={`px-2.5 py-1 rounded-full text-xs font-bold ${CHORUS_STATUT_STYLES.DEPOSEE}`}>
            <Landmark className="h-3 w-3 inline mr-1" />
            Déposée sur Chorus Pro
          </span>
          {facture.chorus_pro_numero_flux && (
            <span className="text-xs text-muted-foreground">
              Flux : {facture.chorus_pro_numero_flux}
            </span>
          )}
        </div>
        <p className="text-xs text-muted-foreground">
          Vérifiez le statut sur Chorus Pro et mettez à jour ci-dessous.
        </p>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" variant="outline" onClick={() => mettreAJourStatut('ACCEPTEE')} disabled={checkingStatus} className="text-xs gap-1 border-green-300 text-green-700 hover:bg-green-50">
            <CheckCircle className="h-3 w-3" /> Acceptée
          </Button>
          <Button size="sm" variant="outline" onClick={() => setConfirmRejet(true)} disabled={checkingStatus} className="text-xs gap-1 border-destructive/30 text-destructive hover:bg-destructive/5">
            <AlertTriangle className="h-3 w-3" /> Rejetée
          </Button>
          <a href="https://chorus-pro.gouv.fr" target="_blank" rel="noopener noreferrer">
            <Button size="sm" variant="ghost" className="text-xs gap-1">
              <ExternalLink className="h-3 w-3" /> Vérifier sur Chorus
            </Button>
          </a>
        </div>
        {confirmRejet && (
          <div className="rounded-lg border border-destructive/20 bg-destructive/5 p-3 space-y-2">
            <p className="text-xs text-destructive font-medium">Confirmer le rejet ? La facture pourra être redéposée.</p>
            <div className="flex gap-2">
              <Button size="sm" variant="destructive" onClick={() => mettreAJourStatut('REJETEE')} disabled={checkingStatus} className="text-xs">
                {checkingStatus ? <Loader2 className="h-3 w-3 animate-spin" /> : null} Confirmer le rejet
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setConfirmRejet(false)} className="text-xs">Annuler</Button>
            </div>
          </div>
        )}
      </div>
    );
  }

  if (statut === 'REJETEE') {
    return (
      <div className="space-y-2">
        <span className={`px-2.5 py-1 rounded-full text-xs font-bold ${CHORUS_STATUT_STYLES.REJETEE}`}>
          <AlertTriangle className="h-3 w-3 inline mr-1" />
          Rejetée
        </span>
        <p className="text-xs text-muted-foreground">
          La facture a été rejetée par Chorus Pro. Vous pouvez la redéposer après correction.
        </p>
        <Button size="sm" variant="outline" onClick={() => setOpen(true)} className="text-xs gap-1">
          <Landmark className="h-3.5 w-3.5" /> Redéposer
        </Button>
      </div>
    );
  }

  // --- Statut A_DEPOSER : parcours de dépôt manuel ---

  if (!open) {
    return (
      <Button size="sm" variant="outline" onClick={() => setOpen(true)} className="text-xs gap-1">
        <Landmark className="h-3.5 w-3.5" /> Déposer sur Chorus Pro
      </Button>
    );
  }

  return (
    <div className="w-full space-y-4 mt-2">
      {/* Bannière info */}
      <div className="rounded-lg bg-primary/5 border border-primary/20 p-3">
        <p className="text-xs text-primary font-medium flex items-center gap-1.5">
          <Landmark className="h-4 w-4 shrink-0" />
          Dépôt manuel sur Chorus Pro (factures commission)
        </p>
      </div>

      {/* Informations à copier */}
      <div className="rounded-lg border border-border bg-muted/30 p-3 space-y-2">
        <p className="text-xs font-semibold text-foreground">Informations à reporter sur Chorus Pro :</p>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <div className="flex items-center justify-between bg-background rounded-md px-3 py-2 border border-border">
            <div>
              <p className="text-[10px] text-muted-foreground">N° facture</p>
              <p className="text-sm font-mono font-bold text-foreground">{facture.numero_facture}</p>
            </div>
            <button onClick={() => copier(facture.numero_facture, 'N° facture')} className="p-1 rounded hover:bg-muted" title="Copier">
              <Copy className="h-3.5 w-3.5 text-muted-foreground" />
            </button>
          </div>
          <div className="flex items-center justify-between bg-background rounded-md px-3 py-2 border border-border">
            <div>
              <p className="text-[10px] text-muted-foreground">Montant TTC</p>
              <p className="text-sm font-mono font-bold text-foreground">{facture.montant_ttc?.toFixed(2)} €</p>
            </div>
            <button onClick={() => copier(facture.montant_ttc?.toFixed(2) ?? '', 'Montant')} className="p-1 rounded hover:bg-muted" title="Copier">
              <Copy className="h-3.5 w-3.5 text-muted-foreground" />
            </button>
          </div>
        </div>
        {facture.date_emission && (
          <p className="text-[10px] text-muted-foreground">
            Date d'émission : {new Date(facture.date_emission).toLocaleDateString('fr-FR')}
          </p>
        )}
      </div>

      {/* Guide pas-à-pas */}
      <div className="rounded-lg border border-border">
        <button
          onClick={() => setGuideOpen(!guideOpen)}
          className="w-full flex items-center justify-between px-3 py-2.5 text-xs font-semibold text-foreground hover:bg-muted/50 transition-colors rounded-lg"
        >
          <span className="flex items-center gap-1.5">
            <FileText className="h-3.5 w-3.5 text-primary" />
            Guide de dépôt pas-à-pas
          </span>
          {guideOpen ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
        </button>
        {guideOpen && (
          <div className="px-3 pb-3 space-y-2">
            {ETAPES_DEPOT.map((e) => (
              <div key={e.num} className="flex gap-3 items-start">
                <div className="flex-shrink-0 w-6 h-6 rounded-full bg-primary/10 text-primary flex items-center justify-center text-xs font-bold">
                  {e.num}
                </div>
                <div>
                  <p className="text-xs font-semibold text-foreground">{e.titre}</p>
                  <p className="text-[11px] text-muted-foreground">{e.desc}</p>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Lien direct Chorus Pro */}
      <a href="https://chorus-pro.gouv.fr" target="_blank" rel="noopener noreferrer" className="block">
        <Button variant="default" size="sm" className="w-full gap-2 text-xs">
          <ExternalLink className="h-3.5 w-3.5" />
          Ouvrir Chorus Pro
        </Button>
      </a>

      {/* Saisie numéro de flux */}
      <div className="rounded-lg border border-border bg-background p-3 space-y-2">
        <p className="text-xs font-semibold text-foreground flex items-center gap-1.5">
          <Clock className="h-3.5 w-3.5 text-primary" />
          J'ai déposé la facture — saisir le numéro de flux
        </p>
        <div className="flex gap-2">
          <Input
            value={numeroFlux}
            onChange={(e) => setNumeroFlux(e.target.value)}
            placeholder="Ex: 2026-FL-001234"
            className="text-xs h-8"
          />
          <Button size="sm" onClick={marquerDeposee} disabled={loading || !numeroFlux.trim()} className="text-xs gap-1 shrink-0">
            {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <CheckCircle className="h-3.5 w-3.5" />}
            Valider
          </Button>
        </div>
        <p className="text-[10px] text-muted-foreground">
          Le numéro de flux est attribué par Chorus Pro après le dépôt. Il permet le suivi.
        </p>
      </div>

      {/* Délai estimé */}
      <div className="flex items-start gap-2 p-2 rounded-lg bg-muted/30">
        <Clock className="h-3.5 w-3.5 text-muted-foreground mt-0.5 shrink-0" />
        <p className="text-[11px] text-muted-foreground">
          <strong>Délai estimé :</strong> 30 à 60 jours après acceptation par l'ordonnateur (délai légal secteur public).
        </p>
      </div>

      <Button size="sm" variant="ghost" onClick={() => setOpen(false)} className="text-xs w-full">
        Fermer
      </Button>
    </div>
  );
}

export function ChorusStatutBadge({ statut }: { statut: string }) {
  if (!statut || statut === 'NON_APPLICABLE') return null;
  return (
    <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold inline-flex items-center gap-1 ${CHORUS_STATUT_STYLES[statut] ?? CHORUS_STATUT_STYLES.A_DEPOSER}`}>
      <Landmark className="h-3 w-3" />
      {CHORUS_STATUT_LABELS[statut] ?? statut}
    </span>
  );
}
