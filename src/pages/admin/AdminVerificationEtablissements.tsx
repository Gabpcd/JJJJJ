import { useEffect, useState } from 'react';
import {
  Loader2, Building2, UserCheck, Mail, CheckCircle2, XCircle, FileText, ExternalLink, ShieldCheck,
} from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { EmptyState } from '@/components/ui/EmptyState';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

interface Dirigeant {
  nom?: string;
  prenoms?: string;
  qualite?: string;
  type_dirigeant?: string;
}

interface EtabAVerifier {
  id: string;
  nom: string | null;
  siret: string | null;
  siret_verifie: boolean | null;
  finess: string | null;
  finess_verifie: boolean | null;
  finess_raison_sociale: string | null;
  finess_categorie: string | null;
  finess_secteur: string | null;
  finess_est_public: boolean | null;
  representant_nom: string | null;
  representant_prenom: string | null;
  representant_identite_verifiee: boolean | null;
  representant_piece_s3_key: string | null;
  representant_piece_type_document: string | null;
  dirigeants: Dirigeant[] | null;
  email_contact: string | null;
  email_contact_verifie: boolean | null;
  rattachement_methode: string | null;
  rattachement_verifie: boolean | null;
  statut_verification: string | null;
  contrat_valide: boolean | null;
  peut_publier_missions: boolean | null;
  cree_le: string | null;
}

