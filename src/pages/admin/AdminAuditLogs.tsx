import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Search, RefreshCw, ChevronLeft, ChevronRight, Shield, Clock } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

const ACTIONS_COLORS: Record<string, string> = {
  'RGPD_SUPPRESSION_COMPTE': 'bg-destructive/10 text-destructive',
  'RGPD_EXPORT_DONNEES': 'bg-info/10 text-info',
  'DOCUMENT_VERIFICATION_AUTO': 'bg-primary/10 text-primary',
  'GPS_CONSENTEMENT_ACTIVE': 'bg-success/10 text-success',
  'GPS_CONSENTEMENT_RETIRE': 'bg-warning/10 text-warning',
  'SMS_CONSENTEMENT_ACTIVE': 'bg-success/10 text-success',
  'SMS_CONSENTEMENT_RETIRE': 'bg-warning/10 text-warning',
  'DONNEES_PERSO_MODIFICATION': 'bg-info/10 text-info',
  'DONNEES_PERSO_CONSULTATION': 'bg-muted text-muted-foreground',
  // Sprint 6 PR 11 — anti-triche pointage filtres (Fix P1-15)
  'POINTAGE': 'bg-warning/10 text-warning',
  'ADMIN_ACTION': 'bg-primary/10 text-primary',
};

// Sprint 6 PR 11 — Evenements anti-triche dans details->>'evenement' (Fix P1-15)
const EVENEMENTS_ANTITRICHE = [
  'TELEPORTATION_DETECTED',
  'POINTAGE_INCOHERENT',
  'QR_SCAN_GPS_ELOIGNE',
  'GPS_SPOOFING_DETECTED',
  'MOCK_GPS_DETECTED',
  'ALERTE_POINTAGE_TRAITEE',
];

// Libellés français pour l'affichage — les valeurs techniques envoyées aux requêtes restent inchangées
const ACTIONS_LIBELLES: Record<string, string> = {
  'RGPD_SUPPRESSION_COMPTE': 'Suppression de compte (RGPD)',
  'RGPD_EXPORT_DONNEES': 'Export de données (RGPD)',
  'DOCUMENT_VERIFICATION_AUTO': 'Vérification automatique de document',
  'GPS_CONSENTEMENT_ACTIVE': 'Consentement GPS activé',
  'GPS_CONSENTEMENT_RETIRE': 'Consentement GPS retiré',
  'SMS_CONSENTEMENT_ACTIVE': 'Consentement SMS activé',
  'SMS_CONSENTEMENT_RETIRE': 'Consentement SMS retiré',
  'DONNEES_PERSO_MODIFICATION': 'Modification de données personnelles',
  'DONNEES_PERSO_CONSULTATION': 'Consultation de données personnelles',
  'POINTAGE': 'Pointage',
  'ADMIN_ACTION': 'Action administrateur',
};

const ACTEURS_LIBELLES: Record<string, string> = {
  'SOIGNANT': 'Soignant',
  'ADMIN_ETABLISSEMENT': 'Admin établissement',
  'ADMIN_PLATEFORME': 'Admin plateforme',
  'SYSTEME': 'Système',
};

const EVENEMENTS_LIBELLES: Record<string, string> = {
  'TELEPORTATION_DETECTED': 'Téléportation détectée',
  'POINTAGE_INCOHERENT': 'Pointage incohérent',
  'QR_SCAN_GPS_ELOIGNE': 'Scan QR avec GPS éloigné',
  'GPS_SPOOFING_DETECTED': 'Falsification GPS détectée',
  'MOCK_GPS_DETECTED': 'GPS simulé détecté',
  'ALERTE_POINTAGE_TRAITEE': 'Alerte de pointage traitée',
};

const RESSOURCES_LIBELLES: Record<string, string> = {
  'bulletin_paie': 'Bulletin de paie',
  'candidature': 'Candidature',
  'etablissement': 'Établissement',
  'facture': 'Facture',
  'facture_honoraire': 'Facture d\'honoraires',
  'filtre_sauvegarde': 'Filtre sauvegardé',
  'litige': 'Litige',
  'mandat_facturation': 'Mandat de facturation',
  'mission': 'Mission',
  'notation': 'Notation',
  'parrainage': 'Parrainage',
  'parrainage_etab': 'Parrainage établissement',
  'preferences': 'Préférences',
  'prevoyance_liste_attente': 'Liste d\'attente prévoyance',
  'signalement': 'Signalement',
  'soignant': 'Soignant',
};

