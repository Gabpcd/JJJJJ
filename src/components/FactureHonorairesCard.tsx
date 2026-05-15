import { useEffect, useState } from 'react';
import { FileText, Download, CheckCircle, Clock, AlertTriangle } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { telechargerFactureHonorairesPDF } from '@/lib/facture-honoraires-pdf';

interface Props {
  missionId: string;
  /** Contexte d'affichage — pour adapter le titre/ton. */
  viewerRole?: 'ETAB' | 'SOIGNANT' | 'ADMIN';
}

const fmt = (v: number) =>
  new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(v) || 0);

const STATUT_CONFIG: Record<string, { label: string; Icon: typeof CheckCircle; colorClass: string }> = {
  BROUILLON: { label: 'Brouillon', Icon: Clock, colorClass: 'bg-muted text-muted-foreground' },
  EMISE: { label: 'Émise', Icon: FileText, colorClass: 'bg-primary/10 text-primary border-primary/20' },
  EN_RETARD: { label: 'En retard', Icon: AlertTriangle, colorClass: 'bg-destructive/10 text-destructive border-destructive/20' },
  PAYEE: { label: 'Payée', Icon: CheckCircle, colorClass: 'bg-success/10 text-success border-success/20' },
  FACTORISEE: { label: 'Avance reçue', Icon: CheckCircle, colorClass: 'bg-success/20 text-success border-success/30' },
  ANNULEE: { label: 'Annulée', Icon: AlertTriangle, colorClass: 'bg-muted text-muted-foreground' },
};

export function FactureHonorairesCard({ missionId, viewerRole = 'ETAB' }: Props) {
  const [facture, setFacture] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [downloading, setDownloading] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from('factures_honoraires')
        .select('id, numero_facture, statut, montant_ht, montant_ttc, taux_tva, exoneration_tva, date_emission, date_echeance, date_paiement, template_version')
        .eq('mission_id', missionId)
        .order('date_emission', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!cancelled) {
        setFacture(data);
        setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [missionId]);

  if (loading) return null;
  if (!facture) return null;

  const config = STATUT_CONFIG[facture.statut] || STATUT_CONFIG.EMISE;
  const StatutIcon = config.Icon;

  const handleDownload = async () => {
    setDownloading(true);
    try {
      await telechargerFactureHonorairesPDF(facture.id);
    } finally {
      setDownloading(false);
    }
  };

  const titre =
    viewerRole === 'SOIGNANT'
      ? 'Votre facture honoraires pour cette mission'
      : viewerRole === 'ADMIN'
      ? 'Facture honoraires soignant'
      : 'Facture honoraires du soignant';

  return (
    <div className="card-base space-y-3">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <FileText className="h-4 w-4 text-primary" />
          <h3 className="font-semibold text-foreground text-sm">{titre}</h3>
        </div>
        <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full border inline-flex items-center gap-1 ${config.colorClass}`}>
          <StatutIcon className="h-3 w-3" /> {config.label}
        </span>
      </div>

      <div className="text-xs space-y-1">
        <p className="text-muted-foreground">
          Numéro : <span className="font-mono font-semibold text-foreground">{facture.numero_facture}</span>
        </p>
        <p className="text-muted-foreground">
          Montant TTC : <span className="font-semibold text-foreground">{fmt(facture.montant_ttc)}</span>
          {facture.exoneration_tva && (
            <span className="text-[10px] text-muted-foreground/80 ml-2">(exonéré TVA art. 261-4 CGI)</span>
          )}
        </p>
        <p className="text-muted-foreground">
          Émise le {format(new Date(facture.date_emission), 'd MMM yyyy', { locale: fr })}
          {facture.date_paiement && (
            <> · <span className="text-success">Payée le {format(new Date(facture.date_paiement), 'd MMM yyyy', { locale: fr })}</span></>
          )}
          {!facture.date_paiement && facture.date_echeance && (
            <> · Échéance {format(new Date(facture.date_echeance), 'd MMM yyyy', { locale: fr })}</>
          )}
        </p>
      </div>

      <BoutonY2K size="sm" variant="secondary" className="gap-1.5 text-xs" onClick={handleDownload} disabled={downloading} loading={downloading} iconeGauche={downloading ? undefined : <Download className="h-3.5 w-3.5" />}>
        {downloading ? 'Génération…' : 'Télécharger PDF'}
      </BoutonY2K>

      {viewerRole === 'ETAB' && (
        <p className="text-[10px] text-muted-foreground/70 italic">
          Facture émise par Jolene au nom du soignant (mandat de facturation — art. 289 I-2 CGI).
          Conservez-la comme preuve comptable du paiement des honoraires.
        </p>
      )}
    </div>
  );
}