function Badge({ ok, label }: { ok: boolean | null | undefined; label: string }) {
  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium ${ok ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'}`}>
      {ok ? <CheckCircle2 className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
      {label}
    </span>
  );
}

/**
 * Page admin /admin/verification-etablissements — file d'attente de revue manuelle
 * des établissements non encore rattachés (fallback ADMIN). L'admin examine le
 * dossier (FINESS, représentant + pièce d'identité, dirigeants INSEE, e-mail) et
 * valide (fn_admin_valider_etablissement → rattachement ADMIN + droit de publier)
 * ou rejette (fn_admin_rejeter_etablissement).
 */
export default function AdminVerificationEtablissements() {
  usePageTitle('Vérification établissements');
  const { afficherNotification } = useNotification();
  const [etabs, setEtabs] = useState<EtabAVerifier[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionId, setActionId] = useState<string | null>(null);
  const [openingId, setOpeningId] = useState<string | null>(null);

  async function charger() {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_lister_etablissements_a_verifier' as any, { p_limit: 200 });
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
    } else if ((data as any)?.success) {
      setEtabs(((data as any).etablissements || []) as EtabAVerifier[]);
    } else {
      afficherNotification({ type: 'erreur', message: (data as any)?.error || 'Erreur de chargement' });
    }
    setLoading(false);
  }

  useEffect(() => { charger(); }, []);

  const ouvrirPiece = async (id: string, path: string | null) => {
    if (!path) return;
    setOpeningId(id);
    try {
      const { data, error } = await supabase.storage.from('jolene-documents').createSignedUrl(path, 3600);
      if (error || !data?.signedUrl) throw error || new Error('URL indisponible');
      window.open(data.signedUrl, '_blank');
    } catch {
      afficherNotification({ type: 'erreur', message: "Impossible d'ouvrir la pièce d'identité." });
    } finally {
      setOpeningId(null);
    }
  };

  const valider = async (etab: EtabAVerifier) => {
    if (!confirm(`Valider « ${etab.nom} » ? L'établissement pourra publier des missions (rattachement ADMIN).`)) return;
    setActionId(etab.id);
    try {
      const { data, error } = await supabase.rpc('fn_admin_valider_etablissement' as any, { p_etablissement_id: etab.id });
      if (error) throw error;
      if ((data as any)?.error) throw new Error((data as any).error);
      afficherNotification({ type: 'succes', message: `Établissement validé : ${(data as any)?.nom || etab.nom}` });
      await charger();
    } catch (e: unknown) {
      afficherNotification({ type: 'erreur', message: (e as Error)?.message || 'Erreur lors de la validation' });
    } finally {
      setActionId(null);
    }
  };

  const rejeter = async (etab: EtabAVerifier) => {
    const motif = prompt(`Motif du rejet de « ${etab.nom} » :`, 'Dossier non conforme');
    if (motif === null) return;
    setActionId(etab.id);
    try {
      const { data, error } = await supabase.rpc('fn_admin_rejeter_etablissement' as any, {
        p_etablissement_id: etab.id, p_motif: motif,
      });
      if (error) throw error;
      if ((data as any)?.error) throw new Error((data as any).error);
      afficherNotification({ type: 'succes', message: (data as any)?.message || 'Établissement rejeté' });
      await charger();
    } catch (e: unknown) {
      afficherNotification({ type: 'erreur', message: (e as Error)?.message || 'Erreur lors du rejet' });
    } finally {
      setActionId(null);
    }
  };

  return (
    <LayoutAdmin>
      <div className="max-w-5xl mx-auto p-4 space-y-4">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <ShieldCheck className="h-6 w-6 text-primary" /> Vérification des établissements
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            File d'attente des établissements non encore rattachés. Examinez le dossier puis validez (rattachement par décision admin) ou rejetez.
          </p>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-20">
            <Loader2 className="h-8 w-8 animate-spin text-primary" />
          </div>
        ) : etabs.length === 0 ? (
          <EmptyState
            icone={<ShieldCheck className="h-12 w-12" />}
            titre="Aucun établissement en attente"
            description="Tous les établissements actifs sont rattachés ou rejetés."
            variant="success"
          />
        ) : (
          <div className="space-y-4">
            {etabs.map(etab => {
              const dirigeantsPhysiques = (etab.dirigeants || []).filter(
                d => (d.type_dirigeant || '').toLowerCase().includes('physique'),
              );
              return (
                <div key={etab.id} className="rounded-xl border border-border bg-card p-4 space-y-3">
                  {/* En-tête */}
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div>
                      <p className="font-semibold text-foreground">{etab.nom || 'Sans nom'}</p>
                      <p className="text-xs text-muted-foreground">
                        SIRET {etab.siret || '—'} · créé le {etab.cree_le ? new Date(etab.cree_le).toLocaleDateString('fr-FR') : '—'}
                      </p>
                    </div>
                    <div className="flex flex-wrap gap-1.5">
                      <Badge ok={etab.siret_verifie} label="SIRET" />
                      <Badge ok={etab.finess_verifie} label="FINESS" />
                      <Badge ok={etab.representant_identite_verifiee} label="Identité" />
                      <Badge ok={etab.email_contact_verifie} label="E-mail" />
                      <Badge ok={etab.contrat_valide} label="Contrat" />
                    </div>
                  </div>

                  {/* FINESS */}
                  <div className="rounded-lg bg-muted/20 p-3 text-sm">
                    <p className="font-medium text-foreground flex items-center gap-1.5">
                      <Building2 className="h-4 w-4 text-primary" /> Structure (FINESS)
                    </p>
                    <p className="text-muted-foreground mt-1">
                      {etab.finess ? (
                        <>FINESS {etab.finess} — {etab.finess_raison_sociale || '?'}{etab.finess_categorie ? ` · ${etab.finess_categorie}` : ''}{etab.finess_est_public ? ' · Public' : ''}</>
                      ) : 'Aucun FINESS renseigné.'}
                    </p>
                  </div>

                  {/* Représentant + pièce + dirigeants */}
                  <div className="rounded-lg bg-muted/20 p-3 text-sm space-y-1.5">
                    <p className="font-medium text-foreground flex items-center gap-1.5">
                      <UserCheck className="h-4 w-4 text-primary" /> Représentant
                    </p>
                    <p className="text-muted-foreground">
                      {etab.representant_prenom || ''} {etab.representant_nom || '—'}
                      {etab.representant_piece_type_document ? ` · ${etab.representant_piece_type_document}` : ''}
                    </p>
                    {etab.representant_piece_s3_key && (
                      <BoutonY2K
                        size="sm"
                        variant="secondary"
                        onClick={() => ouvrirPiece(etab.id, etab.representant_piece_s3_key)}
                        disabled={openingId === etab.id}
                        className="gap-1.5"
                      >
                        {openingId === etab.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <FileText className="h-3.5 w-3.5" />}
                        Voir la pièce d'identité <ExternalLink className="h-3 w-3" />
                      </BoutonY2K>
                    )}
                    {dirigeantsPhysiques.length > 0 && (
                      <div className="mt-1">
                        <p className="text-xs font-medium text-foreground">Dirigeants déclarés (INSEE) :</p>
                        <ul className="text-xs text-muted-foreground list-disc list-inside">
                          {dirigeantsPhysiques.map((d, i) => (
                            <li key={i}>{d.prenoms || ''} {d.nom || ''}{d.qualite ? ` — ${d.qualite}` : ''}</li>
                          ))}
                        </ul>
                      </div>
                    )}
                  </div>

                  {/* E-mail */}
                  <div className="rounded-lg bg-muted/20 p-3 text-sm">
                    <p className="font-medium text-foreground flex items-center gap-1.5">
                      <Mail className="h-4 w-4 text-primary" /> E-mail de contact
                    </p>
                    <p className="text-muted-foreground mt-1">
                      {etab.email_contact || '—'} {etab.email_contact_verifie ? '(confirmé)' : '(non confirmé)'}
                    </p>
                  </div>

                  {/* Actions */}
                  <div className="flex flex-wrap gap-2 pt-1">
                    <BoutonY2K
                      size="sm"
                      onClick={() => valider(etab)}
                      disabled={actionId === etab.id}
                      className="gap-1.5"
                    >
                      {actionId === etab.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4" />}
                      Valider (rattachement ADMIN)
                    </BoutonY2K>
                    <BoutonY2K
                      size="sm"
                      variant="destructive"
                      onClick={() => rejeter(etab)}
                      disabled={actionId === etab.id}
                      className="gap-1.5"
                    >
                      <XCircle className="h-4 w-4" /> Rejeter
                    </BoutonY2K>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </LayoutAdmin>
  );
}
