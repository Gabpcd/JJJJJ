import { useState, useEffect, useMemo } from 'react';
import { useSearchParams } from 'react-router-dom';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { EmptyState } from '@/components/ui/EmptyState';
import { supabase } from '@/integrations/supabase/client';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Scale, ChevronRight, Calendar, Gavel } from 'lucide-react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { TimelineLitige } from '@/components/litige/TimelineLitige';
import { FilDiscussionLitige } from '@/components/FilDiscussionLitige';
import { LitigeResolutionModal } from '@/components/admin/litiges/LitigeResolutionModal';
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
import type { LitigeEnrichi } from '@/components/admin/litiges/types';
import { statutBadgeV2, type StatutLitige } from '@/lib/statutLitige';
import { getLabelProfession } from '@/lib/constantes';

type FiltreStatut = 'ACCORDS_A_VALIDER' | 'REVUE_ADMIN' | 'OUVERTS' | 'RESOLUS' | 'TOUS';

const STATUTS_RESOLUS = ['RESOLU', 'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN', 'RESOLU_ACCORD_PARTIES', 'RESOLU_FAVEUR_SOIGNANT', 'RESOLU_FAVEUR_ETAB', 'RESOLU_PARTAGE', 'FERME', 'CLOTURE'];

const TYPES_RESOLUTION_FINANCIERE_MANUELLE = new Set([
  'MODIFICATION_HORAIRES',
  'MODIFICATION_MONTANT',
  'MIXTE',
]);

// Un accord financier proposé par les parties, en attente de validation admin.
const estAccordAValider = (l: any) =>
  l.statut === 'REVUE_ADMIN'
  && l.accord_soignant === true
  && l.accord_etablissement === true
  && !!l.accord_soignant_le
  && !!l.accord_etablissement_le
  && !!l.payload_modifications
  && !l.modifications_executees
  && (l.payload_modifications?.type && l.payload_modifications.type !== 'ACCORD_SANS_MODIFICATION');

const requiertResolutionFinanciereManuelle = (l: any) =>
  TYPES_RESOLUTION_FINANCIERE_MANUELLE.has(l.payload_modifications?.type);

const libelleInitiateur = (initiePar: string) => {
  if (initiePar === 'SOIGNANT') return 'soignant';
  if (initiePar === 'ETABLISSEMENT') return 'établissement';
  return 'système / intervention admin';
};

