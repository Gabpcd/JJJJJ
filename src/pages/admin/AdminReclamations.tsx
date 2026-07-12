import React, { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ReclamationsScoreContent } from './AdminReclamationsScore';
import { ScoreTriageContent } from './AdminScoreTriage';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementSectionAdmin } from '@/components/admin/ChargementAdmin';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { extraireMessageErreur } from '@/lib/erreurs';
import { Send } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

/* Les contestations de score (workflow MAINTENIR / RÉDUIRE / ANNULER Sprint 3.5)
   vivent sur /admin/reclamations-score. L'onglet legacy `reclamations_scoring`
   (table vide, workflow pré-3.5) a été supprimé — plus de doublon. */

const STATUT_OPTIONS = [
  { value: 'EN_COURS', label: 'En cours' },
  { value: 'RESOLUE', label: 'Résolue' },
  { value: 'FERMEE', label: 'Fermée' },
];

export default function AdminReclamations() {
  usePageTitle('Réclamations');
  const { afficherNotification } = useNotification();

  const [searchParams, setSearchParams] = useSearchParams();
  const tabParam = searchParams.get('tab');
  const onglet = ['generales', 'score', 'triage'].includes(tabParam ?? '') ? (tabParam as string) : 'generales';

  const [reclamations, setReclamations] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [reponseInput, setReponseInput] = useState<Record<string, string>>({});
  const [statutInput, setStatutInput] = useState<Record<string, string>>({});
  const [traitement, setTraitement] = useState<string | null>(null);

  const charger = async () => {
    setLoading(true);
    const { data } = await supabase
      .from('reclamations' as any)
      .select('*')
      .order('cree_le', { ascending: false })
      .limit(100);

    if (data && (data as any[]).length > 0) {
      // Enrich with user names
      const userIds = [...new Set((data as any[]).map((r: any) => r.utilisateur_id))];
      const [{ data: soignants }, { data: etabs }] = await Promise.all([
        supabase.from('soignants').select('id, prenom, nom').in('id', userIds),
        supabase.from('etablissements').select('id, nom').in('id', userIds),
      ]);

      setReclamations((data as any[]).map((r: any) => {
        const sg = soignants?.find(s => s.id === r.utilisateur_id);
        const et = etabs?.find(e => e.id === r.utilisateur_id);
        return {
          ...r,
          nom_utilisateur: sg ? `${sg.prenom} ${sg.nom}` : et?.nom || 'Inconnu',
        };
      }));
    } else {
      setReclamations([]);
    }
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const traiter = async (id: string) => {
    setTraitement(id);
    const statut = statutInput[id] || 'RESOLUE';
    const reponse = reponseInput[id]?.trim() || null;

    const { data, error } = await supabase.rpc('fn_traiter_reclamation_generale' as any, {
      p_reclamation_id: id,
      p_statut: statut,
      p_reponse: reponse,
    });

    if (error || (data as any)?.error) {
      afficherNotification({ type: 'erreur', message: (data as any)?.error || extraireMessageErreur(error!) });
    } else {
      afficherNotification({ type: 'succes', message: 'Réclamation traitée' });
      await charger();
    }
    setTraitement(null);
  };

  const enAttente = reclamations.filter(r => r.statut === 'EN_ATTENTE' || r.statut === 'EN_COURS');
  const traitees = reclamations.filter(r => r.statut === 'RESOLUE' || r.statut === 'FERMEE');

  return (
    <LayoutAdmin>
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">Réclamations & scores</h1>
        <p className="text-sm text-muted-foreground mt-0.5">
          Demandes des utilisateurs, contestations de score et triage des comptes à risque — au même endroit.
        </p>
      </div>

      <Tabs value={onglet} onValueChange={(v) => setSearchParams({ tab: v }, { replace: true })}>
        <TabsList className="mb-4">
          <TabsTrigger value="generales">Réclamations</TabsTrigger>
          <TabsTrigger value="score">Contestations score</TabsTrigger>
          <TabsTrigger value="triage">Triage des scores</TabsTrigger>
        </TabsList>

        <TabsContent value="generales" className="mt-0">
      <div className="space-y-4">
        {loading ? (
          <ChargementSectionAdmin label="Chargement des réclamations…" />
        ) : reclamations.length === 0 ? (
          <p className="text-center py-12 text-muted-foreground">Aucune réclamation générale.</p>
        ) : (
          <>
            {enAttente.map(r => (
              <div key={r.id} className="card-base border-l-4 border-primary space-y-3">
                <div className="flex items-start justify-between">
                  <div>
                    <p className="font-semibold text-foreground">{r.nom_utilisateur}</p>
                    <p className="text-xs text-muted-foreground">
                      {r.type_utilisateur === 'SOIGNANT' ? 'Soignant' : 'Établissement'} · {r.categorie} · {format(new Date(r.cree_le), 'd MMM yyyy HH:mm', { locale: fr })}
                    </p>
                  </div>
                  <span className={`badge-base text-xs ${r.statut === 'EN_ATTENTE' ? 'bg-warning/10 text-warning' : 'bg-primary/10 text-primary'}`}>
                    {r.statut === 'EN_ATTENTE' ? 'En attente' : 'En cours'}
                  </span>
                </div>
                <p className="text-sm font-medium text-foreground">{r.sujet}</p>
                <p className="text-sm text-muted-foreground bg-muted/50 rounded-lg p-3">{r.details}</p>

                <div className="space-y-2 pt-2">
                  <textarea
                    aria-label={`Réponse à la réclamation de ${r.nom_utilisateur}`}
                    placeholder="Réponse à l'utilisateur (optionnelle)"
                    value={reponseInput[r.id] || ''}
                    onChange={e => setReponseInput(prev => ({ ...prev, [r.id]: e.target.value }))}
                    rows={2}
                    className="input-base w-full text-sm resize-none"
                  />
                  <div className="flex items-center gap-2">
                    <select
                      aria-label={`Statut de la réclamation de ${r.nom_utilisateur}`}
                      value={statutInput[r.id] || 'RESOLUE'}
                      onChange={e => setStatutInput(prev => ({ ...prev, [r.id]: e.target.value }))}
                      className="input-base text-sm"
                    >
                      {STATUT_OPTIONS.map(s => (
                        <option key={s.value} value={s.value}>{s.label}</option>
                      ))}
                    </select>
                    <div className="flex-1" />
                    <BoutonY2K
                      size="sm"
                      onClick={() => traiter(r.id)}
                      disabled={traitement === r.id}
                      loading={traitement === r.id}
                      className="gap-1"
                      iconeGauche={traitement === r.id ? undefined : <Send className="h-3.5 w-3.5" />}
                    >
                      Traiter
                    </BoutonY2K>
                  </div>
                </div>
              </div>
            ))}

            {traitees.length > 0 && (
              <div className="space-y-2 mt-6">
                <h2 className="text-base font-semibold text-muted-foreground">
                  Traitées ({traitees.length})
                </h2>
                {traitees.map(r => (
                  <div key={r.id} className="flex items-center justify-between p-3 bg-muted/30 rounded-xl">
                    <div>
                      <span className="text-sm text-foreground">{r.nom_utilisateur}</span>
                      <span className="text-xs text-muted-foreground ml-2">{r.sujet}</span>
                    </div>
                    <span className={`badge-base text-[10px] ${r.statut === 'RESOLUE' ? 'bg-success/10 text-success' : 'bg-muted text-muted-foreground'}`}>
                      {r.statut === 'RESOLUE' ? 'Résolue' : 'Fermée'}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </div>
        </TabsContent>

        <TabsContent value="score" className="mt-0">
          <ReclamationsScoreContent />
        </TabsContent>

        <TabsContent value="triage" className="mt-0">
          <ScoreTriageContent />
        </TabsContent>
      </Tabs>
    </LayoutAdmin>
  );
}
