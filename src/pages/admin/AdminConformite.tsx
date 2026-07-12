import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { supabase } from '@/integrations/supabase/client';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BADGES_STATUT, getLabelProfession } from '@/lib/constantes';
import { AlertTriangle, ShieldAlert, Clock, FileWarning, FileQuestion, Repeat, UserX, FileX, ChevronDown, Loader2, ExternalLink } from 'lucide-react';

/** Libellés français des résultats de contrôle (table conformite_travail). */
const LIBELLES_RESULTAT_CONTROLE: Record<string, string> = {
  'CONFORME': 'Conforme',
  'VIOLATION_BLOQUEE': 'Violation bloquée',
};

function libelleResultat(valeur?: string): string {
  if (!valeur) return '—';
  const libelle = LIBELLES_RESULTAT_CONTROLE[valeur];
  if (libelle) return libelle;
  const texte = valeur.replace(/_/g, ' ').toLowerCase();
  return texte.charAt(0).toUpperCase() + texte.slice(1);
}

interface Champ {
  /** Titre de colonne (desktop) / label (mobile) */
  titre: string;
  /** Rendu de la valeur, identique desktop/mobile */
  render: (item: any) => React.ReactNode;
  /** Marqué primary = affiché en grand/bold sur la card mobile (1er champ) */
  primary?: boolean;
}

interface Indicateur {
  cle: string;
  rpcCle: string;
  label: string;
  icone: React.ElementType;
  champs: Champ[];
}

const formatDate = (d?: string) => d ? new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' }) : '—';

function LienAdmin({ to, children }: { to: string; children: React.ReactNode }) {
  return (
    <Link
      to={to}
      className="group inline-flex items-center gap-1 text-primary hover:underline"
      onClick={(e) => e.stopPropagation()}
    >
      {children}
      <ExternalLink className="h-3 w-3 opacity-0 transition-opacity group-hover:opacity-100" />
    </Link>
  );
}

function LienSoignant({ id, nom }: { id?: string; nom?: string }) {
  if (!id || !nom) return <span>{nom ?? '—'}</span>;
  return <LienAdmin to={`/admin/utilisateurs/${id}`}>{nom}</LienAdmin>;
}

function LienMission({ id, intitule }: { id?: string; intitule?: string }) {
  if (!id || !intitule) return <span>{intitule ?? '—'}</span>;
  return <LienAdmin to={`/admin/missions/${id}`}>{intitule}</LienAdmin>;
}

function LienEtablissement({ id, nom }: { id?: string; nom?: string }) {
  if (!id || !nom) return <span>{nom ?? '—'}</span>;
  return <LienAdmin to={`/admin/utilisateurs/${id}`}>{nom}</LienAdmin>;
}

