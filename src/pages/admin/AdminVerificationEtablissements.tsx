import { useEffect, useState } from 'react';
import {
  Loader2, Building2, UserCheck, Mail, Phone, MapPin, CheckCircle2, XCircle, AlertTriangle,
  FileText, ExternalLink, ShieldCheck, ScanLine, FlaskConical,
} from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { EmptyState } from '@/components/ui/EmptyState';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import {
  analyserVettingEtablissement,
  estUtilisateurTestAdmin,
  formatDateAdmin,
  urlAnnuaireEntreprise,
} from '@/lib/adminPresentation';

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
  siret_raison_sociale: string | null;
  siret_categorie_juridique: string | null;
  siret_code_naf: string | null;
  siret_est_actif: boolean | null;
  finess: string | null;
  finess_verifie: boolean | null;
  finess_raison_sociale: string | null;
  finess_categorie: string | null;
  finess_secteur: string | null;
  finess_est_public: boolean | null;
  adresse_rue: string | null;
  adresse_code_postal: string | null;
  adresse_ville: string | null;
  adresse_departement: string | null;
  telephone_contact: string | null;
  telephone_verifie: boolean | null;
  representant_nom: string | null;
  representant_prenom: string | null;
  representant_identite_verifiee: boolean | null;
  representant_piece_s3_key: string | null;
  representant_piece_type_document: string | null;
  representant_identite_resultat_ia: any | null;
  dirigeants: Dirigeant[] | null;
  email_contact: string | null;
  email_contact_verifie: boolean | null;
  rattachement_methode: string | null;
  rattachement_verifie: boolean | null;
  statut_verification: string | null;
  contrat_valide: boolean | null;
  peut_publier_missions: boolean | null;
  cree_le: string | null;
  est_compte_test?: boolean | null;
}

