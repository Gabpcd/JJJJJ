import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, Download, ArrowLeft, Loader2, CheckCircle, Clock, AlertTriangle, Info, Zap } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import jsPDF from 'jspdf';
import { toast } from 'sonner';
import { MANDAT_FACTURATION_VERSION } from '@/constantes/mandatFacturation';
import { ModalCessionCreance } from '@/components/ModalCessionCreance';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(v) || 0);

const STATUT_CONFIG: Record<string, { label: string; icon: JSX.Element; color: string }> = {
  BROUILLON: { label: 'Brouillon', icon: <Clock className="h-3 w-3" />, color: 'bg-muted text-muted-foreground' },
  EMISE: { label: 'Émise', icon: <FileText className="h-3 w-3" />, color: 'bg-primary/10 text-primary' },
  EN_RETARD: { label: 'En retard', icon: <AlertTriangle className="h-3 w-3" />, color: 'bg-destructive/10 text-destructive' },
  PAYEE: { label: 'Payée', icon: <CheckCircle className="h-3 w-3" />, color: 'bg-success/10 text-success' },
  FACTORISEE: { label: 'Avance reçue', icon: <CheckCircle className="h-3 w-3" />, color: 'bg-success/20 text-success' },
  ANNULEE: { label: 'Annulée', icon: <AlertTriangle className="h-3 w-3" />, color: 'bg-muted text-muted-foreground' },
};