const libelleAction = (action: string) => ACTIONS_LIBELLES[action] ?? action;
const libelleActeur = (type: string) => ACTEURS_LIBELLES[type] ?? type;
const libelleEvenement = (evenement: string) => EVENEMENTS_LIBELLES[evenement] ?? evenement;
const libelleRessource = (type: string) => RESSOURCES_LIBELLES[type] ?? type;

const PAGE_SIZE = 50;

export default function AdminAuditLogs() {
  usePageTitle('Journaux d\'audit');
  const [loading, setLoading] = useState(true);
  const [logs, setLogs] = useState<any[]>([]);
  const [page, setPage] = useState(0);
  const [hasMore, setHasMore] = useState(true);
  const [search, setSearch] = useState('');
  const [filterAction, setFilterAction] = useState('');
  const [filterType, setFilterType] = useState('');
  const [filterEvenement, setFilterEvenement] = useState('');

  const charger = async () => {
    setLoading(true);
    let query = supabase
      .from('journaux_audit')
      .select('*')
      .order('cree_le', { ascending: false })
      .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

    if (filterAction) query = query.eq('action', filterAction);
    if (filterType) query = query.eq('type_acteur', filterType);
    if (filterEvenement) {
      // Sprint 6 PR 11 — filtre événements anti-triche via details->>'evenement' jsonb
      query = (query as any).eq('details->>evenement', filterEvenement);
    }
    if (search) query = query.or(`action.ilike.%${search}%,type_ressource.ilike.%${search}%`);

    const { data } = await query;
    setLogs(data || []);
    setHasMore((data || []).length === PAGE_SIZE);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [page, filterAction, filterType, filterEvenement]);

  const actions = ['RGPD_SUPPRESSION_COMPTE', 'RGPD_EXPORT_DONNEES', 'DOCUMENT_VERIFICATION_AUTO', 'GPS_CONSENTEMENT_ACTIVE', 'GPS_CONSENTEMENT_RETIRE', 'SMS_CONSENTEMENT_ACTIVE', 'SMS_CONSENTEMENT_RETIRE', 'DONNEES_PERSO_MODIFICATION', 'DONNEES_PERSO_CONSULTATION', 'POINTAGE', 'ADMIN_ACTION'];
  const types = ['SOIGNANT', 'ADMIN_ETABLISSEMENT', 'ADMIN_PLATEFORME', 'SYSTEME'];

  return (
    <LayoutAdmin>
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-6 gap-3">
        <div>
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2"><Shield className="h-5 w-5 text-primary" /> Journaux d'audit</h1>
          <p className="text-sm text-muted-foreground">Traçabilité RGPD des actions sensibles</p>
        </div>
        <BoutonY2K variant="ghost" size="sm" onClick={() => { setPage(0); charger(); }} aria-label="Rafraîchir">
          <RefreshCw className="h-4 w-4" />
        </BoutonY2K>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-3 mb-4">
        <div className="flex-1 min-w-[200px]">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && charger()}
              placeholder="Rechercher action ou ressource..."
              className="input-base pl-10"
            />
          </div>
        </div>
        <select value={filterAction} onChange={e => { setFilterAction(e.target.value); setPage(0); }} className="input-base w-auto">
          <option value="">Toutes les actions</option>
          {actions.map(a => <option key={a} value={a}>{libelleAction(a)}</option>)}
        </select>
        <select value={filterType} onChange={e => { setFilterType(e.target.value); setPage(0); }} className="input-base w-auto">
          <option value="">Tous les acteurs</option>
          {types.map(t => <option key={t} value={t}>{libelleActeur(t)}</option>)}
        </select>
        <select value={filterEvenement} onChange={e => { setFilterEvenement(e.target.value); setPage(0); }} className="input-base w-auto" aria-label="Filtrer par événement anti-triche">
          <option value="">Tous les événements</option>
          {EVENEMENTS_ANTITRICHE.map(e => <option key={e} value={e}>{libelleEvenement(e)}</option>)}
        </select>
      </div>

      {loading ? <ChargementPage /> : (
        <>
          {(() => {
            const colonnes: ColonneTableau<any>[] = [
              { cle: 'date', titre: 'Date' },
              { cle: 'acteur', titre: 'Acteur' },
              { cle: 'action', titre: 'Action' },
              { cle: 'ressource', titre: 'Ressource' },
              { cle: 'details', titre: 'Détails' },
            ];
            const actionBadgeVariant = (action: string): 'success' | 'warning' | 'error' | 'info' => {
              const cls = ACTIONS_COLORS[action] || '';
              if (cls.includes('destructive')) return 'error';
              if (cls.includes('success')) return 'success';
              if (cls.includes('warning')) return 'warning';
              return 'info';
            };
            const actionBadge = (log: any) => (
              <BadgeY2K variant={actionBadgeVariant(log.action)} size="sm">
                {libelleAction(log.action)}
              </BadgeY2K>
            );
            const dateFormatted = (log: any) => log.cree_le ? format(new Date(log.cree_le), 'dd/MM/yy HH:mm', { locale: fr }) : '—';
            const detailsContent = (log: any) =>
              log.details ? (
                <details className="text-[10px]">
                  <summary className="cursor-pointer text-primary hover:underline">Voir</summary>
                  <pre className="mt-1 p-2 bg-muted/50 rounded text-[9px] text-muted-foreground overflow-x-auto max-w-[300px]">
                    {JSON.stringify(log.details, null, 2)}
                  </pre>
                </details>
              ) : <span className="text-muted-foreground/40">—</span>;

            return (
              <TableOuCartes
                colonnes={colonnes}
                donnees={logs}
                getId={(log: any) => log.id}
                etatVide={<EmptyState titre="Aucun événement trouvé" description="Aucun événement audit ne correspond aux filtres." />}
                renduCellule={(log: any, col) => {
                  switch (col.cle) {
                    case 'date':
                      return (
                        <div className="flex items-center gap-1.5 text-muted-foreground whitespace-nowrap">
                          <Clock className="h-3 w-3" />
                          {dateFormatted(log)}
                        </div>
                      );
                    case 'acteur':
                      return (
                        <div>
                          <span className="text-xs font-mono text-muted-foreground">{libelleActeur(log.type_acteur)}</span>
                          <p className="text-[10px] text-muted-foreground/60 font-mono truncate max-w-[120px]">{log.acteur_id?.slice(0, 8)}...</p>
                        </div>
                      );
                    case 'action':
                      return actionBadge(log);
                    case 'ressource':
                      return (
                        <div className="text-muted-foreground">
                          <span className="text-xs">{libelleRessource(log.type_ressource)}</span>
                          {log.id_ressource && <p className="text-[10px] text-muted-foreground/60 font-mono truncate max-w-[120px]">{log.id_ressource?.slice(0, 8)}...</p>}
                        </div>
                      );
                    case 'details':
                      return detailsContent(log);
                    default:
                      return null;
                  }
                }}
                renduCarte={(log: any) => (
                  <div className="space-y-2">
                    <div className="flex items-start justify-between gap-2">
                      {actionBadge(log)}
                      <div className="flex items-center gap-1.5 text-xs text-muted-foreground whitespace-nowrap shrink-0">
                        <Clock className="h-3 w-3" />
                        {dateFormatted(log)}
                      </div>
                    </div>
                    <div className="text-xs text-muted-foreground space-y-0.5">
                      <p>Acteur : <span className="font-mono">{libelleActeur(log.type_acteur)}</span> · {log.acteur_id?.slice(0, 8)}…</p>
                      <p>Ressource : <span className="font-mono">{libelleRessource(log.type_ressource)}</span>{log.id_ressource && <> · {log.id_ressource?.slice(0, 8)}…</>}</p>
                    </div>
                    {log.details && <div className="pt-1 border-t border-border">{detailsContent(log)}</div>}
                  </div>
                )}
              />
            );
          })()}

          {/* Pagination */}
          <div className="flex items-center justify-between mt-4">
            <p className="text-xs text-muted-foreground">{logs.length} résultat{logs.length > 1 ? 's' : ''} — page {page + 1}</p>
            <div className="flex gap-2">
              <BoutonY2K variant="ghost" size="sm" onClick={() => setPage(p => Math.max(0, p - 1))} disabled={page === 0} aria-label="Page précédente">
                <ChevronLeft className="h-4 w-4" />
              </BoutonY2K>
              <BoutonY2K variant="ghost" size="sm" onClick={() => setPage(p => p + 1)} disabled={!hasMore} aria-label="Page suivante">
                <ChevronRight className="h-4 w-4" />
              </BoutonY2K>
            </div>
          </div>
        </>
      )}
    </LayoutAdmin>
  );
}
