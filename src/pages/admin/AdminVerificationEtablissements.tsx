import { useCallback, useEffect, useState } from 'react';
import {
  AlertTriangle,
  Building2,
  CheckCircle2,
  ExternalLink,
  FileText,
  FlaskConical,
  Loader2,
  MapPin,
  RefreshCw,
  ScanLine,
  ShieldCheck,
  UserCheck,
  XCircle,
} from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { EmptyState } from '@/components/ui/EmptyState';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import {
  analyserVettingEtablissement,
  estUtilisateurTestAdmin,
  formatDateAdmin,
  urlAnnuaireEntreprise,
} from '@/lib/adminPresentation';

type JsonObject = Record<string, unknown>;
type Preuve = 'IDENTITE' | 'FONCTION';
type Decision = 'APPROUVER' | 'REJETER';
type ConfirmationAdmin = {
  titre: string;
  description: string;
  libelleAction: string;
  destructive?: boolean;
  executer: () => Promise<void>;
};

interface Dirigeant extends JsonObject {
  nom?: string;
  prenoms?: string;
  prenom?: string;
  qualite?: string;
  type_dirigeant?: string;
  date_de_naissance?: string;
  annee_de_naissance?: string | number;
}

interface EtabAVerifier {
  id: string;
  nom: string | null;
  est_compte_test?: boolean | null;
  verification_source_version: number;
  siret: string | null;
  siret_verifie: boolean | null;
  siret_verifie_le: string | null;
  siret_raison_sociale: string | null;
  siret_categorie_juridique: string | null;
  siret_code_naf: string | null;
  siret_est_actif: boolean | null;
  finess: string | null;
  finess_verifie: boolean | null;
  finess_verifie_le: string | null;
  finess_raison_sociale: string | null;
  finess_categorie: string | null;
  finess_secteur: string | null;
  finess_est_public: boolean | null;
  adresse_rue: string | null;
  adresse_code_postal: string | null;
  adresse_ville: string | null;
  adresse_departement: string | null;
  representant_nom: string | null;
  representant_prenom: string | null;
  representant_identite_verifiee: boolean | null;
  representant_identite_verifiee_le: string | null;
  representant_piece_s3_key: string | null;
  representant_piece_type_mime: string | null;
  representant_piece_type_document: string | null;
  representant_identite_resultat_ia: JsonObject | null;
  justificatif_fonction_s3_key: string | null;
  justificatif_fonction_type: string | null;
  justificatif_fonction_type_mime: string | null;
  justificatif_fonction_verifie: boolean | null;
  justificatif_fonction_verifie_le: string | null;
  justificatif_fonction_resultat_ia: JsonObject | null;
  dirigeants: Dirigeant[] | null;
  rapprochement_naissance: JsonObject | null;
  rattachement_methode: string | null;
  rattachement_verifie: boolean | null;
  rattachement_verifie_le: string | null;
  statut_verification: string | null;
  motif_rejet: string | null;
  contrat_service_signe: boolean | null;
  contrat_service_signe_le: string | null;
  peut_publier_missions: boolean | null;
  cree_le: string | null;
}

function texte(value: unknown): string | null {
  if (typeof value === 'string' && value.trim()) return value.trim();
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  return null;
}

function valeur(resultat: JsonObject | null, key: string): string | null {
  return resultat ? texte(resultat[key]) : null;
}

