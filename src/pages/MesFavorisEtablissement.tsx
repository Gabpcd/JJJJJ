import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Star, ShieldCheck, ChevronRight, Send, Check, Siren } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { getLabelProfession } from '@/lib/constantes';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { Button } from '@/components/ui/button';

interface FavoriSoignant {
  soignant_id: string;
  prenom: string;
  nom_initiale: string;
  profession: string;
  specialite_medicale: string | null;
  avatar_url: string | null;
  score_fiabilite: number | null;
  note_moyenne: number | null;
  rpps_verifie: boolean;
  tous_documents_valides: boolean;
  disponible_urgence: boolean;
  cree_le: string;
}

interface MissionOuverte {
  id: string;
  intitule: string;
  debut_le: string;
  profession_requise: string;
}

export default function MesFavorisEtablissement() {
  usePageTitle('Mes favoris');
  const navigate = useNavigate();
  const { etablissementId } = useEtablissementScope();
  const [items, setItems] = useState<FavoriSoignant[]>([]);
  const [missions, setMissions] = useState<MissionOuverte[]>([]);
  const [loading, setLoading] = useState(true);
  const [openSend, setOpenSend] = useState<string | null>(null);

  const charger = async () => {
    setLoading(true);
    const [{ data: favs, error: e1 }, { data: missionsData }] = await Promise.all([
      supabase.rpc('fn_mes_favoris_soignants' as any),
      etablissementId
        ? supabase.from('missions').select('id, intitule, debut_le, profession_requise')
            .eq('etablissement_id', etablissementId).eq('statut', 'OUVERTE')
            .gt('debut_le', new Date().toISOString())
            .order('debut_le', { ascending: true }).limit(20)
        : Promise.resolve({ data: [] as MissionOuverte[] }),
    ]);
    if (e1) toast.error(e1.message);
    if (Array.isArray(favs)) setItems(favs as FavoriSoignant[]);
    setMissions((missionsData ?? []) as MissionOuverte[]);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [etablissementId]);

  const inviter = async (soignant: FavoriSoignant, mission: MissionOuverte) => {
    const { data, error } = await supabase
      .from('candidatures')
      .insert({
        mission_id: mission.id,
        soignant_id: soignant.soignant_id,
        statut: 'PROPOSEE',
        message: 'Invitation directe par établissement (favori)',
      })
      .select('id')
      .maybeSingle();
    if (error) { toast.error(error.message); return; }
    if (data?.id) {
      toast.success(`${soignant.prenom} invité·e à la mission`);
      setOpenSend(null);
    }
  };

  const retirer = async (soignant_id: string) => {
    if (!confirm('Retirer ce soignant de vos favoris ?')) return;
    const { error } = await supabase
      .from('favoris_etab_soignant' as any)
      .delete()
      .eq('soignant_id', soignant_id)
      .eq('etablissement_id', etablissementId);
    if (error) { toast.error(error.message); return; }
    toast.success('Retiré des favoris');
    charger();
  };

  const Avatar = ({ s, taille = 'sm' }: { s: FavoriSoignant; taille?: 'sm' | 'md' }) => {
    const sizeClass = taille === 'md' ? 'h-14 w-14 text-lg' : 'h-10 w-10 text-sm';
    return s.avatar_url ? (
      <img src={s.avatar_url} alt="" className={`${sizeClass} rounded-2xl object-cover border border-border shrink-0`} />
    ) : (
      <div className={`${sizeClass} rounded-2xl border border-border bg-muted flex items-center justify-center font-bold shrink-0`}>
        {(s.prenom?.[0] ?? '') + (s.nom_initiale?.[0] ?? '')}
      </div>
    );
  };

  const SelecteurMission = ({ s }: { s: FavoriSoignant }) => (
    <div className="flex items-center gap-2 flex-1">
      <select
        onChange={(e) => {
          const m = missions.find((mm) => mm.id === e.target.value);
          if (m) inviter(s, m);
        }}
        className="text-xs px-2 py-1.5 rounded-lg border border-border bg-background flex-1"
        defaultValue=""
        onClick={(e) => e.stopPropagation()}
      >
        <option value="" disabled>Choisir une mission…</option>
        {missions.map((m) => (
          <option key={m.id} value={m.id}>
            {m.intitule} · {format(new Date(m.debut_le), 'd MMM HH:mm', { locale: fr })}
          </option>
        ))}
      </select>
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); setOpenSend(null); }}
        className="text-xs text-muted-foreground hover:underline"
      >
        Annuler
      </button>
    </div>
  );

  const colonnes: ColonneTableau<FavoriSoignant>[] = [
    { cle: 'soignant', titre: 'Soignant' },
    { cle: 'score', titre: 'Score / Note' },
    { cle: 'badges', titre: 'Vérifications' },
    { cle: 'depuis', titre: 'Favori depuis' },
    { cle: 'actions', titre: '', align: 'right', largeur: 'w-72' },
  ];

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <Star className="h-6 w-6 text-warning fill-warning" /> Mes soignants favoris
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Soignants que vous appréciez : prioritaires dans le matching et invitables directement.
        </p>
      </div>

      {loading ? (
        <ChargementPage />
      ) : (
        <TableOuCartes
          colonnes={colonnes}
          donnees={items}
          getId={(s) => s.soignant_id}
          onClickLigne={(s) => navigate(`/etablissement/soignants/${s.soignant_id}`)}
          etatVide={
            <EmptyState
              icone={<Star />}
              mascotte="thinking"
              titre="Aucun soignant favori"
              description="Ajoutez des soignants depuis l'annuaire ou la fiche profil détaillée."
              cta={{
                label: "Aller à l'annuaire",
                onClick: () => navigate('/etablissement/soignants'),
                variant: 'secondary',
              }}
            />
          }
          renduCellule={(s, col) => {
            switch (col.cle) {
              case 'soignant':
                return (
                  <div className="flex items-center gap-2 min-w-0">
                    <Avatar s={s} />
                    <div className="min-w-0">
                      <p className="font-medium text-foreground truncate">{s.prenom} {s.nom_initiale}</p>
                      <p className="text-xs text-muted-foreground truncate">
                        {getLabelProfession(s.profession)}
                        {s.specialite_medicale && ` · ${s.specialite_medicale}`}
                      </p>
                    </div>
                  </div>
                );
              case 'score':
                return (
                  <div className="flex flex-wrap items-center gap-1.5 text-xs">
                    {s.score_fiabilite != null && (
                      <span className="inline-flex items-center gap-1 rounded-full bg-primary/10 text-primary px-2 py-0.5 font-medium">
                        <ShieldCheck className="h-3 w-3" /> {s.score_fiabilite}/100
                      </span>
                    )}
                    {s.note_moyenne != null && (
                      <span className="inline-flex items-center gap-1 rounded-full bg-amber-50 text-amber-700 px-2 py-0.5 font-medium">
                        <Star className="h-3 w-3" aria-hidden="true" /> {Number(s.note_moyenne).toFixed(1)}
                      </span>
                    )}
                  </div>
                );
              case 'badges':
                return (
                  <div className="flex flex-wrap items-center gap-1 text-[10px]">
                    {s.rpps_verifie && <span className="badge-base bg-success/10 text-success">RPPS <Check className="inline-block h-3 w-3" aria-hidden="true" /></span>}
                    {s.tous_documents_valides && <span className="badge-base bg-success/10 text-success">Docs <Check className="inline-block h-3 w-3" aria-hidden="true" /></span>}
                    {s.disponible_urgence && <span className="badge-base bg-orange-50 text-orange-700"><Siren className="inline-block h-3 w-3 mr-0.5" aria-hidden="true" />Urgence</span>}
                  </div>
                );
              case 'depuis':
                return <span className="text-xs text-muted-foreground whitespace-nowrap">{format(new Date(s.cree_le), 'd MMM yyyy', { locale: fr })}</span>;
              case 'actions':
                return (
                  <div className="flex items-center justify-end gap-2" onClick={(e) => e.stopPropagation()}>
                    {missions.length > 0 ? (
                      openSend === s.soignant_id ? (
                        <SelecteurMission s={s} />
                      ) : (
                        <Button
                          size="sm"
                          variant="default"
                          className="h-8 text-xs"
                          onClick={(e) => { e.stopPropagation(); setOpenSend(s.soignant_id); }}
                        >
                          <Send className="h-3.5 w-3.5 mr-1" /> Inviter
                        </Button>
                      )
                    ) : (
                      <span className="text-[11px] text-muted-foreground italic">Aucune mission ouverte</span>
                    )}
                    <button
                      type="button"
                      onClick={(e) => { e.stopPropagation(); retirer(s.soignant_id); }}
                      className="text-xs text-muted-foreground hover:text-destructive hover:underline"
                    >
                      Retirer
                    </button>
                  </div>
                );
              default:
                return null;
            }
          }}
          renduCarte={(s) => (
            <div className="flex items-start gap-3">
              <Avatar s={s} taille="md" />
              <div className="flex-1 min-w-0">
                <div className="flex items-start justify-between gap-2 mb-1">
                  <div className="min-w-0">
                    <h2 className="font-semibold text-foreground truncate">{s.prenom} {s.nom_initiale}</h2>
                    <p className="text-xs text-muted-foreground">
                      {getLabelProfession(s.profession)}
                      {s.specialite_medicale && ` · ${s.specialite_medicale}`}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={(e) => { e.stopPropagation(); navigate(`/etablissement/soignants/${s.soignant_id}`); }}
                    className="text-xs text-primary hover:underline inline-flex items-center gap-1 shrink-0"
                  >
                    Profil <ChevronRight className="h-3 w-3" />
                  </button>
                </div>

                <div className="flex flex-wrap items-center gap-1.5 text-xs">
                  {s.score_fiabilite != null && (
                    <span className="inline-flex items-center gap-1 rounded-full bg-primary/10 text-primary px-2 py-0.5 font-medium">
                      <ShieldCheck className="h-3 w-3" /> {s.score_fiabilite}/100
                    </span>
                  )}
                  {s.note_moyenne != null && (
                    <span className="inline-flex items-center gap-1 rounded-full bg-amber-50 text-amber-700 px-2 py-0.5 font-medium">
                      <Star className="h-3 w-3" aria-hidden="true" /> {Number(s.note_moyenne).toFixed(1)}
                    </span>
                  )}
                  {s.rpps_verifie && <span className="badge-base bg-success/10 text-success text-[10px]">RPPS <Check className="inline-block h-3 w-3" aria-hidden="true" /></span>}
                  {s.tous_documents_valides && <span className="badge-base bg-success/10 text-success text-[10px]">Docs <Check className="inline-block h-3 w-3" aria-hidden="true" /></span>}
                  {s.disponible_urgence && <span className="badge-base bg-orange-50 text-orange-700 text-[10px]"><Siren className="inline-block h-3 w-3 mr-0.5" aria-hidden="true" />Urgence</span>}
                </div>

                <p className="text-xs text-muted-foreground mt-2">
                  Favori depuis le {format(new Date(s.cree_le), 'd MMM yyyy', { locale: fr })}
                </p>

                <div className="flex items-center gap-2 mt-3 pt-2 border-t border-border" onClick={(e) => e.stopPropagation()}>
                  {missions.length > 0 ? (
                    openSend === s.soignant_id ? (
                      <SelecteurMission s={s} />
                    ) : (
                      <Button
                        size="sm"
                        variant="default"
                        className="min-h-[44px] text-xs"
                        onClick={(e) => { e.stopPropagation(); setOpenSend(s.soignant_id); }}
                      >
                        <Send className="h-3.5 w-3.5 mr-1.5" /> Inviter à une mission
                      </Button>
                    )
                  ) : (
                    <span className="text-xs text-muted-foreground italic">Pas de mission ouverte à proposer</span>
                  )}
                  <button
                    type="button"
                    onClick={(e) => { e.stopPropagation(); retirer(s.soignant_id); }}
                    className="text-xs text-muted-foreground hover:text-destructive hover:underline ml-auto min-h-[44px] px-2"
                  >
                    Retirer
                  </button>
                </div>
              </div>
            </div>
          )}
        />
      )}
    </LayoutApp>
  );
}
