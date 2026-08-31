import { useEffect, useState } from 'react';
import { telechargerOuPartagerPdf } from '@/lib/telechargement';
import { useParams, useNavigate } from 'react-router-dom';
import { jsPDF } from 'jspdf';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { ArrowLeft, Download, Loader2 } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { CertificatSignature } from '@/components/CertificatSignature';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { usePageTitle } from '@/hooks/usePageTitle';
import { UserRole } from '@/lib/types';

interface SignatureRow {
  id: string;
  signataire_user_id: string;
  signataire_role: 'soignant' | 'etablissement';
  signe_a: string | null;
  ip_signature: string | null;
  user_agent: string | null;
  hash_document: string | null;
  otp_valide_a: string | null;
  psc_session_active: boolean | null;
  rpps_verifie: boolean | null;
  traits_identite_verifies: boolean | null;
  statut_signature: string;
  cree_le: string;
}

/**
 * Page dédiée /contrat/:id/certificat — affichage détaillé du certificat de
 * signature électronique Jolene + export PDF jsPDF.
 *
 * Accessible aux parties au contrat (soignant + étab) et aux admins
 * plateforme. RLS appliquée via les policies signatures_contrats (PR 4
 * Sprint 1).
 */
export default function CertificatSignaturePage() {
  usePageTitle('Certificat de signature');
  const { id: contratId } = useParams<{ id: string }>();
  const { user } = useAuth();
  const { role: serverRole } = useRole();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const role: UserRole = serverRole === 'INCONNU'
      ? 'SOIGNANT'
      : serverRole;

  const [loading, setLoading] = useState(true);
  const [contrat, setContrat] = useState<any>(null);
  const [exporting, setExporting] = useState(false);

  useEffect(() => {
    if (!contratId || !user) return;
    (async () => {
      const { data } = await supabase
        .from('contrats_mission')
        .select('id, numero_contrat, type_contrat, statut, soignant_id, etablissement_id, signature_soignant_le, signature_etablissement_le, hash_document, storage_path' as any)
        .eq('id', contratId)
        .maybeSingle();
      setContrat(data as any);
      setLoading(false);
    })();
  }, [contratId, user]);

  async function exporterPdf() {
    if (!contratId || !contrat) return;
    setExporting(true);
    try {
      const { data: sigs } = await supabase
        .from('signatures_contrats' as any)
        .select('id, signataire_role, signe_a, ip_signature, user_agent, hash_document, otp_valide_a, statut_signature')
        .eq('contrat_id', contratId)
        .order('cree_le');
      const signatures = (sigs || []) as unknown as SignatureRow[];

      const doc = new jsPDF({ unit: 'pt', format: 'a4' });
      const margin = 48;
      let y = margin;

      doc.setFontSize(20);
      doc.setTextColor(214, 51, 108);
      doc.text('Certificat de signature électronique', margin, y);
      y += 24;

      doc.setFontSize(11);
      doc.setTextColor(51, 51, 51);
      doc.text('Plateforme : Jolene SASU', margin, y); y += 14;
      doc.text(`Contrat : ${contrat.numero_contrat || contrat.id}`, margin, y); y += 14;
      doc.text(`Type : ${contrat.type_contrat || '—'}`, margin, y); y += 14;
      doc.text(`Statut : ${contrat.statut || '—'}`, margin, y); y += 22;

      if (contrat.hash_document) {
        doc.setFontSize(9);
        doc.setTextColor(100);
        doc.text('Empreinte du document signé (SHA-256) :', margin, y); y += 12;
        doc.setFont('courier', 'normal');
        // wrap hash
        const chunks = contrat.hash_document.match(/.{1,48}/g) || [contrat.hash_document];
        chunks.forEach((c: string) => { doc.text(c, margin, y); y += 11; });
        doc.setFont('helvetica', 'normal');
        y += 12;
      }

      doc.setDrawColor(214, 51, 108);
      doc.setLineWidth(0.8);
      doc.line(margin, y, 595 - margin, y);
      y += 18;

      doc.setFontSize(13);
      doc.setTextColor(51, 51, 51);
      doc.text('Signatures enregistrées', margin, y);
      y += 20;

      for (const sig of signatures) {
        doc.setFontSize(11);
        doc.setTextColor(214, 51, 108);
        doc.text(sig.signataire_role === 'soignant' ? 'Soignant·e' : 'Établissement', margin, y);
        y += 14;
        doc.setFontSize(10);
        doc.setTextColor(51, 51, 51);
        const lignes: string[] = [];
        if (sig.signe_a) {
          lignes.push(`Date / heure : ${format(new Date(sig.signe_a), "dd/MM/yyyy 'à' HH:mm:ss", { locale: fr })}`);
        }
        if (sig.otp_valide_a) lignes.push('OTP SMS validé : oui');
        if (sig.ip_signature) lignes.push(`Adresse IP : ${sig.ip_signature}`);
        if (sig.user_agent) lignes.push(`User-Agent : ${sig.user_agent.slice(0, 90)}…`);
        if (sig.hash_document) lignes.push(`Hash document signé : ${sig.hash_document.slice(0, 24)}…`);
        lignes.push(`Statut : ${sig.statut_signature}`);
        lignes.forEach(l => { doc.text(l, margin + 8, y); y += 12; });
        y += 8;
        if (y > 760) { doc.addPage(); y = margin; }
      }

      // Footer mention juridique
      if (y > 720) { doc.addPage(); y = margin; }
      y = Math.max(y, 720);
      doc.setDrawColor(200);
      doc.line(margin, y, 595 - margin, y);
      y += 12;
      doc.setFontSize(8);
      doc.setTextColor(100);
      const footerLines = [
        'Signature électronique sécurisée Jolene — conforme aux art. 1366-1367 du Code civil.',
        'Renforcée par OTP SMS + horodatage + adresse IP + hash SHA-256 du document.',
        'Pour une signature qualifiée eIDAS, contactez un Prestataire de Services de Confiance qualifié.',
        `Document généré le ${format(new Date(), "dd/MM/yyyy 'à' HH:mm:ss", { locale: fr })}`,
      ];
      footerLines.forEach(l => { doc.text(l, margin, y); y += 10; });

      await telechargerOuPartagerPdf(doc, `certificat-signature-${contrat.numero_contrat || contrat.id}.pdf`);
      afficherNotification({ type: 'succes', message: 'Certificat PDF téléchargé.' });
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur export PDF' });
    } finally {
      setExporting(false);
    }
  }

  if (loading) return <LayoutApp role={role}><ChargementPage /></LayoutApp>;
  if (!contratId || !contrat) {
    return (
      <LayoutApp role={role}>
        <p className="text-center text-muted-foreground py-12">Contrat introuvable</p>
      </LayoutApp>
    );
  }

  const variant: 'detail' | 'resume' = role === 'ADMIN_PLATEFORME' ? 'detail' : 'resume';

  return (
    <LayoutApp role={role}>
      <div className="max-w-3xl mx-auto">
        <button onClick={() => navigate(-1)} className="app-inline-back flex items-center gap-1 text-sm text-primary mb-4 hover:underline">
          <ArrowLeft className="h-4 w-4" /> Retour
        </button>

        <div className="flex items-start justify-between gap-3 mb-4">
          <div>
            <h1 className="text-xl font-bold text-foreground">Certificat de signature</h1>
            <p className="text-sm text-muted-foreground">Contrat {contrat.numero_contrat || contrat.id}</p>
          </div>
          <button
            type="button"
            onClick={exporterPdf}
            disabled={exporting}
            className="btn-primary inline-flex items-center gap-2 disabled:opacity-50"
          >
            {exporting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
            Télécharger PDF
          </button>
        </div>

        <CertificatSignature contratId={contratId} variant={variant} />

        {contrat.hash_document && (
          <div className="mt-4 rounded-xl border border-border bg-card p-4">
            <h3 className="font-semibold text-foreground text-sm mb-2">Empreinte du document signé</h3>
            <p className="text-[10px] font-mono text-muted-foreground break-all">{contrat.hash_document}</p>
            <p className="text-[10px] text-muted-foreground mt-2 italic">
              SHA-256 du contrat figé au moment de la signature. Si vous recalculez le hash du contenu HTML stocké
              (storage_path : <span className="font-mono">{contrat.storage_path || '—'}</span>), vous devez retrouver
              cette empreinte — c'est la preuve que le document n'a pas été modifié depuis la signature.
            </p>
          </div>
        )}

        <p className="text-[10px] text-muted-foreground/70 italic text-center mt-6">
          Conforme art. 1366-1367 Code civil — Signature électronique sécurisée Jolene renforcée par OTP SMS + horodatage + IP + hash SHA-256.
          Audit trail complet disponible sur demande pour les admins plateforme.
        </p>
      </div>
    </LayoutApp>
  );
}
