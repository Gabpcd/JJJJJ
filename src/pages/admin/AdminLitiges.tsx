import { useState, useEffect, useMemo } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
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
import type { LitigeEnrichi } from '@/components/admin/litiges/types';
import { statutBadgeV2, type StatutLitige } from '@/lib/statutLitige';
import { getLabelProfession } from '@/lib/constantes';

type FiltreStatut = 'ACCORDS_A_VALIDER' | 'REVUE_ADMIN' | 'OUVERTS' | 'RESOLUS' | 'TOUS';

const STATUTS_RESOLUS = ['RESOLU', 'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN', 'RESOLU_ACCORD_PARTIES', 'RESOLU_FAVEUR_SOIGNANT', 'RESOLU_FAVEUR_ETAB', 'RESOLU_PARTAGE', 'FERME', 'CLOTURE'];

// Un accord financier proposé par les parties, en attente de validation admin.
const estAccordAValider = (l: any) =>
  !!l.payload_modifications && !l.modifications_executees
  && (l.payload_modifications?.type && l.payload_modifications.type !== 'ACCORD_SANS_MODIFICATION');

export default function AdminLitiges() {
  usePageTitle('Litiges — Supervision admin');
  const [litiges, setLitiges] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [filtre, setFiltre] = useState<FiltreStatut>('ACCORDS_A_VALIDER');
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [resolutionLitige, setResolutionLitige] = useState<LitigeEnrichi | null>(null);
  const [resolutionOpen, setResolutionOpen] = useState(false);
  const [validating, setValidating] = useState<string | null>(null);

  const charger = async () => {
    setLoading(true);
    // Admin voit TOUS les litiges (même non escaladés / résolus entre parties).
    const { data, error } = await supabase
      .from('litiges')
      .select(`
        id, motif, reponse, statut, cree_le, soignant_id, etablissement_id, mission_id, initie_par,
        accord_soignant, accord_etablissement, accord_soignant_le, accord_etablissement_le,
        resolution, resolu_le, facture_id, type_litige, categorie_litige,
        payload_modifications, modifications_executees,
        missions(id, intitule, debut_le, fin_le, profession_requise, service, statut),
        soignants:soignant_id(id, prenom, nom, profession, email, telephone),
        etablissements:etablissement_id(id, nom, email_contact, telephone_contact, type)
      `)
      .order('cree_le', { ascending: false });

    if (error) {
      toast.error('Impossible de charger les litiges.');
      setLoading(false);
      return;
    }
    setLitiges((data as any[]) || []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

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

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

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
          mascotte={filtre === 'ACCORDS_A_VALIDER' || filtre === 'REVUE_ADMIN' ? 'happy' : 'empty'}
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
            const isExpanded = expandedId === l.id;
            const ageJours = Math.floor((Date.now() - new Date(l.cree_le).getTime()) / (1000 * 60 * 60 * 24));
            const ageLabel = ageJours === 0
              ? 'aujourd\'hui'
              : `${ageJours} jour${ageJours > 1 ? 's' : ''}`;
            const isUrgent = l.statut === 'REVUE_ADMIN';
            return (
              <div
                key={l.id}
                className={`card-base overflow-hidden ${isUrgent ? 'border-destructive/30' : ''}`}
                data-litige-id={l.id}
                data-statut={l.statut}
              >
                <div
                  className="flex items-start gap-3 cursor-pointer"
                  onClick={() => setExpandedId(isExpanded ? null : l.id)}
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
                      Initié par : {l.initie_par === 'SOIGNANT' ? 'soignant' : 'établissement'}
                    </p>
                  </div>
                  <div className="flex items-center shrink-0">
                    <ChevronRight className={`h-4 w-4 text-muted-foreground transition-transform ${isExpanded ? 'rotate-90' : ''}`} />
                  </div>
                </div>

                {isExpanded && (
                  <div className="border-t border-border mt-3 pt-3 space-y-3">
                    <TimelineLitige statut={l.statut} />

                    {estAccordAValider(l) && (
                      <div className="rounded-xl border border-amber-300/60 bg-amber-50 p-3 space-y-2">
                        <p className="text-xs font-semibold text-amber-900">
                          Accord financier proposé par les parties — validation requise
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
                          onClick={() => validerAccord(l.id)}
                        >
                          Valider l'accord et exécuter
                        </BoutonY2K>
                        <p className="text-[10px] text-amber-700">
                          Ou ajustez à un autre montant via « Résoudre » ci-dessous.
                        </p>
                      </div>
                    )}

                    <BoutonY2K
                      variant="primary"
                      size="sm"
                      iconeGauche={<Gavel className="h-4 w-4" />}
                      onClick={() => {
                        const enrichi: LitigeEnrichi = {
                          id: l.id, motif: l.motif, reponse: l.reponse ?? null,
                          statut: l.statut, cree_le: l.cree_le,
                          soignant_id: l.soignant_id, etablissement_id: l.etablissement_id,
                          mission_id: l.mission_id, initie_par: l.initie_par,
                          resolution: l.resolution, resolu_le: l.resolu_le,
                          type_litige: l.type_litige ?? null, categorie_litige: l.categorie_litige ?? null,
                          facture_id: l.facture_id ?? null,
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
                          } : null,
                        };
                        setResolutionLitige(enrichi);
                        setResolutionOpen(true);
                      }}
                    >
                      Résoudre (financier + statut)
                    </BoutonY2K>
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
      <LitigeResolutionModal
        litige={resolutionLitige}
        open={resolutionOpen}
        onOpenChange={(o) => {
          setResolutionOpen(o);
          if (!o) setResolutionLitige(null);
        }}
        onResolved={charger}
      />
    </LayoutAdmin>
  );
}
