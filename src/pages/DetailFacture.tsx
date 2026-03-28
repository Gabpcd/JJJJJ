import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Printer, CreditCard, Loader2, CheckCircle, Clock, ChevronDown, ChevronRight, Download, MapPin } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { StripeEmbeddedCheckout } from '@/components/StripeEmbeddedCheckout';
import { PaiementVirement } from '@/components/PaiementVirement';
import { format, differenceInMinutes } from 'date-fns';
import { fr } from 'date-fns/locale';
import { ENTREPRISE } from '@/constantes/entreprise';
import { capturerErreurSentry } from '@/lib/sentry';
import jsPDF from 'jspdf';
import autoTable from 'jspdf-autotable';

const STATUT_COLORS: Record<string, string> = {
  BROUILLON: 'bg-muted text-muted-foreground',
  EMISE: 'bg-primary/10 text-primary',
  VIREMENT_DECLARE: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  PAYEE: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  EN_RETARD: 'bg-destructive/10 text-destructive',
  ANNULEE: 'bg-muted text-muted-foreground line-through',
};

const STATUT_LABELS: Record<string, string> = {
  BROUILLON: 'Brouillon',
  EMISE: 'Émise',
  VIREMENT_DECLARE: 'Virement déclaré 🔍',
  PAYEE: 'Payée',
  EN_RETARD: 'En retard',
  ANNULEE: 'Annulée',
};

const formatEur = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
const formatHeure = (d: string) => format(new Date(d), 'HH:mm', { locale: fr });
const formatDateCourte = (d: string) => format(new Date(d), 'EEEE dd/MM/yyyy', { locale: fr });

function dureeEntre(debut: string, fin: string): string {
  const mins = differenceInMinutes(new Date(fin), new Date(debut));
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return m > 0 ? `${h}h${String(m).padStart(2, '0')}` : `${h}h`;
}

function PresencesJour({ presences }: { presences: any[] }) {
  if (!presences || presences.length === 0) {
    return <p className="text-xs text-muted-foreground italic py-1">Aucun pointage enregistré</p>;
  }

  // Group by date
  const parJour: Record<string, any[]> = {};
  presences.forEach(p => {
    const jour = p.pointage_arrivee_le
      ? format(new Date(p.pointage_arrivee_le), 'yyyy-MM-dd')
      : 'inconnu';
    if (!parJour[jour]) parJour[jour] = [];
    parJour[jour].push(p);
  });

  return (
    <div className="space-y-1">
      {Object.entries(parJour).sort().map(([jour, pList]) => (
        <div key={jour} className="flex flex-wrap items-center gap-x-4 gap-y-0.5 text-xs">
          <span className="font-medium text-foreground w-36 capitalize">
            {jour !== 'inconnu' ? formatDateCourte(jour + 'T00:00:00') : '—'}
          </span>
          {pList.map((p, i) => (
            <span key={p.id} className="text-muted-foreground">
              {p.pointage_arrivee_le ? formatHeure(p.pointage_arrivee_le) : '?'}
              {' → '}
              {p.pointage_depart_le ? formatHeure(p.pointage_depart_le) : '?'}
              {p.pointage_arrivee_le && p.pointage_depart_le && (
                <span className="text-foreground font-medium ml-1">
                  ({dureeEntre(p.pointage_arrivee_le, p.pointage_depart_le)})
                </span>
              )}
              {p.methode_pointage_arrivee && (
                <span className="ml-1 text-[10px] text-muted-foreground/70">
                  [{p.methode_pointage_arrivee}]
                </span>
              )}
            </span>
          ))}
          {pList.length > 1 && (
            <span className="text-[10px] text-primary font-medium">
              (pause entre shifts)
            </span>
          )}
        </div>
      ))}
    </div>
  );
}