export default function MesFacturesHonoraires() {
  usePageTitle('Mes factures d\'honoraires');
  const navigate = useNavigate();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [factures, setFactures] = useState<any[]>([]);
  const [mandatSigne, setMandatSigne] = useState(false);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const [{ data: sgData }, { data: facts }] = await Promise.all([
        supabase.from('soignants').select('mandat_facturation_signe').eq('id', user.id).maybeSingle(),
        supabase.rpc('fn_mes_factures_honoraires' as any),
      ]);
      setMandatSigne(!!sgData?.mandat_facturation_signe);
      setFactures(facts || []);
      setLoading(false);
    })();
  }, [user]);

  const [cessionModal, setCessionModal] = useState<{ id: string; numero: string; montant: number } | null>(null);

  const ouvrirCession = (facture: any) => {
    setCessionModal({
      id: facture.id,
      numero: facture.numero_facture,
      montant: Number(facture.montant_ttc),
    });
  };

  const onCessionSuccess = () => {
    navigate('/soignant/mes-avances');
  };

  const telechargerFacturePDF = async (factureId: string) => {
    try {
      // Récupérer la facture complète + soignant + établissement
      const { data: f } = await supabase
        .from('factures_honoraires')
        .select('*')
        .eq('id', factureId)
        .maybeSingle();
      if (!f) { toast.error('Facture introuvable'); return; }

      const [{ data: sg }, { data: etab }, { data: mission }] = await Promise.all([
        supabase.from('soignants').select('prenom, nom, profession, numero_rpps, numero_adeli, email, telephone, adresse_rue, adresse_code_postal, adresse_ville').eq('id', (f as any).soignant_id).maybeSingle(),
        supabase.from('etablissements').select('nom, type, adresse_rue, adresse_code_postal, adresse_ville, siret, email_contact').eq('id', (f as any).etablissement_id).maybeSingle(),
        (f as any).mission_id ? supabase.from('missions').select('intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base').eq('id', (f as any).mission_id).maybeSingle() : Promise.resolve({ data: null }),
      ]);

      const doc = new jsPDF();
      const TEAL = { r: 23, g: 162, b: 184 };

      // Header bandeau
      doc.setFillColor(TEAL.r, TEAL.g, TEAL.b);
      doc.rect(0, 0, 210, 28, 'F');
      doc.setTextColor(255, 255, 255);
      doc.setFontSize(18);
      doc.setFont('helvetica', 'bold');
      doc.text("FACTURE D'HONORAIRES", 14, 17);
      doc.setFontSize(10);
      doc.setFont('helvetica', 'normal');
      doc.text(f.numero_facture, 14, 24);

      // Mention mandataire
      doc.setTextColor(80, 80, 80);
      doc.setFontSize(7);
      doc.text("Émise par Jolene en qualité de mandataire (Article 289 I-2 CGI)", 110, 17);
      doc.text(`Mandat version ${f.mandat_version || MANDAT_FACTURATION_VERSION}`, 110, 22);

      let y = 40;

      // Émetteur (soignant — légalement le vendeur)
      doc.setTextColor(0, 0, 0);
      doc.setFontSize(9);
      doc.setFont('helvetica', 'bold');
      doc.text('ÉMETTEUR (vendeur légal)', 14, y);
      doc.setFont('helvetica', 'normal');
      y += 5;
      if (sg) {
        doc.text(`${sg.prenom || ''} ${sg.nom || ''}`.trim(), 14, y); y += 4;
        doc.text(sg.profession || '', 14, y); y += 4;
        if (sg.numero_rpps) { doc.text(`RPPS : ${sg.numero_rpps}`, 14, y); y += 4; }
        if (sg.numero_adeli) { doc.text(`ADELI : ${sg.numero_adeli}`, 14, y); y += 4; }
        if (sg.adresse_rue) { doc.text(sg.adresse_rue, 14, y); y += 4; }
        if (sg.adresse_code_postal) { doc.text(`${sg.adresse_code_postal} ${sg.adresse_ville || ''}`, 14, y); y += 4; }
        if (sg.email) { doc.text(sg.email, 14, y); y += 4; }
      }

      // Destinataire (établissement)
      let yClient = 45;
      doc.setFont('helvetica', 'bold');
      doc.text('FACTURÉ À', 120, yClient);
      doc.setFont('helvetica', 'normal');
      yClient += 5;
      if (etab) {
        doc.text(etab.nom || '', 120, yClient); yClient += 4;
        if (etab.adresse_rue) { doc.text(etab.adresse_rue, 120, yClient); yClient += 4; }
        if (etab.adresse_code_postal) { doc.text(`${etab.adresse_code_postal} ${etab.adresse_ville || ''}`, 120, yClient); yClient += 4; }
        if (etab.siret) { doc.text(`SIRET : ${etab.siret}`, 120, yClient); yClient += 4; }
      }

      // Détails facture
      y = Math.max(y, yClient) + 8;
      doc.setDrawColor(200, 200, 200);
      doc.line(14, y, 196, y);
      y += 6;

      doc.setFontSize(9);
      const addInfo = (label: string, value: string) => {
        doc.setFont('helvetica', 'bold');
        doc.text(label, 14, y);
        doc.setFont('helvetica', 'normal');
        doc.text(value, 60, y);
        y += 5;
      };
      addInfo('Date d\'émission :', format(new Date(f.date_emission), 'dd/MM/yyyy', { locale: fr }));
      if (f.date_echeance) addInfo('Date d\'échéance :', format(new Date(f.date_echeance), 'dd/MM/yyyy', { locale: fr }));

      if (mission) {
        addInfo('Mission :', mission.intitule || '—');
        addInfo('Profession :', mission.profession_requise || '—');
        if (mission.debut_le && mission.fin_le) {
          addInfo('Période :', `${format(new Date(mission.debut_le), 'dd/MM/yyyy HH:mm', { locale: fr })} → ${format(new Date(mission.fin_le), 'dd/MM/yyyy HH:mm', { locale: fr })}`);
        }
        if (mission.duree_heures) addInfo('Heures :', `${mission.duree_heures} h`);
        if (mission.taux_horaire_base) addInfo('Taux horaire :', `${Number(mission.taux_horaire_base).toFixed(2)} €`);
      }

      // Montants
      y += 5;
      doc.setDrawColor(200, 200, 200);
      doc.line(14, y, 196, y);
      y += 8;

      doc.setFontSize(10);
      doc.setFont('helvetica', 'bold');
      doc.text('Montant HT', 14, y);
      doc.text(fmt(Number(f.montant_ht)), 196, y, { align: 'right' });
      y += 6;

      if (f.exoneration_tva) {
        doc.setFont('helvetica', 'normal');
        doc.setFontSize(8);
        doc.text("TVA non applicable — Article 261-4 du CGI (actes médicaux et paramédicaux)", 14, y);
        y += 6;
      } else {
        doc.setFont('helvetica', 'normal');
        doc.text(`TVA (${f.taux_tva}%)`, 14, y);
        doc.text(fmt(Number(f.montant_tva)), 196, y, { align: 'right' });
        y += 6;
      }

      doc.setFontSize(13);
      doc.setFont('helvetica', 'bold');
      doc.text('TOTAL TTC', 14, y);
      doc.text(fmt(Number(f.montant_ttc)), 196, y, { align: 'right' });
      y += 12;

      // Modalités paiement
      doc.setFontSize(8);
      doc.setFont('helvetica', 'normal');
      doc.text("Conditions de paiement : 30 jours date de facture.", 14, y); y += 4;
      doc.text("Pénalités de retard : 3× le taux d'intérêt légal. Indemnité forfaitaire : 40 €.", 14, y); y += 4;

      // Footer
      y = 280;
      doc.setFontSize(7);
      doc.setTextColor(120, 120, 120);
      doc.text("Facture émise par Jolene SAS pour le compte du professionnel ci-dessus, en qualité de mandataire (Article 289 I-2 du CGI).", 14, y);
      y += 3;
      doc.text("Le professionnel demeure le vendeur légal de la prestation.", 14, y);

      doc.save(`${f.numero_facture}.pdf`);
      toast.success('Facture téléchargée');
    } catch (err: any) {
      toast.error(err?.message || 'Erreur génération PDF');
    }
  };

  if (loading) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      </LayoutApp>
    );
  }

  const totalFacture = factures.reduce((s, f) => s + Number(f.montant_ttc || 0), 0);
  const totalPaye = factures.filter(f => f.statut === 'PAYEE' || f.statut === 'FACTORISEE').reduce((s, f) => s + Number(f.montant_ttc || 0), 0);
  const totalAttente = factures.filter(f => f.statut === 'EMISE' || f.statut === 'EN_RETARD').reduce((s, f) => s + Number(f.montant_ttc || 0), 0);

  return (
    <LayoutApp role="SOIGNANT">
      <div className="space-y-5">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={() => navigate(-1)}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
              <FileText className="h-5 w-5 text-primary" /> Mes factures d'honoraires
            </h1>
            <p className="text-xs text-muted-foreground">Factures émises en votre nom par Jolene (mandataire)</p>
          </div>
        </div>

        {!mandatSigne && (
          <div className="rounded-xl border-2 border-warning/30 bg-warning/5 p-4 flex items-start gap-3">
            <Info className="h-5 w-5 text-warning shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="font-semibold text-foreground">Mandat de facturation non signé</p>
              <p className="text-sm text-muted-foreground mt-0.5">
                Pour que Jolene puisse produire automatiquement vos factures d'honoraires et préparer l'accès au paiement rapide,
                vous devez d'abord signer le mandat de facturation.
              </p>
              <Button onClick={() => navigate('/soignant/mandat-facturation')} className="mt-3 gap-2" size="sm">
                Signer le mandat
              </Button>
            </div>
          </div>
        )}

        {/* KPIs */}
        <div className="grid grid-cols-3 gap-3">
          <div className="card-base">
            <p className="text-xs text-muted-foreground">Total facturé</p>
            <p className="text-xl font-bold text-foreground">{fmt(totalFacture)}</p>
          </div>
          <div className="card-base border-success/20 bg-success/5">
            <p className="text-xs text-muted-foreground">Encaissé</p>
            <p className="text-xl font-bold text-success">{fmt(totalPaye)}</p>
          </div>
          <div className="card-base border-warning/20 bg-warning/5">
            <p className="text-xs text-muted-foreground">En attente</p>
            <p className="text-xl font-bold text-warning">{fmt(totalAttente)}</p>
          </div>
        </div>

        {factures.length === 0 ? (
          <div className="card-base text-center py-10">
            <FileText className="h-12 w-12 text-muted-foreground mx-auto mb-3" />
            <p className="font-semibold text-foreground">Aucune facture d'honoraires pour le moment</p>
            <p className="text-sm text-muted-foreground mt-1">
              {mandatSigne
                ? 'Les factures apparaîtront dès que vos missions seront terminées et validées.'
                : 'Signez d\'abord le mandat de facturation pour commencer à recevoir des factures automatiques.'}
            </p>
          </div>
        ) : (
          <div className="space-y-2">
            {factures.map((f: any) => {
              const config = STATUT_CONFIG[f.statut] || STATUT_CONFIG.EMISE;
              return (
                <div key={f.id} className="card-base hover:border-primary/30 transition-colors">
                  <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="font-mono text-xs font-bold text-foreground">{f.numero_facture}</span>
                        <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full inline-flex items-center gap-1 ${config.color}`}>
                          {config.icon} {config.label}
                        </span>
                      </div>
                      <p className="text-sm text-foreground font-medium">{f.mission_intitule || '—'}</p>
                      <p className="text-xs text-muted-foreground">{f.etablissement_nom}</p>
                      <p className="text-[10px] text-muted-foreground mt-1">
                        Émise le {f.date_emission ? format(new Date(f.date_emission), 'dd/MM/yyyy', { locale: fr }) : '—'}
                        {f.date_echeance && ` · Échéance ${format(new Date(f.date_echeance), 'dd/MM/yyyy', { locale: fr })}`}
                        {f.date_paiement && ` · Payée le ${format(new Date(f.date_paiement), 'dd/MM/yyyy', { locale: fr })}`}
                      </p>
                    </div>
                    <div className="flex items-center gap-3">
                      <div className="text-right">
                        <p className="text-lg font-bold text-foreground">{fmt(f.montant_ttc)}</p>
                        <p className="text-[10px] text-muted-foreground">Exonéré TVA (art. 261-4 CGI)</p>
                      </div>
                      <div className="flex flex-col gap-1.5">
                        <Button size="sm" variant="outline" className="gap-1 text-xs" onClick={() => telechargerFacturePDF(f.id)}>
                          <Download className="h-3.5 w-3.5" /> PDF
                        </Button>
                        {(f.statut === 'EMISE' || f.statut === 'EN_RETARD') && (
                          <Button
                            size="sm"
                            className="gap-1 text-xs"
                            onClick={() => ouvrirCession(f)}
                          >
                            <Zap className="h-3 w-3" />
                            Recevoir maintenant
                          </Button>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {cessionModal && (
        <ModalCessionCreance
          open={!!cessionModal}
          onClose={() => setCessionModal(null)}
          factureId={cessionModal.id}
          numeroFacture={cessionModal.numero}
          montant={cessionModal.montant}
          onSuccess={onCessionSuccess}
        />
      )}
    </LayoutApp>
  );
}