function normaliserNom(value: string | null | undefined): string {
  return (value || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\b(sas|sasu|sarl|sa|eurl|sci|scp|selarl|selas|snc|gie|association|groupe|clinique|centre|hopital|ehpad|cabinet|pharmacie|societe)\b/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function nomsConcordent(a: string | null, b: string | null): boolean | null {
  const na = normaliserNom(a);
  const nb = normaliserNom(b);
  if (!na || !nb) return null;
  return na === nb || na.includes(nb) || nb.includes(na);
}

function BadgeGate({ ok, label }: { ok: boolean; label: string }) {
  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2 py-1 text-xs font-medium ${ok
      ? 'bg-emerald-100 text-emerald-800 dark:bg-emerald-950/50 dark:text-emerald-200'
      : 'bg-amber-100 text-amber-900 dark:bg-amber-950/50 dark:text-amber-200'}`}
    >
      {ok ? <CheckCircle2 className="h-3.5 w-3.5" /> : <AlertTriangle className="h-3.5 w-3.5" />}
      {label}
    </span>
  );
}

function ChampExtraction({ label, value }: { label: string; value: unknown }) {
  const rendered = texte(value) || '—';
  return (
    <div>
      <dt className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd className="break-words text-sm text-foreground">{rendered}</dd>
    </div>
  );
}

export default function AdminVerificationEtablissements() {
  usePageTitle('Vérification établissements');
  const { afficherNotification } = useNotification();
  const [etabs, setEtabs] = useState<EtabAVerifier[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);
  const [actionKey, setActionKey] = useState<string | null>(null);
  const [openingKey, setOpeningKey] = useState<string | null>(null);
  const [motifs, setMotifs] = useState<Record<string, string>>({});
  const [datesNaissance, setDatesNaissance] = useState<Record<string, string>>({});
  const [confirmation, setConfirmation] = useState<ConfirmationAdmin | null>(null);

  const charger = useCallback(async () => {
    setLoading(true);
    setErreurChargement(null);
    try {
      const { data, error } = await supabase.rpc(
        'fn_admin_lister_etablissements_a_verifier' as never,
        { p_limit: 200 } as never,
      );
      const payload = data as unknown as { success?: boolean; etablissements?: EtabAVerifier[]; error?: string } | null;
      if (error || !payload?.success) {
        throw error || new Error(payload?.error || 'Erreur de chargement');
      }
      // Les comptes de recette restent hors des KPI réels côté serveur, mais
      // doivent être pilotables ici : ils sont soumis au même verrou de
      // publication et seraient sinon impossibles à débloquer depuis l'admin.
      setEtabs(payload.etablissements || []);
    } catch (error) {
      const message = error instanceof Error && error.message
        ? error.message
        : 'Impossible de charger les dossiers de vérification.';
      setErreurChargement(message);
      afficherNotification({ type: 'erreur', message });
    } finally {
      setLoading(false);
    }
  }, [afficherNotification]);

  useEffect(() => {
    void charger();
  }, [charger]);

  const ouvrirPiece = async (etab: EtabAVerifier, preuve: Preuve) => {
    const path = preuve === 'IDENTITE'
      ? etab.representant_piece_s3_key
      : etab.justificatif_fonction_s3_key;
    if (!path) return;

    const preview = window.open('about:blank', '_blank');
    if (!preview) {
      afficherNotification({
        type: 'erreur',
        message: 'Autorisez les fenêtres contextuelles pour consulter ce document.',
      });
      return;
    }
    preview.opener = null;

    const key = `${etab.id}:${preuve}`;
    setOpeningKey(key);
    try {
      const { data, error } = await supabase.storage
        .from('jolene-documents')
        .createSignedUrl(path, 900);
      if (error || !data?.signedUrl) throw error || new Error('URL indisponible');
      preview.location.replace(data.signedUrl);
    } catch {
      preview.close();
      afficherNotification({
        type: 'erreur',
        message: preuve === 'IDENTITE'
          ? "Impossible d'ouvrir la pièce d'identité."
          : 'Impossible d’ouvrir le justificatif de fonction.',
      });
    } finally {
      setOpeningKey(null);
    }
  };

  const deciderPreuve = async (etab: EtabAVerifier, preuve: Preuve, decision: Decision) => {
    const key = `${etab.id}:${preuve}`;
    const motif = (motifs[key] || '').trim();
    if (decision === 'REJETER' && motif.length < 5) {
      afficherNotification({ type: 'erreur', message: 'Saisissez un motif de rejet (5 caractères minimum).' });
      return;
    }
    const sourceKey = preuve === 'IDENTITE'
      ? etab.representant_piece_s3_key
      : etab.justificatif_fonction_s3_key;
    if (!sourceKey) return;
    const resultatIdentite = etab.representant_identite_resultat_ia;
    const dateSuggeree = valeur(resultatIdentite, 'date_naissance_extraite');

    setActionKey(key);
    try {
      const { data, error } = await supabase.rpc(
        'fn_admin_decider_preuve_etablissement' as never,
        {
          p_etablissement_id: etab.id,
          p_preuve: preuve,
          p_decision: decision,
          p_motif: motif || null,
          p_version_attendue: etab.verification_source_version,
          p_source_s3_key_attendue: sourceKey,
          p_date_naissance_confirmee: preuve === 'IDENTITE'
            ? (datesNaissance[etab.id] || dateSuggeree || null)
            : null,
        } as never,
      );
      const payload = data as unknown as { success?: boolean; error?: string } | null;
      if (error) throw error;
      if (payload?.success !== true) throw new Error(payload?.error || 'Décision non appliquée');
      afficherNotification({
        type: 'succes',
        message: `${preuve === 'IDENTITE' ? 'Identité' : 'Justificatif'} ${decision === 'APPROUVER' ? 'approuvé' : 'rejeté'}.`,
      });
      setMotifs(current => ({ ...current, [key]: '' }));
      await charger();
    } catch (error: unknown) {
      afficherNotification({
        type: 'erreur',
        message: error instanceof Error ? error.message : 'Décision impossible; rechargez la file.',
      });
    } finally {
      setActionKey(null);
    }
  };

  const finaliser = async (etab: EtabAVerifier) => {
    const key = `${etab.id}:FINALISER`;
    setActionKey(key);
    try {
      const { data, error } = await supabase.rpc(
        'fn_admin_finaliser_verification_etablissement' as never,
        {
          p_etablissement_id: etab.id,
          p_version_attendue: etab.verification_source_version,
        } as never,
      );
      const payload = data as unknown as { success?: boolean; error?: string } | null;
      if (error) throw error;
      if (payload?.success !== true) throw new Error(payload?.error || 'Finalisation non appliquée');
      afficherNotification({ type: 'succes', message: 'Dossier finalisé; publication des missions autorisée.' });
      await charger();
    } catch (error: unknown) {
      afficherNotification({
        type: 'erreur',
        message: error instanceof Error ? error.message : 'Finalisation impossible; rechargez la file.',
      });
    } finally {
      setActionKey(null);
    }
  };

  const rejeterDossier = async (etab: EtabAVerifier) => {
    const key = `${etab.id}:DOSSIER`;
    const motif = (motifs[key] || '').trim();
    if (motif.length < 10) {
      afficherNotification({
        type: 'erreur',
        message: 'Saisissez un motif de rejet explicite (10 caractères minimum).',
      });
      return;
    }
    setActionKey(key);
    try {
      const { data, error } = await supabase.rpc(
        'fn_admin_rejeter_dossier_etablissement' as never,
        {
          p_etablissement_id: etab.id,
          p_version_attendue: etab.verification_source_version,
          p_motif: motif,
        } as never,
      );
      const payload = data as unknown as { success?: boolean; error?: string } | null;
      if (error) throw error;
      if (payload?.success !== true) throw new Error(payload?.error || 'Rejet non appliqué');
      afficherNotification({
        type: 'succes',
        message: 'Dossier rejeté; la publication de missions reste bloquée.',
      });
      setMotifs(current => ({ ...current, [key]: '' }));
      await charger();
    } catch (error: unknown) {
      afficherNotification({
        type: 'erreur',
        message: error instanceof Error ? error.message : 'Rejet impossible; rechargez la file.',
      });
    } finally {
      setActionKey(null);
    }
  };

  const demanderDecisionPreuve = (etab: EtabAVerifier, preuve: Preuve, decision: Decision) => {
    const key = `${etab.id}:${preuve}`;
    const motif = (motifs[key] || '').trim();
    if (decision === 'REJETER' && motif.length < 5) {
      afficherNotification({ type: 'erreur', message: 'Saisissez un motif de rejet (5 caractères minimum).' });
      return;
    }
    const nomPreuve = preuve === 'IDENTITE' ? "la pièce d'identité" : 'le justificatif de fonction';
    setConfirmation({
      titre: decision === 'APPROUVER' ? 'Approuver cette preuve ?' : 'Rejeter cette preuve ?',
      description: `${etab.nom || 'Établissement'} — ${nomPreuve}. La décision et votre note de revue seront journalisées.`,
      libelleAction: decision === 'APPROUVER' ? 'Confirmer l’approbation' : 'Confirmer le rejet',
      destructive: decision === 'REJETER',
      executer: () => deciderPreuve(etab, preuve, decision),
    });
  };

  const demanderFinalisation = (etab: EtabAVerifier) => {
    setConfirmation({
      titre: 'Autoriser la publication des missions ?',
      description: `${etab.nom || 'Établissement'} — le serveur vérifiera de nouveau chaque contrôle avant d’activer le compte.`,
      libelleAction: 'Finaliser et autoriser',
      executer: () => finaliser(etab),
    });
  };

  const demanderRejetDossier = (etab: EtabAVerifier) => {
    const motif = (motifs[`${etab.id}:DOSSIER`] || '').trim();
    if (motif.length < 10) {
      afficherNotification({
        type: 'erreur',
        message: 'Saisissez un motif de rejet explicite (10 caractères minimum).',
      });
      return;
    }
    setConfirmation({
      titre: 'Rejeter tout le dossier ?',
      description: `${etab.nom || 'Établissement'} ne pourra plus publier de mission. Le motif saisi sera conservé dans l’audit.`,
      libelleAction: 'Confirmer le rejet du dossier',
      destructive: true,
      executer: () => rejeterDossier(etab),
    });
  };

  return (
    <LayoutAdmin>
      <main className="mx-auto max-w-6xl space-y-4 p-4" aria-busy={loading}>
        <header className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 className="flex items-center gap-2 text-2xl font-bold text-foreground">
              <ShieldCheck className="h-6 w-6 text-primary" /> Vérification des établissements
            </h1>
            <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
              Revue des preuves en attente, y compris les dossiers dont le rattachement automatique est déjà prêt.
              Chaque décision est liée à la version et à la source affichées.
            </p>
          </div>
          <BoutonY2K variant="secondary" size="sm" onClick={() => void charger()} disabled={loading} className="min-h-[44px] gap-2">
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} /> Actualiser
          </BoutonY2K>
        </header>

        {loading ? (
          <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-primary" /></div>
        ) : erreurChargement ? (
          <div role="alert" className="rounded-xl border border-destructive/30 bg-destructive/5 p-6 text-center">
            <AlertTriangle className="mx-auto h-8 w-8 text-destructive" />
            <h2 className="mt-3 text-base font-bold text-foreground">Dossiers indisponibles</h2>
            <p className="mt-1 text-sm text-muted-foreground">{erreurChargement}</p>
            <BoutonY2K
              variant="secondary"
              size="sm"
              className="mt-4 min-h-[44px] gap-2"
              onClick={() => void charger()}
            >
              <RefreshCw className="h-4 w-4" /> Réessayer
            </BoutonY2K>
          </div>
        ) : etabs.length === 0 ? (
          <EmptyState
            icone={<ShieldCheck className="h-12 w-12" />}
            titre="Aucun dossier en attente"
            description="Tous les dossiers ont été finalisés ou explicitement rejetés."
            variant="success"
          />
        ) : (
          <div className="space-y-5">
            {etabs.map((etab) => {
              const identite = etab.representant_identite_resultat_ia || {};
              const fonction = etab.justificatif_fonction_resultat_ia || {};
              const naissance = etab.rapprochement_naissance || {};
              const naissanceStatut = valeur(naissance, 'statut') || 'NON_DISPONIBLE';
              const dateSuggeree = valeur(identite, 'date_naissance_extraite') || '';
              const adresse = [etab.adresse_rue, etab.adresse_code_postal, etab.adresse_ville].filter(Boolean).join(', ');
              const alertesVetting = analyserVettingEtablissement(etab.siret, etab.siret_code_naf);
              const annuaireUrl = urlAnnuaireEntreprise(etab.siret);
              const dirigeants = (etab.dirigeants || []).filter(dirigeant =>
                String(dirigeant.type_dirigeant || '').toLowerCase().includes('physique'));
              const gateSiret = etab.siret_verifie === true && etab.siret_est_actif !== false;
              const gateFiness = !!etab.finess && etab.finess_verifie === true;
              const gateIdentite = etab.representant_identite_verifiee === true;
              const gateRattachement = etab.rattachement_verifie === true;
              const gateContrat = etab.contrat_service_signe === true;
              const peutFinaliser = gateSiret && gateFiness && gateIdentite && gateRattachement && gateContrat;
              const gatesManquantes = [
                !gateSiret && 'SIRET actif',
                !gateFiness && 'FINESS',
                !gateIdentite && 'identité',
                !gateRattachement && 'habilitation',
                !gateContrat && 'contrat de service',
              ].filter((gate): gate is string => typeof gate === 'string');
              const estTest = estUtilisateurTestAdmin(etab);

              return (
                <article key={etab.id} className="space-y-4 rounded-xl border border-border bg-card p-4 shadow-sm" data-testid="dossier-verification-etablissement">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <h2 className="text-lg font-semibold text-foreground">{etab.nom || 'Sans nom'}</h2>
                      <p className="text-xs text-muted-foreground">
                        Créé le {formatDateAdmin(etab.cree_le)} · snapshot v{etab.verification_source_version} · statut {etab.statut_verification || '—'}
                      </p>
                    </div>
                    <div className="flex flex-wrap gap-1.5" aria-label="État des contrôles obligatoires">
                      {estTest && <span className="inline-flex items-center gap-1 rounded-full bg-warning/10 px-2 py-1 text-xs font-medium text-warning"><FlaskConical className="h-3.5 w-3.5" /> Donnée de test</span>}
                      <BadgeGate ok={gateSiret} label="SIRET" />
                      <BadgeGate ok={gateFiness} label="FINESS" />
                      <BadgeGate ok={gateIdentite} label="Identité" />
                      <BadgeGate ok={gateRattachement} label="Habilitation" />
                      <BadgeGate ok={gateContrat} label="Contrat" />
                    </div>
                  </div>

                  <section className="rounded-lg border border-border bg-muted/20 p-3" aria-labelledby={`registres-${etab.id}`}>
                    <h3 id={`registres-${etab.id}`} className="flex items-center gap-2 font-medium text-foreground"><Building2 className="h-4 w-4 text-primary" /> Snapshots officiels</h3>
                    <dl className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                      <ChampExtraction label="Nom déclaré" value={etab.nom} />
                      <ChampExtraction label="SIRET / raison sociale" value={`${etab.siret || '—'} · ${etab.siret_raison_sociale || '—'}`} />
                      <ChampExtraction label="FINESS / raison sociale" value={`${etab.finess || '—'} · ${etab.finess_raison_sociale || '—'}`} />
                      <ChampExtraction label="NAF / catégorie" value={`${etab.siret_code_naf || '—'} · ${etab.siret_categorie_juridique || '—'}`} />
                    </dl>
                    <div className="mt-2 flex flex-wrap gap-3 text-xs">
                      <span className={nomsConcordent(etab.nom, etab.siret_raison_sociale) === false ? 'text-destructive' : 'text-muted-foreground'}>Nom ↔ SIRET : {nomsConcordent(etab.nom, etab.siret_raison_sociale) === false ? 'divergent' : 'cohérent/non concluant'}</span>
                      <span className={nomsConcordent(etab.nom, etab.finess_raison_sociale) === false ? 'text-destructive' : 'text-muted-foreground'}>Nom ↔ FINESS : {nomsConcordent(etab.nom, etab.finess_raison_sociale) === false ? 'divergent' : 'cohérent/non concluant'}</span>
                    </div>
                    {alertesVetting.length > 0 && (
                      <div className="mt-2 space-y-2" data-testid="alertes-vetting-etablissement" role="alert">
                        {alertesVetting.map(alerte => (
                          <p key={alerte.code} className="flex items-start gap-2 rounded border border-amber-300 bg-amber-50 p-2 text-xs text-amber-900 dark:bg-amber-950/30 dark:text-amber-200">
                            <AlertTriangle className="h-4 w-4 shrink-0" />{alerte.message}
                          </p>
                        ))}
                      </div>
                    )}
                    <div className="mt-2 flex flex-wrap gap-3">
                      {annuaireUrl && <a href={annuaireUrl} target="_blank" rel="noopener noreferrer" className="inline-flex min-h-[44px] items-center gap-1 text-xs font-medium text-primary hover:underline">Annuaire des Entreprises <ExternalLink className="h-3.5 w-3.5" /></a>}
                      {adresse && <span className="inline-flex min-h-[44px] items-center gap-1 text-xs text-muted-foreground"><MapPin className="h-3.5 w-3.5" />{adresse}</span>}
                    </div>
                  </section>

                  <section className="rounded-lg border border-border p-3" aria-labelledby={`representant-${etab.id}`}>
                    <h3 id={`representant-${etab.id}`} className="flex items-center gap-2 font-medium text-foreground"><UserCheck className="h-4 w-4 text-primary" /> Représentant et registre</h3>
                    <p className="mt-1 text-sm text-foreground">{etab.representant_prenom || '—'} {etab.representant_nom || '—'} · méthode {etab.rattachement_methode || 'ADMIN'}</p>
                    {dirigeants.length > 0 && <ul className="mt-2 space-y-1 text-xs text-muted-foreground">{dirigeants.map((dirigeant, index) => <li key={`${dirigeant.nom || 'dirigeant'}-${index}`}>{dirigeant.prenoms || dirigeant.prenom || ''} {dirigeant.nom || ''}{dirigeant.qualite ? ` — ${dirigeant.qualite}` : ''}{dirigeant.date_de_naissance || dirigeant.annee_de_naissance ? ` · naissance registre ${dirigeant.date_de_naissance || dirigeant.annee_de_naissance}` : ''}</li>)}</ul>}
                  </section>

                  <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
                    <section className="space-y-3 rounded-lg border border-border p-3" aria-labelledby={`identite-${etab.id}`}>
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <h3 id={`identite-${etab.id}`} className="flex items-center gap-2 font-medium text-foreground"><ScanLine className="h-4 w-4 text-primary" /> Pièce d’identité</h3>
                        <BadgeGate ok={gateIdentite} label={gateIdentite ? 'Approuvée' : 'À revoir'} />
                      </div>
                      <p className="break-all text-xs text-muted-foreground">{etab.representant_piece_type_document || 'Type inconnu'} · {etab.representant_piece_s3_key || 'Aucune source'}</p>
                      {etab.representant_piece_s3_key && <BoutonY2K variant="secondary" size="sm" className="min-h-[44px] gap-1" onClick={() => void ouvrirPiece(etab, 'IDENTITE')} disabled={openingKey === `${etab.id}:IDENTITE`}>{openingKey === `${etab.id}:IDENTITE` ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileText className="h-4 w-4" />} Ouvrir la pièce <ExternalLink className="h-3.5 w-3.5" /></BoutonY2K>}
                      <dl className="grid grid-cols-2 gap-2 rounded bg-muted/20 p-2">
                        <ChampExtraction label="Verdict" value={valeur(identite, 'verdict_final')} />
                        <ChampExtraction label="Confiance" value={valeur(identite, 'confiance') || valeur(identite, 'score_confiance')} />
                        <ChampExtraction label="Nom extrait" value={`${valeur(identite, 'prenom_extrait') || ''} ${valeur(identite, 'nom_extrait') || ''}`.trim()} />
                        <ChampExtraction label="Expiration" value={valeur(identite, 'date_expiration')} />
                      </dl>
                      {valeur(identite, 'motif') && <p className="rounded border border-amber-300 bg-amber-50 p-2 text-xs text-amber-900 dark:bg-amber-950/30 dark:text-amber-200"><strong>Motif IA :</strong> {valeur(identite, 'motif')}</p>}
                      <div className={`rounded border p-2 text-xs ${
                        naissanceStatut === 'DIVERGE'
                          ? 'border-destructive bg-destructive/5 text-destructive'
                          : naissanceStatut === 'CORRESPOND'
                            ? 'border-emerald-300 bg-emerald-50 text-emerald-900 dark:bg-emerald-950/20 dark:text-emerald-200'
                            : 'border-amber-300 bg-amber-50 text-amber-900 dark:bg-amber-950/20 dark:text-amber-200'
                      }`} data-testid="rapprochement-naissance">
                        Date pièce ↔ registre : <strong>{naissanceStatut}</strong>{valeur(naissance, 'date_piece') ? ` · pièce ${valeur(naissance, 'date_piece')}` : ''}{valeur(naissance, 'date_registre') ? ` · registre ${valeur(naissance, 'date_registre')}` : ''}
                      </div>
                      <div>
                        <Label htmlFor={`dob-${etab.id}`}>Date lue sur la pièce (confirmation humaine)</Label>
                        <Input id={`dob-${etab.id}`} type="date" value={datesNaissance[etab.id] ?? dateSuggeree} onChange={event => setDatesNaissance(current => ({ ...current, [etab.id]: event.target.value }))} className="mt-1" />
                      </div>
                      <div>
                        <Label htmlFor={`motif-identite-${etab.id}`}>Motif / note de revue</Label>
                        <Textarea id={`motif-identite-${etab.id}`} value={motifs[`${etab.id}:IDENTITE`] || ''} onChange={event => setMotifs(current => ({ ...current, [`${etab.id}:IDENTITE`]: event.target.value }))} placeholder="Obligatoire pour rejeter" className="mt-1" />
                      </div>
                      <div className="flex flex-wrap gap-2">
                        <BoutonY2K size="sm" className="min-h-[44px] gap-1" disabled={!etab.representant_piece_s3_key || actionKey !== null} onClick={() => demanderDecisionPreuve(etab, 'IDENTITE', 'APPROUVER')}>{actionKey === `${etab.id}:IDENTITE` ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4" />} Approuver</BoutonY2K>
                        <BoutonY2K size="sm" variant="destructive" className="min-h-[44px] gap-1" disabled={!etab.representant_piece_s3_key || actionKey !== null} onClick={() => demanderDecisionPreuve(etab, 'IDENTITE', 'REJETER')}><XCircle className="h-4 w-4" /> Rejeter</BoutonY2K>
                      </div>
                    </section>

                    <section className="space-y-3 rounded-lg border border-border p-3" aria-labelledby={`fonction-${etab.id}`}>
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <h3 id={`fonction-${etab.id}`} className="flex items-center gap-2 font-medium text-foreground"><FileText className="h-4 w-4 text-primary" /> Justificatif de fonction</h3>
                        <BadgeGate ok={etab.justificatif_fonction_verifie === true} label={etab.justificatif_fonction_verifie ? 'Approuvé' : 'Optionnel si dirigeant'} />
                      </div>
                      <p className="break-all text-xs text-muted-foreground">{etab.justificatif_fonction_type || 'Type inconnu'} · {etab.justificatif_fonction_s3_key || 'Aucune source'}</p>
                      {etab.justificatif_fonction_s3_key && <BoutonY2K variant="secondary" size="sm" className="min-h-[44px] gap-1" onClick={() => void ouvrirPiece(etab, 'FONCTION')} disabled={openingKey === `${etab.id}:FONCTION`}>{openingKey === `${etab.id}:FONCTION` ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileText className="h-4 w-4" />} Ouvrir le justificatif <ExternalLink className="h-3.5 w-3.5" /></BoutonY2K>}
                      <dl className="grid grid-cols-2 gap-2 rounded bg-muted/20 p-2">
                        <ChampExtraction label="Verdict" value={valeur(fonction, 'verdict_final')} />
                        <ChampExtraction label="Type détecté" value={valeur(fonction, 'type_detecte')} />
                        <ChampExtraction label="Personne extraite" value={`${valeur(fonction, 'prenom_extrait') || ''} ${valeur(fonction, 'nom_extrait') || ''}`.trim()} />
                        <ChampExtraction label="Fonction" value={valeur(fonction, 'fonction_detectee')} />
                        <ChampExtraction label="Établissement extrait" value={valeur(fonction, 'etablissement_extrait')} />
                        <ChampExtraction label="SIRET extrait" value={valeur(fonction, 'siret_extrait')} />
                      </dl>
                      {valeur(fonction, 'motif') && <p className="rounded border border-amber-300 bg-amber-50 p-2 text-xs text-amber-900 dark:bg-amber-950/30 dark:text-amber-200"><strong>Motif IA :</strong> {valeur(fonction, 'motif')}</p>}
                      <div>
                        <Label htmlFor={`motif-fonction-${etab.id}`}>Motif / note de revue</Label>
                        <Textarea id={`motif-fonction-${etab.id}`} value={motifs[`${etab.id}:FONCTION`] || ''} onChange={event => setMotifs(current => ({ ...current, [`${etab.id}:FONCTION`]: event.target.value }))} placeholder="Obligatoire pour rejeter" className="mt-1" />
                      </div>
                      <div className="flex flex-wrap gap-2">
                        <BoutonY2K size="sm" className="min-h-[44px] gap-1" disabled={!etab.justificatif_fonction_s3_key || !gateIdentite || actionKey !== null} onClick={() => demanderDecisionPreuve(etab, 'FONCTION', 'APPROUVER')}>{actionKey === `${etab.id}:FONCTION` ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4" />} Approuver</BoutonY2K>
                        <BoutonY2K size="sm" variant="destructive" className="min-h-[44px] gap-1" disabled={!etab.justificatif_fonction_s3_key || actionKey !== null} onClick={() => demanderDecisionPreuve(etab, 'FONCTION', 'REJETER')}><XCircle className="h-4 w-4" /> Rejeter</BoutonY2K>
                      </div>
                    </section>
                  </div>

                  <section className={`rounded-lg border p-3 ${peutFinaliser ? 'border-emerald-300 bg-emerald-50 dark:bg-emerald-950/20' : 'border-amber-300 bg-amber-50 dark:bg-amber-950/20'}`}>
                    <h3 className="font-medium text-foreground">Validation finale</h3>
                    <p className="mt-1 text-xs text-muted-foreground">Le serveur recalcule l’habilitation et refuse toute finalisation si une gate a changé.</p>
                    {!peutFinaliser && (
                      <p className="mt-2 text-sm text-amber-900 dark:text-amber-200" role="status">
                        Contrôles manquants : {gatesManquantes.join(', ')}.
                      </p>
                    )}
                    <BoutonY2K className="mt-3 min-h-[44px] gap-2" disabled={!peutFinaliser || actionKey !== null} onClick={() => demanderFinalisation(etab)}>{actionKey === `${etab.id}:FINALISER` ? <Loader2 className="h-4 w-4 animate-spin" /> : <ShieldCheck className="h-4 w-4" />} Finaliser le dossier</BoutonY2K>
                    <div className="mt-4 border-t border-border pt-3">
                      <Label htmlFor={`motif-dossier-${etab.id}`}>Motif de rejet global du dossier</Label>
                      <Textarea
                        id={`motif-dossier-${etab.id}`}
                        value={motifs[`${etab.id}:DOSSIER`] || ''}
                        onChange={event => setMotifs(current => ({
                          ...current,
                          [`${etab.id}:DOSSIER`]: event.target.value,
                        }))}
                        placeholder="Expliquez précisément le motif (10 caractères minimum)"
                        className="mt-1 bg-background"
                      />
                      <BoutonY2K
                        className="mt-2 min-h-[44px] gap-2"
                        variant="destructive"
                        disabled={actionKey !== null}
                        onClick={() => demanderRejetDossier(etab)}
                      >
                        {actionKey === `${etab.id}:DOSSIER`
                          ? <Loader2 className="h-4 w-4 animate-spin" />
                          : <XCircle className="h-4 w-4" />}
                        Rejeter le dossier
                      </BoutonY2K>
                    </div>
                  </section>
                </article>
              );
            })}
          </div>
        )}
        <AlertDialog
          open={confirmation !== null}
          onOpenChange={(open) => {
            if (!open && actionKey === null) setConfirmation(null);
          }}
        >
          <AlertDialogContent className="w-[calc(100%-2rem)] rounded-2xl">
            <AlertDialogHeader>
              <AlertDialogTitle>{confirmation?.titre}</AlertDialogTitle>
              <AlertDialogDescription>{confirmation?.description}</AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel disabled={actionKey !== null}>Revenir au dossier</AlertDialogCancel>
              <AlertDialogAction
                disabled={!confirmation || actionKey !== null}
                className={confirmation?.destructive ? 'bg-destructive text-destructive-foreground hover:bg-destructive/90' : undefined}
                onClick={() => {
                  const action = confirmation?.executer;
                  setConfirmation(null);
                  if (action) void action();
                }}
              >
                {confirmation?.libelleAction}
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </main>
    </LayoutAdmin>
  );
}