const INDICATEURS: Indicateur[] = [
  {
    cle: 'violations_repos_11h',
    rpcCle: 'repos_11h_violations',
    label: 'Violations repos 11h',
    icone: Clock,
    champs: [
      { titre: 'Soignant', primary: true, render: (i) => <LienSoignant id={i.soignant_id} nom={i.soignant_nom} /> },
      { titre: 'Mission', render: (i) => <LienMission id={i.mission_id} intitule={i.mission_intitule} /> },
      { titre: 'Établissement', render: (i) => <LienEtablissement id={i.etablissement_id} nom={i.etablissement_nom} /> },
      { titre: 'Résultat', render: (i) => <BadgeY2K variant="error" size="sm">{libelleResultat(i.resultat)}</BadgeY2K> },
      { titre: 'Date', render: (i) => <span className="text-muted-foreground">{formatDate(i.controle_le)}</span> },
    ],
  },
  {
    cle: 'alertes_48h',
    rpcCle: 'plafond_48h_alertes',
    label: 'Alertes 48h',
    icone: ShieldAlert,
    champs: [
      { titre: 'Soignant', primary: true, render: (i) => <LienSoignant id={i.soignant_id} nom={i.soignant_nom} /> },
      { titre: 'Mission', render: (i) => <LienMission id={i.mission_id} intitule={i.mission_intitule} /> },
      { titre: 'Établissement', render: (i) => <LienEtablissement id={i.etablissement_id} nom={i.etablissement_nom} /> },
      { titre: 'Profession', render: (i) => <BadgeY2K variant="info" size="sm">{getLabelProfession(i.profession)}</BadgeY2K> },
      { titre: 'Heures semaine', render: (i) => <span className="font-semibold text-destructive">{i.heures_semaine}h</span> },
    ],
  },
  {
    cle: 'docs_expires',
    rpcCle: 'documents_expires',
    label: 'Documents expirés',
    icone: FileWarning,
    champs: [
      { titre: 'Soignant', primary: true, render: (i) => <LienSoignant id={i.soignant_id} nom={i.soignant_nom} /> },
      { titre: 'Mission', render: (i) => <LienMission id={i.mission_id} intitule={i.mission_intitule} /> },
      { titre: 'Établissement', render: (i) => <LienEtablissement id={i.etablissement_id} nom={i.etablissement_nom} /> },
      { titre: 'Profession', render: (i) => <BadgeY2K variant="info" size="sm">{getLabelProfession(i.profession)}</BadgeY2K> },
      { titre: 'Document', render: (i) => i.type_document },
      { titre: 'Expiré le', render: (i) => <span className="text-destructive">{formatDate(i.valide_jusqua)}</span> },
    ],
  },
  {
    cle: 'docs_en_attente',
    rpcCle: 'documents_en_attente',
    label: 'Documents en attente',
    icone: FileQuestion,
    champs: [
      { titre: 'Soignant', primary: true, render: (i) => <LienSoignant id={i.soignant_id} nom={i.soignant_nom} /> },
      { titre: 'Mission', render: (i) => <LienMission id={i.mission_id} intitule={i.mission_intitule} /> },
      { titre: 'Établissement', render: (i) => <LienEtablissement id={i.etablissement_id} nom={i.etablissement_nom} /> },
      { titre: 'Profession', render: (i) => <BadgeY2K variant="info" size="sm">{getLabelProfession(i.profession)}</BadgeY2K> },
      { titre: 'Document', render: (i) => i.type_document },
      { titre: 'Téléversé le', render: (i) => <span className="text-muted-foreground">{formatDate(i.televerse_le)}</span> },
    ],
  },
  {
    cle: 'cddu_repetitifs',
    rpcCle: 'cddu_repetitifs',
    label: 'CDD répétitifs (risque requalification CDI)',
    icone: Repeat,
    champs: [
      { titre: 'Soignant', primary: true, render: (i) => <LienSoignant id={i.soignant_id} nom={i.soignant_nom} /> },
      { titre: 'Mission', render: (i) => <LienMission id={i.mission_id} intitule={i.mission_intitule} /> },
      { titre: 'Établissement', render: (i) => <LienEtablissement id={i.etablissement_id} nom={i.etablissement_nom} /> },
      { titre: 'Nb missions', render: (i) => <span className="font-semibold">{i.nb_missions}</span> },
      { titre: 'Première', render: (i) => <span className="text-muted-foreground">{formatDate(i.premiere_mission)}</span> },
      { titre: 'Dernière', render: (i) => <span className="text-muted-foreground">{formatDate(i.derniere_mission)}</span> },
    ],
  },
  {
    cle: 'soignants_sans_docs',
    rpcCle: 'soignants_sans_docs',
    label: 'Soignants sans documents',
    icone: UserX,
    champs: [
      { titre: 'Soignant', primary: true, render: (i) => <LienSoignant id={i.soignant_id} nom={i.soignant_nom} /> },
      { titre: 'Mission', render: (i) => <LienMission id={i.mission_id} intitule={i.mission_intitule} /> },
      { titre: 'Établissement', render: (i) => <LienEtablissement id={i.etablissement_id} nom={i.etablissement_nom} /> },
      { titre: 'Profession', render: (i) => <BadgeY2K variant="info" size="sm">{getLabelProfession(i.profession)}</BadgeY2K> },
      { titre: 'Email', render: (i) => i.email
        ? <a href={`mailto:${i.email}`} className="text-primary hover:underline" onClick={(e) => e.stopPropagation()}>{i.email}</a>
        : <span className="text-muted-foreground">—</span> },
      { titre: 'Inscrit le', render: (i) => <span className="text-muted-foreground">{formatDate(i.cree_le)}</span> },
    ],
  },
  {
    cle: 'missions_sans_contrat',
    rpcCle: 'missions_sans_contrat',
    label: 'Missions sans contrat',
    icone: FileX,
    champs: [
      { titre: 'Mission', primary: true, render: (i) => <LienMission id={i.mission_id ?? i.id} intitule={i.intitule} /> },
      { titre: 'Établissement', render: (i) => <LienEtablissement id={i.etablissement_id} nom={i.etablissement_nom} /> },
      { titre: 'Soignant', render: (i) => <LienSoignant id={i.soignant_id} nom={i.soignant_nom} /> },
      { titre: 'Statut', render: (i) => <BadgeY2K variant="info" size="sm">{BADGES_STATUT[i.statut]?.label || i.statut}</BadgeY2K> },
      { titre: 'Début', render: (i) => <span className="text-muted-foreground">{formatDate(i.debut_le)}</span> },
    ],
  },
];