function MissionDetail({ mission, presences }: { mission: any; presences: any[] }) {
  const [open, setOpen] = useState(false);
  const missionPresences = presences.filter(p => p.mission_id === mission.id);

  const totalMaj = (mission.montant_majoration_nuit ?? 0) +
    (mission.montant_majoration_dimanche ?? 0) +
    (mission.montant_majoration_ferie ?? 0);

  return (
    <div className="border border-border/60 rounded-lg overflow-hidden">
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center justify-between p-3 hover:bg-muted/30 transition-colors text-left"
      >
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            {open ? <ChevronDown className="h-4 w-4 text-muted-foreground shrink-0" /> : <ChevronRight className="h-4 w-4 text-muted-foreground shrink-0" />}
            <span className="font-semibold text-foreground text-sm">{mission.intitule}</span>
            <span className="text-xs text-muted-foreground">
              {mission.soignants ? `${(mission.soignants as any).prenom} ${(mission.soignants as any).nom}` : ''}
            </span>
          </div>
          <div className="flex flex-wrap gap-3 text-xs text-muted-foreground mt-1 ml-6">
            <span>{mission.profession_requise}</span>
            <span>{mission.debut_le ? format(new Date(mission.debut_le), 'dd/MM/yyyy', { locale: fr }) : '—'} → {mission.fin_le ? format(new Date(mission.fin_le), 'dd/MM/yyyy', { locale: fr }) : '—'}</span>
            <span>{mission.duree_heures ?? 0}h</span>
          </div>
        </div>
        <div className="text-right shrink-0 ml-3">
          <p className="text-sm font-bold text-primary">{formatEur(mission.montant_commission_ht ?? 0)}</p>
          <p className="text-[10px] text-muted-foreground">commission HT</p>
        </div>
      </button>

      {open && (
        <div className="border-t border-border/60 bg-muted/20 p-4 space-y-4">
          {/* Financial breakdown */}
          <div>
            <h4 className="text-xs font-bold text-foreground mb-2 uppercase tracking-wider">💶 Décomposition financière</h4>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-1.5 text-xs">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Taux horaire</span>
                <span className="font-medium">{formatEur(mission.taux_horaire_base ?? 0)}/h</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Durée</span>
                <span className="font-medium">{mission.duree_heures ?? 0}h</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Brut soignant</span>
                <span className="font-medium">{formatEur(mission.total_brut ?? 0)}</span>
              </div>
              {(mission.montant_majoration_nuit ?? 0) > 0 && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">🌙 Majoration nuit</span>
                  <span className="font-medium">{formatEur(mission.montant_majoration_nuit)}</span>
                </div>
              )}
              {(mission.montant_majoration_dimanche ?? 0) > 0 && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">☀️ Majoration dimanche</span>
                  <span className="font-medium">{formatEur(mission.montant_majoration_dimanche)}</span>
                </div>
              )}
              {(mission.montant_majoration_ferie ?? 0) > 0 && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">🎌 Majoration férié</span>
                  <span className="font-medium">{formatEur(mission.montant_majoration_ferie)}</span>
                </div>
              )}
              {(mission.montant_ifm ?? 0) > 0 && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">IFM ({(mission.taux_ifm ?? 10)}%)</span>
                  <span className="font-medium">{formatEur(mission.montant_ifm)}</span>
                </div>
              )}
              {(mission.montant_icp ?? 0) > 0 && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">ICP ({(mission.taux_icp ?? 10)}%)</span>
                  <span className="font-medium">{formatEur(mission.montant_icp)}</span>
                </div>
              )}
            </div>
          </div>

          {/* Commission detail */}
          <div>
            <h4 className="text-xs font-bold text-foreground mb-2 uppercase tracking-wider">🏷️ Commission Jolene</h4>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-1.5 text-xs">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Taux commission</span>
                <span className="font-medium">{mission.taux_commission ?? 15}%</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Commission HT</span>
                <span className="font-semibold text-primary">{formatEur(mission.montant_commission_ht ?? 0)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">TVA commission</span>
                <span className="font-medium">{formatEur(mission.montant_commission_tva ?? 0)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Commission TTC</span>
                <span className="font-bold text-foreground">{formatEur(mission.montant_commission_ttc ?? 0)}</span>
              </div>
            </div>
          </div>

          {/* Pointages */}
          <div>
            <h4 className="text-xs font-bold text-foreground mb-2 uppercase tracking-wider">⏱️ Pointages détaillés</h4>
            <PresencesJour presences={missionPresences} />
          </div>
        </div>
      )}
    </div>
  );
}