// ── Comparaison de noms (cohérence nom déclaré / SIRET / FINESS) ──────────
function normaliserNom(s: string | null | undefined): string {
  if (!s) return '';
  return s
    .toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '') // accents
    .replace(/\b(sas|sasu|sarl|sa|eurl|sci|scp|selarl|selas|snc|gie|association|asso|groupe|clinique|centre|hopital|ehpad|cabinet|pharmacie|ste|societe)\b/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

type Verdict = 'match' | 'partiel' | 'different' | 'absent';

function comparerNoms(a: string | null | undefined, b: string | null | undefined): Verdict {
  const na = normaliserNom(a);
  const nb = normaliserNom(b);
  if (!na || !nb) return 'absent';
  if (na === nb) return 'match';
  if (na.includes(nb) || nb.includes(na)) return 'partiel';
  // chevauchement de mots significatifs
  const setA = new Set(na.split(' ').filter(w => w.length >= 3));
  const setB = new Set(nb.split(' ').filter(w => w.length >= 3));
  const communs = [...setA].filter(w => setB.has(w));
  if (communs.length > 0) return 'partiel';
  return 'different';
}

const VERDICT_STYLE: Record<Verdict, { cls: string; label: string; icon: typeof CheckCircle2 }> = {
  match: { cls: 'text-emerald-700 dark:text-emerald-300', label: 'Concordent', icon: CheckCircle2 },
  partiel: { cls: 'text-amber-700 dark:text-amber-300', label: 'Concordance partielle', icon: AlertTriangle },
  different: { cls: 'text-red-700 dark:text-red-300', label: 'NE CONCORDENT PAS', icon: XCircle },
  absent: { cls: 'text-muted-foreground', label: 'Donnée manquante', icon: AlertTriangle },
};

// ── Badge à 3 états : vérifié / renseigné non vérifié / manquant ──────────
function BadgeVerif({ present, verifie, label }: { present: boolean; verifie: boolean | null | undefined; label: string }) {
  let cls: string; let icon: JSX.Element; let txt: string;
  if (!present) {
    cls = 'bg-muted text-muted-foreground'; icon = <XCircle className="h-3 w-3" />; txt = `${label} manquant`;
  } else if (verifie) {
    cls = 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300'; icon = <CheckCircle2 className="h-3 w-3" />; txt = `${label} vérifié`;
  } else {
    cls = 'bg-amber-100 text-amber-700 dark:bg-amber-950/50 dark:text-amber-300'; icon = <AlertTriangle className="h-3 w-3" />; txt = `${label} non vérifié`;
  }
  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium ${cls}`}>
      {icon}{txt}
    </span>
  );
}

/**
 * Page admin /admin/verification-etablissements — file d'attente de revue manuelle
 * des établissements non encore rattachés (fallback ADMIN). L'admin examine le
 * dossier complet (cohérence SIRET/FINESS/nom, représentant + pièce d'identité +
 * verdict IA, dirigeants INSEE, contact) et valide ou rejette.
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
    if (!confirm(`Valider « ${etab.nom} » ? L'établissement pourra publier des missions (rattachement par décision admin).`)) return;
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
            File d'attente des établissements non encore rattachés. Vérifiez la cohérence
            <strong> SIRET / FINESS / nom</strong>, l'identité du représentant, contactez si besoin, puis validez ou rejetez.
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
              const adresse = [etab.adresse_rue, etab.adresse_code_postal, etab.adresse_ville].filter(Boolean).join(', ');
              // Cohérence : on compare le nom déclaré aux raisons sociales officielles.
              const vSiret = comparerNoms(etab.nom, etab.siret_raison_sociale);
              const vFiness = etab.finess ? comparerNoms(etab.nom, etab.finess_raison_sociale) : 'absent';
              const vCroise = (etab.siret_raison_sociale && etab.finess_raison_sociale)
                ? comparerNoms(etab.siret_raison_sociale, etab.finess_raison_sociale) : 'absent';
              const iaRep = etab.representant_identite_resultat_ia as any;
              const alertesVetting = analyserVettingEtablissement(etab.siret, etab.siret_code_naf);
              const annuaireUrl = urlAnnuaireEntreprise(etab.siret);
              const estTest = estUtilisateurTestAdmin(etab);
              return (
                <div key={etab.id} className="rounded-xl border border-border bg-card p-4 space-y-3">
                  {/* En-tête */}
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div>
                      <p className="font-semibold text-foreground">{etab.nom || 'Sans nom'}</p>
                      <p className="text-xs text-muted-foreground whitespace-nowrap">
                        SIRET {etab.siret || '—'} · créé le {formatDateAdmin(etab.cree_le)}
                      </p>
                    </div>
                    <div className="flex flex-wrap gap-1.5">
                      {estTest && (
                        <span className="inline-flex items-center gap-1 rounded-full bg-warning/10 px-2 py-0.5 text-xs font-medium text-warning" data-testid="badge-donnee-test">
                          <FlaskConical className="h-3 w-3" /> Donnée de test
                        </span>
                      )}
                      <BadgeVerif present={!!etab.siret} verifie={etab.siret_verifie} label="SIRET" />
                      <BadgeVerif present={!!etab.finess} verifie={etab.finess_verifie} label="FINESS" />
                      <BadgeVerif present={!!etab.representant_piece_s3_key} verifie={etab.representant_identite_verifiee} label="Identité" />
                      <BadgeVerif present={!!etab.email_contact} verifie={etab.email_contact_verifie} label="E-mail" />
                      <BadgeVerif present={!!etab.telephone_contact} verifie={etab.telephone_verifie} label="Tél." />
                      <BadgeVerif present={etab.contrat_valide != null} verifie={etab.contrat_valide} label="Contrat" />
                    </div>
                  </div>

                  {/* Cohérence SIRET / FINESS / nom — le point clé de la revue */}
                  <div className="rounded-lg bg-muted/20 p-3 text-sm space-y-2">
                    <p className="font-medium text-foreground flex items-center gap-1.5">
                      <Building2 className="h-4 w-4 text-primary" /> Cohérence des identités
                    </p>
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                      <div>
                        <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Nom déclaré</p>
                        <p className="text-foreground">{etab.nom || '—'}</p>
                      </div>
                      <div>
                        <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Raison sociale SIRET (INSEE)</p>
                        <p className="text-foreground">{etab.siret_raison_sociale || '—'}</p>
                      </div>
                      <div>
                        <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Raison sociale FINESS</p>
                        <p className="text-foreground">{etab.finess_raison_sociale || (etab.finess ? '?' : '— (non renseigné)')}</p>
                      </div>
                    </div>
                    <div className="flex flex-wrap gap-3 pt-1">
                      {([['Nom ↔ SIRET', vSiret], ['Nom ↔ FINESS', vFiness], ['SIRET ↔ FINESS', vCroise]] as [string, Verdict][]).map(([lbl, v]) => {
                        const st = VERDICT_STYLE[v];
                        return (
                          <span key={lbl} className={`inline-flex items-center gap-1 text-xs font-medium ${st.cls}`}>
                            <st.icon className="h-3.5 w-3.5" /> {lbl} : {st.label}
                          </span>
                        );
                      })}
                    </div>
                    {(vSiret === 'different' || vFiness === 'different' || vCroise === 'different') && (
                      <div className="flex items-start gap-2 rounded border border-red-200 bg-red-50 p-2 text-xs text-red-700 dark:border-red-900 dark:bg-red-950/30 dark:text-red-300">
                        <AlertTriangle className="h-4 w-4 shrink-0" />
                        <p>Incohérence détectée : le nom déclaré et/ou les raisons sociales officielles ne correspondent pas. Vérifiez qu'il ne s'agit pas d'une usurpation avant de valider.</p>
                      </div>
                    )}
                    {etab.siret_categorie_juridique && (
                      <p className="text-xs text-muted-foreground">
                        Cat. juridique : {etab.siret_categorie_juridique}{etab.siret_code_naf ? ` · NAF ${etab.siret_code_naf}` : ''}
                        {etab.siret_est_actif === false ? ' · SIRET INACTIF' : etab.siret_est_actif ? ' · actif' : ''}
                      </p>
                    )}
                    {alertesVetting.length > 0 && (
                      <div className="space-y-1.5" data-testid="alertes-vetting-etablissement">
                        {alertesVetting.map((alerte) => (
                          <div key={alerte.code} className="flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 p-2 text-xs text-amber-900 dark:border-amber-800 dark:bg-amber-950/30 dark:text-amber-200">
                            <AlertTriangle className="h-4 w-4 shrink-0" />
                            <span>{alerte.message}</span>
                          </div>
                        ))}
                      </div>
                    )}
                    {annuaireUrl && (
                      <a href={annuaireUrl} target="_blank" rel="noopener noreferrer" className="inline-flex min-h-[44px] items-center gap-1.5 text-xs font-medium text-primary hover:underline">
                        Vérifier sur l'Annuaire des Entreprises <ExternalLink className="h-3.5 w-3.5" />
                      </a>
                    )}
                    {adresse && (
                      <p className="text-xs text-muted-foreground flex items-center gap-1.5">
                        <MapPin className="h-3.5 w-3.5" /> {adresse}
                      </p>
                    )}
                  </div>

                  {/* Représentant + pièce + verdict IA + dirigeants */}
                  <div className="rounded-lg bg-muted/20 p-3 text-sm space-y-1.5">
                    <p className="font-medium text-foreground flex items-center gap-1.5">
                      <UserCheck className="h-4 w-4 text-primary" /> Représentant (personne physique rattachée)
                    </p>
                    <p className="text-muted-foreground">
                      {etab.representant_prenom || ''} {etab.representant_nom || '—'}
                      {etab.representant_piece_type_document ? ` · ${etab.representant_piece_type_document}` : ''}
                    </p>
                    {iaRep && (iaRep.verdict || iaRep.nom_detecte || iaRep.confiance != null) && (
                      <p className="text-xs flex items-start gap-1.5 text-muted-foreground">
                        <ScanLine className="h-3.5 w-3.5 shrink-0 mt-0.5 text-primary" />
                        <span>
                          Vérif IA : {iaRep.verdict ? <strong>{String(iaRep.verdict)}</strong> : '—'}
                          {iaRep.nom_detecte ? ` · nom détecté : ${iaRep.nom_detecte}` : ''}
                          {iaRep.confiance != null ? ` · confiance ${iaRep.confiance}` : ''}
                          {iaRep.motif ? ` · ${iaRep.motif}` : ''}
                        </span>
                      </p>
                    )}
                    {etab.representant_piece_s3_key && (
                      <BoutonY2K
                        size="sm"
                        variant="secondary"
                        onClick={() => ouvrirPiece(etab.id, etab.representant_piece_s3_key)}
                        disabled={openingId === etab.id}
                        className="gap-1.5 min-h-[44px]"
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

                  {/* Contact direct */}
                  <div className="rounded-lg bg-muted/20 p-3 text-sm space-y-2">
                    <p className="font-medium text-foreground flex items-center gap-1.5">
                      <Mail className="h-4 w-4 text-primary" /> Contacter l'établissement
                    </p>
                    <div className="flex flex-wrap gap-2">
                      {etab.email_contact ? (
                        <a
                          href={`mailto:${etab.email_contact}?subject=${encodeURIComponent('Vérification de votre compte Jolene')}`}
                          className="inline-flex items-center gap-1.5 rounded-lg border border-primary/30 bg-primary/5 px-3 py-1.5 text-xs font-medium text-primary hover:bg-primary/10"
                        >
                          <Mail className="h-3.5 w-3.5" /> {etab.email_contact}
                          {!etab.email_contact_verifie && <span className="text-amber-600">(non confirmé)</span>}
                        </a>
                      ) : (
                        <span className="text-xs text-muted-foreground">Aucun e-mail renseigné</span>
                      )}
                      {etab.telephone_contact ? (
                        <a
                          href={`tel:${etab.telephone_contact.replace(/\s/g, '')}`}
                          className="inline-flex items-center gap-1.5 rounded-lg border border-primary/30 bg-primary/5 px-3 py-1.5 text-xs font-medium text-primary hover:bg-primary/10"
                        >
                          <Phone className="h-3.5 w-3.5" /> {etab.telephone_contact}
                        </a>
                      ) : (
                        <span className="text-xs text-muted-foreground">Aucun téléphone renseigné</span>
                      )}
                    </div>
                  </div>

                  {/* Actions */}
                  <div className="flex flex-wrap gap-2 pt-1">
                    <BoutonY2K
                      size="sm"
                      onClick={() => valider(etab)}
                      disabled={actionId === etab.id}
                      className="gap-1.5 min-h-[44px]"
                    >
                      {actionId === etab.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4" />}
                      Valider (rattachement par décision admin)
                    </BoutonY2K>
                    <BoutonY2K
                      size="sm"
                      variant="destructive"
                      onClick={() => rejeter(etab)}
                      disabled={actionId === etab.id}
                      className="gap-1.5 min-h-[44px]"
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
