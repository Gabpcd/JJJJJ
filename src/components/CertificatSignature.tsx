import { useEffect, useState } from 'react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { ShieldCheck, Download, AlertCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface Props {
  contratId: string;
  /** Variant compact (résumé) ou détail (page admin). */
  variant?: 'resume' | 'detail';
}

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
 * Certificat de signature électronique Jolene — affiche les preuves
 * (qui, quand, IP, UA, hash document, OTP, PSC, RPPS) pour les parties
 * au contrat et les admins.
 *
 * Conforme art. 1366-1367 Code civil (signature électronique avancée
 * renforcée par OTP + horodatage + identification multi-facteurs).
 *
 * NB : badge "Signature électronique sécurisée Jolene" (pas "AES eIDAS"
 * réservé aux PSCo qualifiés avec certificat).
 */
export function CertificatSignature({ contratId, variant = 'resume' }: Props) {
  const [signatures, setSignatures] = useState<SignatureRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      setLoading(true);
      const { data, error } = await supabase
        .from('signatures_contrats' as any)
        .select('id, signataire_user_id, signataire_role, signe_a, ip_signature, user_agent, hash_document, otp_valide_a, psc_session_active, rpps_verifie, traits_identite_verifies, statut_signature, cree_le')
        .eq('contrat_id', contratId)
        .order('cree_le');
      if (error) {
        setErr(error.message);
      } else {
        setSignatures((data || []) as unknown as SignatureRow[]);
      }
      setLoading(false);
    })();
  }, [contratId]);

  function exporterPdf() {
    // MVP : version printer-friendly via window.print. Implémentation
    // jsPDF complète peut venir en PR ultérieure (cf bulletin-paie-pdf.ts
    // pour le pattern).
    window.print();
  }

  if (loading) return <div className="text-sm text-muted-foreground">Chargement du certificat…</div>;
  if (err) return (
    <div className="flex items-center gap-2 text-sm text-destructive">
      <AlertCircle className="h-4 w-4" />
      {err}
    </div>
  );

  // La signature manuscrite historique est portée directement par
  // contrats_mission et ne crée pas de ligne signatures_contrats. Sur la
  // page du contrat, le statut des deux parties reste donc la source de
  // vérité : ne pas afficher un faux « aucune signature » contradictoire.
  if (signatures.length === 0) {
    if (variant === 'resume') return null;
    return (
      <div className="text-sm text-muted-foreground italic">
        Aucune preuve OTP détaillée enregistrée pour ce contrat.
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <ShieldCheck className="h-5 w-5 text-primary" />
          <h3 className="font-semibold text-foreground">Certificat de signature Jolene</h3>
        </div>
        {variant === 'detail' && (
          <button
            type="button"
            onClick={exporterPdf}
            className="btn-secondary text-xs inline-flex items-center gap-1.5"
          >
            <Download className="h-3.5 w-3.5" />
            Exporter PDF
          </button>
        )}
      </div>

      <div className="space-y-3">
        {signatures.map(sig => (
          <div key={sig.id} className="rounded-lg border border-border bg-background p-3">
            <div className="flex items-center justify-between flex-wrap gap-2 mb-2">
              <span className="text-sm font-semibold text-foreground capitalize">
                {sig.signataire_role}
              </span>
              <span className={`text-xs px-2 py-0.5 rounded-full ${
                sig.statut_signature === 'signe'
                  ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-300'
                  : 'bg-muted text-muted-foreground'
              }`}>
                {sig.statut_signature === 'signe' ? '✅ Signé' : sig.statut_signature}
              </span>
            </div>

            <dl className="grid grid-cols-1 sm:grid-cols-2 gap-y-1 gap-x-3 text-xs">
              {sig.signe_a && (
                <>
                  <dt className="text-muted-foreground">Date / heure</dt>
                  <dd className="text-foreground font-mono">
                    {format(new Date(sig.signe_a), "dd/MM/yyyy 'à' HH:mm:ss", { locale: fr })}
                  </dd>
                </>
              )}
              {sig.otp_valide_a && (
                <>
                  <dt className="text-muted-foreground">OTP validé</dt>
                  <dd className="text-foreground">✓ Code SMS vérifié</dd>
                </>
              )}
              {variant === 'detail' && sig.ip_signature && (
                <>
                  <dt className="text-muted-foreground">Adresse IP</dt>
                  <dd className="text-foreground font-mono">{sig.ip_signature}</dd>
                </>
              )}
              {variant === 'detail' && sig.user_agent && (
                <>
                  <dt className="text-muted-foreground">Navigateur</dt>
                  <dd className="text-foreground text-[10px] truncate" title={sig.user_agent}>
                    {sig.user_agent}
                  </dd>
                </>
              )}
              {variant === 'detail' && sig.hash_document && (
                <>
                  <dt className="text-muted-foreground">Hash document</dt>
                  <dd className="text-foreground font-mono text-[10px] truncate" title={sig.hash_document}>
                    {sig.hash_document.slice(0, 24)}…
                  </dd>
                </>
              )}
              <dt className="text-muted-foreground">RPPS vérifié</dt>
              <dd className="text-foreground">{sig.rpps_verifie ? '✓' : '—'}</dd>
              <dt className="text-muted-foreground">PSC actif</dt>
              <dd className="text-foreground">{sig.psc_session_active ? '✓' : '—'}</dd>
            </dl>
          </div>
        ))}
      </div>

      <p className="text-[10px] text-muted-foreground border-t border-border pt-2">
        Signature électronique sécurisée Jolene — conforme art. 1366-1367 Code civil
        (signature électronique simple/avancée renforcée par OTP SMS + horodatage +
        IP). Pour une signature qualifiée eIDAS, contactez un Prestataire de Services
        de Confiance qualifié.
      </p>
    </div>
  );
}