export default function DetailFacture() {
  usePageTitle('Détail facture');
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [facture, setFacture] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [presences, setPresences] = useState<any[]>([]);
  const [etab, setEtab] = useState<any>(null);
  const [showCheckout, setShowCheckout] = useState(false);
  const [generatingPdf, setGeneratingPdf] = useState(false);

  const charger = async () => {
    if (!user || !id) return;
    const [resF, resM, resE] = await Promise.all([
      supabase.from('factures').select('id, numero_facture, montant_ht, montant_tva, montant_ttc, taux_tva, nombre_missions, statut, date_emission, date_echeance, date_paiement, periode_debut, periode_fin, mode_paiement, stripe_hosted_url, chorus_pro_statut, est_secteur_public, etablissement_id, virement_reference').eq('id', id).eq('etablissement_id', user.id).single(),
      supabase.from('missions')
        .select('id, intitule, debut_le, fin_le, duree_heures, taux_horaire_base, total_brut, profession_requise, soignant_assigne_id, soignants(nom, prenom), montant_commission_ht, montant_commission_tva, montant_commission_ttc, taux_commission, montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie, montant_ifm, montant_icp, taux_ifm, taux_icp, statut')
        .eq('etablissement_id', user.id)
        .eq('commission_facturee', true)
        .eq('statut', 'TERMINEE')
        .order('debut_le', { ascending: true }),
      supabase.from('etablissements').select('nom, siret, adresse_rue, adresse_ville, adresse_code_postal, taux_commission_negocie, paliers_commission(nom)').eq('id', user.id).single(),
    ]);

    if (resF.data) setFacture(resF.data);
    if (resM.data && resF.data) {
      // Filter missions by facture period
      const fData = resF.data as any;
      let filteredMissions = resM.data;
      if (fData.periode_debut && fData.periode_fin) {
        const pdStart = new Date(fData.periode_debut).getTime();
        const pdEnd = new Date(fData.periode_fin).getTime();
        filteredMissions = resM.data.filter((m: any) => {
          if (!m.debut_le) return false;
          const mDate = new Date(m.debut_le).getTime();
          return mDate >= pdStart && mDate <= pdEnd;
        });
      }
      setMissions(filteredMissions);
      // Fetch presences for all missions
      const missionIds = resM.data.map((m: any) => m.id);
      if (missionIds.length > 0) {
        const { data: presData } = await supabase.from('presences')
          .select('id, mission_id, pointage_arrivee_le, pointage_depart_le, methode_pointage_arrivee, methode_pointage_depart, valide_par_etablissement')
          .in('mission_id', missionIds)
          .order('pointage_arrivee_le', { ascending: true });
        if (presData) setPresences(presData);
      }
    }
    if (resE.data) setEtab(resE.data);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user, id]);

  const genererPDF = () => {
    if (!facture || !etab) return;
    setGeneratingPdf(true);

    try {
      const doc = new jsPDF();
      const pw = doc.internal.pageSize.getWidth();

      // Header
      doc.setFillColor(23, 162, 184);
      doc.rect(0, 0, pw, 32, 'F');
      doc.setTextColor(255, 255, 255);
      doc.setFontSize(18);
      doc.text('FACTURE', 14, 16);
      doc.setFontSize(11);
      doc.text(facture.numero_facture || '', 14, 26);
      doc.setFontSize(9);
      doc.text(`Statut : ${STATUT_LABELS[facture.statut] ?? facture.statut}`, pw - 14, 16, { align: 'right' });

      // Company & Client
      doc.setTextColor(0, 0, 0);
      let y = 42;
      doc.setFontSize(10);
      doc.setFont('helvetica', 'bold');
      doc.text(ENTREPRISE.nom, 14, y);
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(8);
      doc.text('Plateforme de mise en relation soignants', 14, y + 5);

      doc.setFontSize(9);
      doc.text('Facturé à :', pw - 80, y);
      doc.setFont('helvetica', 'bold');
      doc.text(etab.nom, pw - 80, y + 5);
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(8);
      doc.text(`${etab.adresse_rue}`, pw - 80, y + 10);
      doc.text(`${etab.adresse_code_postal} ${etab.adresse_ville}`, pw - 80, y + 15);
      doc.text(`SIRET : ${etab.siret}`, pw - 80, y + 20);

      y += 30;
      doc.setFontSize(8);
      const addMeta = (label: string, value: string) => {
        doc.text(`${label} : ${value}`, 14, y);
        y += 5;
      };
      addMeta('Date d\'émission', facture.date_emission ? format(new Date(facture.date_emission), 'dd/MM/yyyy') : '—');
      addMeta('Échéance', facture.date_echeance ? format(new Date(facture.date_echeance), 'dd/MM/yyyy') : '—');
      addMeta('Commission', `${etab.taux_commission_negocie ?? 15}% (${etab.paliers_commission?.nom ?? 'Standard'})`);

      y += 5;

      // Missions table
      doc.setFontSize(10);
      doc.setFont('helvetica', 'bold');
      doc.text('Détail des missions', 14, y);
      y += 3;

      const tableData = missions.map(m => {
        const sg = m.soignants as any;
        const totalMaj = (m.montant_majoration_nuit ?? 0) + (m.montant_majoration_dimanche ?? 0) + (m.montant_majoration_ferie ?? 0);
        return [
          m.intitule?.substring(0, 25) || '—',
          sg ? `${sg.prenom} ${sg.nom}` : '—',
          m.debut_le ? format(new Date(m.debut_le), 'dd/MM') + ' → ' + (m.fin_le ? format(new Date(m.fin_le), 'dd/MM') : '') : '—',
          `${m.duree_heures ?? 0}h`,
          formatEur(m.taux_horaire_base ?? 0),
          formatEur(m.total_brut ?? 0),
          totalMaj > 0 ? formatEur(totalMaj) : '—',
          formatEur(m.montant_commission_ht ?? 0),
        ];
      });

      autoTable(doc, {
        startY: y,
        head: [['Mission', 'Soignant', 'Dates', 'Heures', 'Taux/h', 'Brut', 'Maj.', 'Com. HT']],
        body: tableData,
        styles: { fontSize: 7, cellPadding: 2 },
        headStyles: { fillColor: [23, 162, 184], textColor: 255, fontStyle: 'bold' },
        columnStyles: {
          0: { cellWidth: 32 },
          4: { halign: 'right' },
          5: { halign: 'right' },
          6: { halign: 'right' },
          7: { halign: 'right', fontStyle: 'bold' },
        },
        margin: { left: 14, right: 14 },
      });

      y = (doc as any).lastAutoTable?.finalY ?? y + 30;
      y += 5;

      // Pointages detail per mission
      missions.forEach(m => {
        const mPresences = presences.filter(p => p.mission_id === m.id);
        if (mPresences.length === 0) return;

        if (y > 260) { doc.addPage(); y = 20; }

        doc.setFontSize(8);
        doc.setFont('helvetica', 'bold');
        doc.text(`⏱ Pointages — ${m.intitule}`, 14, y);
        y += 4;

        const presData = mPresences.map(p => [
          p.pointage_arrivee_le ? format(new Date(p.pointage_arrivee_le), 'dd/MM/yyyy') : '—',
          p.pointage_arrivee_le ? formatHeure(p.pointage_arrivee_le) : '—',
          p.pointage_depart_le ? formatHeure(p.pointage_depart_le) : '—',
          p.pointage_arrivee_le && p.pointage_depart_le ? dureeEntre(p.pointage_arrivee_le, p.pointage_depart_le) : '—',
          p.methode_pointage_arrivee ?? '—',
          p.valide_par_etablissement ? '✓' : '—',
        ]);

        autoTable(doc, {
          startY: y,
          head: [['Date', 'Arrivée', 'Départ', 'Durée', 'Méthode', 'Validé']],
          body: presData,
          styles: { fontSize: 6.5, cellPadding: 1.5 },
          headStyles: { fillColor: [240, 240, 240], textColor: [60, 60, 60], fontStyle: 'bold' },
          margin: { left: 20, right: 14 },
        });

        y = (doc as any).lastAutoTable?.finalY ?? y + 15;
        y += 4;
      });

      // Totals
      if (y > 240) { doc.addPage(); y = 20; }
      y += 5;
      doc.setDrawColor(200, 200, 200);
      doc.line(pw - 100, y, pw - 14, y);
      y += 8;
      doc.setFontSize(9);
      doc.setFont('helvetica', 'normal');
      doc.text('Total HT', pw - 100, y);
      doc.text(formatEur(facture.montant_ht), pw - 14, y, { align: 'right' });
      y += 6;
      doc.text(`TVA (${facture.taux_tva ?? 20}%)`, pw - 100, y);
      doc.text(formatEur(facture.montant_tva), pw - 14, y, { align: 'right' });
      y += 7;
      doc.setFont('helvetica', 'bold');
      doc.setFontSize(12);
      doc.text('Total TTC', pw - 100, y);
      doc.text(formatEur(facture.montant_ttc), pw - 14, y, { align: 'right' });

      // Footer
      const ph = doc.internal.pageSize.getHeight();
      doc.setFontSize(6.5);
      doc.setFont('helvetica', 'normal');
      doc.setTextColor(140, 140, 140);
      doc.text(`${ENTREPRISE.nom} — Facture détaillée générée le ${format(new Date(), 'dd/MM/yyyy à HH:mm')}`, pw / 2, ph - 8, { align: 'center' });

      doc.save(`facture_${facture.numero_facture}.pdf`);
      afficherNotification({ type: 'succes', message: 'PDF téléchargé' });
    } catch (err) {
      capturerErreurSentry(err, 'DetailFacture', 'generer_pdf');
      afficherNotification({ type: 'erreur', message: 'Erreur lors de la génération du PDF' });
    } finally {
      setGeneratingPdf(false);
    }
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;
  if (!facture) return <LayoutApp role="ADMIN_ETABLISSEMENT"><p className="text-center text-muted-foreground py-12">Facture introuvable.</p></LayoutApp>;

  const canPay = facture.statut === 'EMISE' || facture.statut === 'EN_RETARD';

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      {/* Header */}
      <div className="flex items-center justify-between mb-6 no-print">
        <button onClick={() => navigate('/etablissement/facturation')} className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors">
          <ArrowLeft className="h-4 w-4" /> Retour
        </button>
        <div className="flex flex-wrap gap-2">
          <button onClick={genererPDF} disabled={generatingPdf} className="btn-secondary text-sm flex items-center gap-1.5 disabled:opacity-50">
            {generatingPdf ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
            PDF complet
          </button>
          <button onClick={() => window.print()} className="btn-secondary text-sm flex items-center gap-1.5">
            <Printer className="h-4 w-4" /> Imprimer
          </button>
          {canPay && !facture.est_secteur_public && (
            <button onClick={() => setShowCheckout(true)} className="btn-primary text-sm flex items-center gap-1.5">
              <CreditCard className="h-4 w-4" /> Payer par carte
            </button>
          )}
        </div>
      </div>

      {/* Invoice card */}
      <div className="card-base print-invoice print-full">
        {/* Header facture */}
        <div className="flex flex-col sm:flex-row justify-between gap-4 mb-8 pb-6 border-b border-border">
          <div>
            <h1 className="text-2xl font-black text-foreground">FACTURE</h1>
            <p className="text-lg font-bold text-primary mt-1">{facture.numero_facture}</p>
            <p className="text-sm text-muted-foreground mt-2">
              Émise le {facture.date_emission ? format(new Date(facture.date_emission), 'dd MMMM yyyy', { locale: fr }) : '—'}
            </p>
            {facture.date_echeance && (
              <p className="text-sm text-muted-foreground">
                Échéance : {format(new Date(facture.date_echeance), 'dd MMMM yyyy', { locale: fr })}
              </p>
          )}
          {facture.mode_paiement && (
            <span className="text-xs text-muted-foreground ml-2">
              Mode : {facture.mode_paiement === 'STRIPE' ? 'Carte bancaire' : facture.mode_paiement === 'VIREMENT' ? 'Virement bancaire' : facture.mode_paiement === 'SEPA' ? 'Prélèvement SEPA' : facture.mode_paiement}
            </span>
          )}
          </div>
          <div className="text-right">
            <p className="text-sm font-bold text-foreground">{ENTREPRISE.nom}</p>
            <p className="text-xs text-muted-foreground">Plateforme de mise en relation</p>
            <p className="text-xs text-muted-foreground mt-2">Facturé à :</p>
            <p className="text-sm font-semibold text-foreground">{etab?.nom}</p>
            <p className="text-xs text-muted-foreground">{etab?.adresse_rue}</p>
            <p className="text-xs text-muted-foreground">{etab?.adresse_code_postal} {etab?.adresse_ville}</p>
            <p className="text-xs text-muted-foreground">SIRET : {etab?.siret}</p>
          </div>
        </div>

        {/* Status */}
        <div className="mb-6 flex items-center gap-2">
          <span className="text-sm text-muted-foreground">Statut :</span>
          <span className={`px-3 py-1 rounded-full text-xs font-bold ${STATUT_COLORS[facture.statut] ?? STATUT_COLORS.BROUILLON}`}>
            {STATUT_LABELS[facture.statut] ?? facture.statut}
          </span>
          {etab?.paliers_commission && (
            <span className="text-xs text-muted-foreground ml-2">
              Commission {(etab as any).paliers_commission.nom} ({etab.taux_commission_negocie ?? 15}%)
            </span>
          )}
        </div>

        {facture.statut === 'VIREMENT_DECLARE' && (
          <div className="mb-6 flex items-center gap-2 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-700/30 rounded-xl p-3">
            <Clock className="h-4 w-4 text-amber-600 dark:text-amber-400 shrink-0" />
            <div>
              <p className="text-sm font-medium text-amber-700 dark:text-amber-300">Virement déclaré — en attente de vérification</p>
              {facture.virement_reference && (
                <p className="text-xs text-amber-600/80 dark:text-amber-400/80">Référence : {facture.virement_reference}</p>
              )}
            </div>
          </div>
        )}

        {/* Missions detail */}
        <h2 className="text-sm font-bold text-foreground mb-3 uppercase tracking-wider">
          📋 Missions facturées ({missions.length})
        </h2>
        <div className="space-y-2 mb-6">
          {missions.map(m => (
            <MissionDetail key={m.id} mission={m} presences={presences} />
          ))}
        </div>

        {/* Totals */}
        <div className="border-t-2 border-border pt-4 space-y-2 max-w-xs ml-auto">
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Total HT</span>
            <span className="font-medium text-foreground">{formatEur(facture.montant_ht ?? 0)}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">TVA ({facture.taux_tva ?? 20}%)</span>
            <span className="font-medium text-foreground">{formatEur(facture.montant_tva ?? 0)}</span>
          </div>
          <div className="flex justify-between text-lg font-bold border-t border-border pt-2">
            <span className="text-foreground">Total TTC</span>
            <span className="text-primary">{formatEur(facture.montant_ttc ?? 0)}</span>
          </div>
        </div>

        {/* Payment info */}
        {facture.statut === 'PAYEE' && facture.date_paiement && (
          <div className="mt-6 flex items-center gap-2 bg-success/10 border border-success/20 rounded-xl p-3">
            <CheckCircle className="h-4 w-4 text-success shrink-0" />
            <p className="text-sm text-success">
              Payée le {format(new Date(facture.date_paiement), 'dd MMMM yyyy', { locale: fr })}
            </p>
          </div>
        )}

        {/* Payment actions for unpaid */}
        {canPay && !facture.est_secteur_public && (
          <div className="mt-6 no-print">
            <PaiementVirement facture={facture} onUpdate={charger} />
          </div>
        )}

        {/* Footer */}
        <div className="mt-8 pt-4 border-t border-border text-[10px] text-muted-foreground text-center">
          <p>{ENTREPRISE.nom} — Plateforme de mise en relation soignants-établissements</p>
          <p>Facture détaillée — Commission sur missions terminées</p>
        </div>
      </div>

      {showCheckout && facture && (
        <StripeEmbeddedCheckout
          factureId={facture.id}
          open={showCheckout}
          onClose={() => setShowCheckout(false)}
          onComplete={() => { setShowCheckout(false); charger(); }}
        />
      )}
    </LayoutApp>
  );
}