function getCouleur(val: number): string {
  if (val === 0) return 'text-success';
  if (val <= 5) return 'text-warning';
  return 'text-destructive';
}

function getBgCouleur(val: number): string {
  if (val === 0) return 'bg-success/10 border-success/20';
  if (val <= 5) return 'bg-warning/10 border-warning/20';
  return 'bg-destructive/10 border-destructive/20';
}

export default function AdminConformite() {
  usePageTitle('Conformité');
  const [data, setData] = useState<Record<string, number> | null>(null);
  const [loading, setLoading] = useState(true);
  const [erreur, setErreur] = useState<string | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [detail, setDetail] = useState<any[] | null>(null);
  const [loadingDetail, setLoadingDetail] = useState(false);

  useEffect(() => {
    (supabase.rpc('fn_admin_conformite' as any) as any).then(({ data: d, error: e }: any) => {
      if (e) {
        console.warn('fn_admin_conformite error:', e);
        setErreur('Le contrôle de conformité est indisponible. Aucun indicateur ne peut être considéré comme conforme.');
      }
      else if (d && typeof d === 'object' && !Array.isArray(d)) setData(d);
      else if (Array.isArray(d) && d.length > 0 && typeof d[0] === 'object') setData(d[0]);
      else {
        console.warn('fn_admin_conformite: unexpected response shape', d);
        setErreur('La réponse du contrôle de conformité est invalide. Aucun résultat n’est affiché.');
      }
      setLoading(false);
    }).catch((err: any) => {
      console.warn('fn_admin_conformite exception:', err);
      setErreur('Le contrôle de conformité est indisponible. Aucun indicateur ne peut être considéré comme conforme.');
      setLoading(false);
    });
  }, []);

  async function toggleDetail(cle: string) {
    if (selected === cle) {
      setSelected(null);
      setDetail(null);
      return;
    }
    setSelected(cle);
    setDetail(null);
    setLoadingDetail(true);
    const { data: d, error } = await supabase.rpc('fn_admin_conformite_detail' as any, { p_type: cle });
    if (error) {
      setDetail(null);
      setErreur(`Impossible de charger le détail « ${INDICATEURS.find((i) => i.cle === cle)?.label ?? cle} ».`);
    } else {
      setDetail(Array.isArray(d) ? d : []);
    }
    setLoadingDetail(false);
  }

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Conformité" /></LayoutAdmin>;

  const mappedData: Record<string, number> = {};
  if (data) {
    INDICATEURS.forEach((ind) => {
      mappedData[ind.cle] = data[ind.cle] ?? data[ind.rpcCle] ?? 0;
    });
  }

  const selectedInd = INDICATEURS.find((i) => i.cle === selected);

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Conformité" />
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-foreground">Conformité</h1>

        {erreur && (
          <div role="alert" className="rounded-xl border border-destructive/40 bg-destructive/10 p-4 text-sm text-destructive flex items-start gap-2">
            <AlertTriangle className="h-5 w-5 shrink-0" />
            <div>
              <p className="font-semibold">Résultats indisponibles</p>
              <p className="mt-1">{erreur}</p>
            </div>
          </div>
        )}

        {!erreur && data && <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {INDICATEURS.map((ind) => {
            const val = mappedData[ind.cle] ?? 0;
            const isSelected = selected === ind.cle;
            return (
              <CardY2K
                noPadding
                key={ind.cle}
                className={`cursor-pointer border transition-all hover:shadow-md ${getBgCouleur(val)} ${isSelected ? 'ring-2 ring-primary' : ''}`}
                onClick={() => toggleDetail(ind.cle)}
              >
                <CardY2KContent className="flex items-center gap-4 pt-5 pb-5">
                  <div className={`rounded-xl p-2.5 ${getBgCouleur(val)}`}>
                    <ind.icone className={`h-5 w-5 ${getCouleur(val)}`} />
                  </div>
                  <div className="flex-1">
                    <p className={`text-2xl font-bold ${getCouleur(val)}`}>{val}</p>
                    <p className="text-xs text-muted-foreground">{ind.label}</p>
                  </div>
                  <ChevronDown className={`h-4 w-4 text-muted-foreground transition-transform ${isSelected ? 'rotate-180' : ''}`} />
                </CardY2KContent>
              </CardY2K>
            );
          })}
        </div>}

        {!erreur && selected && selectedInd && (
          <CardY2K noPadding className="animate-in slide-in-from-top-2 fade-in-0 duration-200">
            <CardY2KContent className="pt-5">
              <div className="mb-4 flex items-center gap-2">
                <selectedInd.icone className="h-5 w-5 text-foreground" />
                <h2 className="text-base font-semibold text-foreground">{selectedInd.label}</h2>
                <BadgeY2K variant="info" className="ml-auto">{mappedData[selected] ?? 0} élément(s)</BadgeY2K>
              </div>

              {loadingDetail ? (
                <div className="flex justify-center py-8">
                  <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
                </div>
              ) : detail && detail.length > 0 ? (
                <>
                  {/* Desktop : table */}
                  <div className="hidden md:block overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          {selectedInd.champs.map((c) => (
                            <TableHead key={c.titre} className="text-xs">{c.titre}</TableHead>
                          ))}
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {detail.map((item: any, i: number) => (
                          <TableRow key={item.id ? `${item.id}-${i}` : i} className="text-sm">
                            {selectedInd.champs.map((c) => (
                              <TableCell key={c.titre} className={c.primary ? 'font-medium' : ''}>
                                {c.render(item)}
                              </TableCell>
                            ))}
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>

                  {/* Mobile : cards label/value */}
                  <div className="md:hidden space-y-3">
                    {detail.map((item: any, i: number) => {
                      const primaryChamp = selectedInd.champs.find((c) => c.primary);
                      const autresChamps = selectedInd.champs.filter((c) => !c.primary);
                      return (
                        <div key={item.id ? `${item.id}-${i}` : i} className="rounded-xl border border-border bg-card p-3 space-y-2">
                          {primaryChamp && (
                            <div className="text-sm font-semibold text-foreground border-b border-border/50 pb-2">
                              {primaryChamp.render(item)}
                            </div>
                          )}
                          <div className="space-y-1.5">
                            {autresChamps.map((c) => (
                              <div key={c.titre} className="flex items-start justify-between gap-3 text-xs">
                                <span className="text-muted-foreground shrink-0">{c.titre}</span>
                                <span className="text-foreground text-right min-w-0 break-words">{c.render(item)}</span>
                              </div>
                            ))}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </>
              ) : (
                <p className="py-6 text-center text-sm text-muted-foreground">Aucun élément à afficher</p>
              )}
            </CardY2KContent>
          </CardY2K>
        )}
      </div>
    </LayoutAdmin>
  );
}