export default function AdminLitiges() {
  usePageTitle('Litiges — Supervision admin');
  const [searchParams, setSearchParams] = useSearchParams();
  const [litiges, setLitiges] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [filtre, setFiltre] = useState<FiltreStatut>('ACCORDS_A_VALIDER');
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [resolutionLitige, setResolutionLitige] = useState<LitigeEnrichi | null>(null);
  const [resolutionOpen, setResolutionOpen] = useState(false);
  const [validating, setValidating] = useState<string | null>(null);
  const [accordAConfirmer, setAccordAConfirmer] = useState<any | null>(null);

  const charger = async (afficherChargement = true) => {
    if (afficherChargement) setLoading(true);
    // Admin voit TOUS les litiges (même non escaladés / résolus entre parties).
    const { data, error } = await supabase
      .from('litiges')
      .select(`
        id, motif, reponse, statut, cree_le, soignant_id, etablissement_id, mission_id, initie_par,
        accord_soignant, accord_etablissement, accord_soignant_le, accord_etablissement_le,
        resolution, resolu_le, facture_id, type_litige, categorie_litige,
        payload_modifications, modifications_executees,
        missions(id, intitule, debut_le, fin_le, profession_requise, service, statut,
          duree_heures, taux_horaire_base, taux_horaire_base_fige,
          taux_rist_plafonne, rist_plafond_applique, type_contrat_applique),
        soignants:soignant_id(id, prenom, nom, profession, email, telephone),
        etablissements:etablissement_id(id, nom, email_contact, telephone_contact, type)
      `)
      .order('cree_le', { ascending: false });

    if (error) {
      toast.error('Impossible de charger les litiges.');
      if (afficherChargement) setLoading(false);
      return;
    }
    setLitiges((data as any[]) || []);
    if (afficherChargement) setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  useEffect(() => {
    const litigeCible = searchParams.get('litige');
    if (!litigeCible || !litiges.some((litige) => litige.id === litigeCible)) return;
    setFiltre('TOUS');
    setExpandedId(litigeCible);
    requestAnimationFrame(() => {
      document.querySelector(`[data-litige-id="${litigeCible}"]`)?.scrollIntoView({
        behavior: 'smooth',
        block: 'start',
      });
    });
    const suivants = new URLSearchParams(searchParams);
    suivants.delete('litige');
    setSearchParams(suivants, { replace: true });
  }, [litiges, searchParams, setSearchParams]);

  const ouvrirResolution = (l: any) => {
    const enrichi: LitigeEnrichi = {
      id: l.id, motif: l.motif, reponse: l.reponse ?? null,
      statut: l.statut, cree_le: l.cree_le,
      soignant_id: l.soignant_id, etablissement_id: l.etablissement_id,
      mission_id: l.mission_id, initie_par: l.initie_par,
      resolution: l.resolution, resolu_le: l.resolu_le,
      type_litige: l.type_litige ?? null, categorie_litige: l.categorie_litige ?? null,
      facture_id: l.facture_id ?? null,
      payload_modifications: l.payload_modifications ?? null,
      soignant: l.soignants ? {
        id: l.soignants.id, prenom: l.soignants.prenom, nom: l.soignants.nom,
        email: l.soignants.email ?? null, telephone: l.soignants.telephone ?? null,
        profession: l.soignants.profession ?? null,
      } : null,
      etablissement: l.etablissements ? {
        id: l.etablissements.id, nom: l.etablissements.nom,
        email_contact: l.etablissements.email_contact ?? null,
        telephone_contact: l.etablissements.telephone_contact ?? null,
        type: l.etablissements.type ?? null,
      } : null,
      mission: l.missions ? {
        id: l.missions.id, intitule: l.missions.intitule,
        profession_requise: l.missions.profession_requise ?? '',
        service: l.missions.service ?? null,
        debut_le: l.missions.debut_le, fin_le: l.missions.fin_le,
        statut: l.missions.statut ?? null,
        duree_heures: l.missions.duree_heures ?? null,
        taux_horaire_base: l.missions.taux_horaire_base ?? null,
        taux_horaire_base_fige: l.missions.taux_horaire_base_fige ?? null,
        taux_rist_plafonne: l.missions.taux_rist_plafonne ?? null,
        rist_plafond_applique: l.missions.rist_plafond_applique ?? null,
        type_contrat_applique: l.missions.type_contrat_applique ?? null,
      } : null,
    };
    setResolutionLitige(enrichi);
    setResolutionOpen(true);
  };

  // Valider l'accord financier proposé par les parties (exécute le mouvement financier).
  const validerAccord = async (litigeId: string) => {
    setValidating(litigeId);
    const { data, error } = await supabase.rpc('fn_admin_valider_accord_litige' as any, { p_litige_id: litigeId });
    setValidating(null);
    if (error || (data as any)?.success === false) {
      toast.error((data as any)?.error || error?.message || 'Erreur lors de la validation.');
      return;
    }
    toast.success('Accord validé — mouvement financier exécuté.');
    charger();
  };

  const counts = useMemo(() => ({
    accords: litiges.filter(estAccordAValider).length,
    revueAdmin: litiges.filter(l => l.statut === 'REVUE_ADMIN').length,
    ouverts: litiges.filter(l => !STATUTS_RESOLUS.includes(l.statut)).length,
    resolus: litiges.filter(l => STATUTS_RESOLUS.includes(l.statut)).length,
    total: litiges.length,
  }), [litiges]);

  const filtered = useMemo(() => {
    switch (filtre) {
      case 'ACCORDS_A_VALIDER': return litiges.filter(estAccordAValider);
      case 'REVUE_ADMIN': return litiges.filter(l => l.statut === 'REVUE_ADMIN');
      case 'OUVERTS': return litiges.filter(l => !STATUTS_RESOLUS.includes(l.statut));
      case 'RESOLUS': return litiges.filter(l => STATUTS_RESOLUS.includes(l.statut));
      default: return litiges;
    }
  }, [litiges, filtre]);

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Litiges" /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <Scale className="h-6 w-6 text-primary" /> Litiges — Supervision admin
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Tous les litiges sont visibles. Les mouvements financiers (avoir, remboursement,
          ajustement de montant) sont autorisés par l'admin, y compris sur accord des parties.
        </p>
      </div>

      {/* Filters */}
      <div className="flex gap-2 mb-4 overflow-x-auto pb-1">
        {[
          { id: 'ACCORDS_A_VALIDER' as FiltreStatut, label: 'Accords à valider', count: counts.accords, urgent: counts.accords > 0 },
          { id: 'REVUE_ADMIN' as FiltreStatut, label: 'À trancher', count: counts.revueAdmin, urgent: counts.revueAdmin > 0 },
          { id: 'OUVERTS' as FiltreStatut, label: 'Ouverts', count: counts.ouverts },
          { id: 'RESOLUS' as FiltreStatut, label: 'Résolus', count: counts.resolus },
          { id: 'TOUS' as FiltreStatut, label: 'Tous', count: counts.total },
        ].map(f => (
          <button
            key={f.id}
            onClick={() => setFiltre(f.id)}
            className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium border transition-colors whitespace-nowrap ${
              filtre === f.id
                ? 'bg-primary text-primary-foreground border-primary'
                : f.urgent
                  ? 'bg-destructive/10 text-destructive border-destructive/30 hover:bg-destructive/20'
                  : 'bg-card text-muted-foreground border-border hover:bg-muted/50'
            }`}
          >
            {f.label}
            <span className={`rounded-full px-1.5 py-0.5 text-[10px] font-bold ${
              filtre === f.id ? 'bg-primary-foreground/20' : 'bg-muted'
            }`}>{f.count}</span>
          </button>
        ))}
      </div>

      {/* Liste */}
      {filtered.length === 0 ? (
        <EmptyState
          icone={<Scale />}
          mascotte={false}
          titre={filtre === 'ACCORDS_A_VALIDER' ? 'Aucun accord en attente' : filtre === 'REVUE_ADMIN' ? 'Aucun litige à trancher' : 'Aucun litige'}
          description={filtre === 'ACCORDS_A_VALIDER'
            ? 'Aucun mouvement financier en attente de validation admin.'
            : 'Aucun litige correspondant à ce filtre.'}
          variant={filtre === 'ACCORDS_A_VALIDER' || filtre === 'REVUE_ADMIN' ? 'success' : 'info'}
        />
      ) : (
        <div className="space-y-3">
          {filtered.map(l => {
            const badge = statutBadgeV2(l.statut);
            const estDejaResolu = STATUTS_RESOLUS.includes(l.statut);
            const isExpanded = expandedId === l.id;
            const ageJours = Math.floor((Date.now() - new Date(l.cree_le).getTime()) / (1000 * 60 * 60 * 24));
            const ageLabel = ageJours === 0
              ? 'aujourd\'hui'
              : `${ageJours} jour${ageJours > 1 ? 's' : ''}`;
            const isUrgent = l.statut === 'REVUE_ADMIN';
            const resolutionFinanciereManuelle =
              requiertResolutionFinanciereManuelle(l);
            return (
              <div
                key={l.id}
                className={`card-base overflow-hidden ${isUrgent ? 'border-destructive/30' : ''}`}
                data-litige-id={l.id}
                data-statut={l.statut}
              >
                <button
                  type="button"
                  className="flex w-full items-start gap-3 text-left"
                  onClick={() => setExpandedId(isExpanded ? null : l.id)}
                  aria-expanded={isExpanded}
                  aria-controls={`contenu-litige-${l.id}`}
                >
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1 flex-wrap">
                      <BadgeY2K
                        variant={
                          badge.groupe === 'OUVERT' ? 'warning'
                          : badge.groupe === 'MEDIATION' ? 'info'
                          : badge.groupe === 'ACTION_ATTENDUE' ? 'error'
                          : badge.groupe === 'RESOLU_ACCORD' || badge.groupe === 'RESOLU_DECISION' ? 'success'
                          : 'info'
                        }
                        size="sm"
                        icone={<badge.icon className="h-3 w-3" />}
                      >
                        {badge.label}
                      </BadgeY2K>
                      <span className="inline-flex items-center gap-1 text-[10px] text-muted-foreground">
                        <Calendar className="h-3 w-3" />
                        Ouvert il y a {ageLabel}
                      </span>
                      {isUrgent && (
                        <span className="text-[10px] font-semibold text-destructive">À trancher</span>
                      )}
                    </div>
                    <p className="text-sm font-semibold text-foreground truncate">
                      {l.missions?.intitule || 'Mission'}
                    </p>
                    <p className="text-xs text-muted-foreground truncate">
                      Établissement : {l.etablissements?.nom || '—'}
                      {' · '}
                      Soignant : {l.soignants?.prenom} {l.soignants?.nom?.charAt(0)}. ({getLabelProfession(l.soignants?.profession || '')})
                      {l.missions?.debut_le && ` · ${format(new Date(l.missions.debut_le), 'd MMM yyyy', { locale: fr })}`}
                    </p>
                    <p className="text-xs text-muted-foreground mt-0.5 line-clamp-1">
                      <span className="font-medium">Motif :</span> {l.motif}
                    </p>
                    <p className="text-[10px] text-muted-foreground mt-0.5">
                      Initié par : {libelleInitiateur(l.initie_par)}
                    </p>
                  </div>
                  <div className="flex items-center shrink-0">
                    <ChevronRight className={`h-4 w-4 text-muted-foreground transition-transform ${isExpanded ? 'rotate-90' : ''}`} />
                  </div>
                </button>

                {isExpanded && (
                  <div id={`contenu-litige-${l.id}`} className="border-t border-border mt-3 pt-3 space-y-3">
                    <TimelineLitige statut={l.statut} />

                    {estAccordAValider(l) && (
                      <div className="rounded-xl border border-amber-300/60 bg-amber-50 p-3 space-y-2">
                        <p className="text-xs font-semibold text-amber-900">
                          Accord financier proposé par les parties — {resolutionFinanciereManuelle
                            ? 'résolution comptable requise'
                            : 'validation requise'}
                        </p>
                        <p className="text-[11px] text-amber-800">
                          Type : <span className="font-mono">{l.payload_modifications?.type}</span>
                          {l.payload_modifications?.modifications?.montant_total_corrige &&
                            ` · Montant corrigé : ${l.payload_modifications.modifications.montant_total_corrige} €`}
                          {l.payload_modifications?.modifications?.pourcentage_compensation != null &&
                            ` · Compensation : ${l.payload_modifications.modifications.pourcentage_compensation} %`}
                        </p>
                        {l.payload_modifications?.justification && (
                          <p className="text-[11px] text-amber-800 italic">« {l.payload_modifications.justification} »</p>
                        )}
                        <BoutonY2K
                          variant="primary"
                          size="sm"
                          loading={validating === l.id}
                          onClick={() => {
                            if (resolutionFinanciereManuelle) {
                              ouvrirResolution(l);
                            } else {
                              setAccordAConfirmer(l);
                            }
                          }}
                        >
                          {resolutionFinanciereManuelle
                            ? 'Traiter l’accord financier'
                            : 'Valider l’accord et exécuter'}
                        </BoutonY2K>
                        <p className="text-[10px] text-amber-700">
                          {resolutionFinanciereManuelle
                            ? 'Vérifiez puis appliquez les heures, le taux et l’action comptable dans la résolution.'
                            : 'Cette action applique exactement l’accord accepté et conserve sa trace d’audit.'}
                        </p>
                      </div>
                    )}

                    {!estAccordAValider(l) && !estDejaResolu && (
                      <BoutonY2K
                        variant="primary"
                        size="sm"
                        iconeGauche={<Gavel className="h-4 w-4" />}
                        onClick={() => ouvrirResolution(l)}
                      >
                        Résoudre (financier + statut)
                      </BoutonY2K>
                    )}
                    <FilDiscussionLitige
                      litige={{
                        id: l.id,
                        statut: l.statut,
                        motif: l.motif,
                        cree_le: l.cree_le,
                        accord_soignant: l.accord_soignant,
                        accord_etablissement: l.accord_etablissement,
                        soignant_id: l.soignant_id,
                        etablissement_id: l.etablissement_id,
                        resolution: l.resolution,
                        missions: { intitule: l.missions?.intitule },
                      }}
                      onUpdate={charger}
                    />
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
      <AlertDialog
        open={accordAConfirmer !== null}
        onOpenChange={(open) => {
          if (!open && !validating) setAccordAConfirmer(null);
        }}
      >
        <AlertDialogContent className="w-[calc(100%-2rem)] rounded-2xl">
          <AlertDialogHeader>
            <AlertDialogTitle>Confirmer le mouvement financier</AlertDialogTitle>
            <AlertDialogDescription>
              Vérifiez l’accord exact avant de l’exécuter. Cette opération est journalisée et peut produire un avoir, un complément ou un remboursement.
            </AlertDialogDescription>
          </AlertDialogHeader>
          {accordAConfirmer && (
            <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-2 rounded-xl border border-border bg-muted/30 p-3 text-sm">
              <dt className="text-muted-foreground">Mission</dt>
              <dd className="font-medium text-foreground">{accordAConfirmer.missions?.intitule ?? 'Mission'}</dd>
              <dt className="text-muted-foreground">Accord</dt>
              <dd className="font-mono text-xs text-foreground">{accordAConfirmer.payload_modifications?.type ?? '—'}</dd>
              {accordAConfirmer.payload_modifications?.modifications?.pourcentage_compensation != null && (
                <>
                  <dt className="text-muted-foreground">Compensation</dt>
                  <dd className="font-semibold text-foreground">{accordAConfirmer.payload_modifications.modifications.pourcentage_compensation} %</dd>
                </>
              )}
              {accordAConfirmer.payload_modifications?.modifications?.montant_total_corrige != null && (
                <>
                  <dt className="text-muted-foreground">Montant corrigé</dt>
                  <dd className="font-semibold text-foreground">{accordAConfirmer.payload_modifications.modifications.montant_total_corrige} €</dd>
                </>
              )}
              <dt className="text-muted-foreground">Justification</dt>
              <dd className="text-foreground">{accordAConfirmer.payload_modifications?.justification ?? '—'}</dd>
            </dl>
          )}
          <AlertDialogFooter>
            <AlertDialogCancel disabled={Boolean(validating)}>Revenir au dossier</AlertDialogCancel>
            <AlertDialogAction
              disabled={!accordAConfirmer || Boolean(validating)}
              onClick={() => {
                if (!accordAConfirmer) return;
                const litigeId = accordAConfirmer.id;
                setAccordAConfirmer(null);
                void validerAccord(litigeId);
              }}
            >
              Confirmer et exécuter
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <LitigeResolutionModal
        litige={resolutionLitige}
        open={resolutionOpen}
        onOpenChange={(o) => {
          setResolutionOpen(o);
          if (!o) setResolutionLitige(null);
        }}
        onResolved={() => { void charger(false); }}
      />
    </LayoutAdmin>
  );
}
