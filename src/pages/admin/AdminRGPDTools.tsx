// Export des 500 dernières demandes RGPD (suppressions + exports)
// depuis le journal d'audit sécurisé.

import { useCallback, useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { supabase } from '@/integrations/supabase/client';
import {
  Shield,
  Download,
  RefreshCw,
  FileJson,
} from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { CardY2K } from '@/components/y2k/CardY2K';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { telechargerOuPartager } from '@/lib/telechargement';

const EXPORT_LIMIT = 500;

const ACTIONS_RGPD = ['RGPD_SUPPRESSION_COMPTE', 'RGPD_EXPORT_DONNEES'];

// Libellés français pour l'affichage uniquement — les valeurs brutes restent
// utilisées dans les requêtes et l'export JSON.
const LIBELLES_ACTION: Record<string, string> = {
  RGPD_SUPPRESSION_COMPTE: 'Suppression de compte',
  RGPD_EXPORT_DONNEES: 'Export de données',
};

const LIBELLES_TYPE_ACTEUR: Record<string, string> = {
  SOIGNANT: 'Soignant',
  ADMIN_ETABLISSEMENT: 'Admin établissement',
  ADMIN_PLATEFORME: 'Admin plateforme',
  SYSTEME: 'Système',
};

const LIBELLES_TYPE_RESSOURCE: Record<string, string> = {
  soignant: 'Soignant',
  etablissement: 'Établissement',
};

const libelle = (map: Record<string, string>, valeur: string | null | undefined) =>
  valeur ? (map[valeur] ?? valeur) : '—';

export default function AdminRGPDTools() {
  usePageTitle('Outils RGPD');

  const [loadingDemandes, setLoadingDemandes] = useState(true);
  const [demandes, setDemandes] = useState<any[]>([]);
  const [exporting, setExporting] = useState(false);

  const chargerDemandes = useCallback(async () => {
    setLoadingDemandes(true);
    const { data, error } = await supabase
      .from('journaux_audit')
      .select('*')
      .in('action', ACTIONS_RGPD)
      .order('cree_le', { ascending: false })
      .limit(EXPORT_LIMIT);

    if (error) {
      toast.error('Erreur chargement des demandes RGPD');
      setDemandes([]);
    } else {
      setDemandes(data || []);
    }
    setLoadingDemandes(false);
  }, []);

  useEffect(() => {
    chargerDemandes();
  }, [chargerDemandes]);

  const handleExportJSON = async () => {
    setExporting(true);
    try {
      const payload = {
        exported_at: new Date().toISOString(),
        nombre_demandes: demandes.length,
        limite: EXPORT_LIMIT,
        demandes: demandes.map((d) => ({
          id: d.id,
          cree_le: d.cree_le,
          action: d.action,
          type_acteur: d.type_acteur,
          acteur_id: d.acteur_id,
          type_ressource: d.type_ressource,
          id_ressource: d.id_ressource,
          details: d.details,
        })),
      };
      await telechargerOuPartager(JSON.stringify(payload, null, 2), `demandes-rgpd-${format(new Date(), 'yyyy-MM-dd-HHmmss')}.json`, 'application/json');
      toast.success(`Export JSON de ${demandes.length} demandes téléchargé`);
    } catch (e: any) {
      toast.error(`Erreur lors de l'export : ${e?.message || 'inconnue'}`);
    } finally {
      setExporting(false);
    }
  };

  return (
    <LayoutAdmin>
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <Shield className="h-5 w-5 text-primary" /> Outils RGPD
        </h1>
        <p className="text-sm text-muted-foreground">
          Suivi des demandes d'effacement (article 17) et de portabilité (article 20), avec export du journal d'audit.
        </p>
      </div>

      <div className="space-y-6 max-w-5xl">
        {/* ── Section 1 : Export demandes RGPD ── */}
        <CardY2K hoverLift={false}>
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-4 gap-3">
            <div>
              <h2 className="text-base font-semibold text-foreground flex items-center gap-2">
                <FileJson className="h-4 w-4 text-primary" /> Export demandes RGPD
              </h2>
              <p className="text-xs text-muted-foreground mt-1">
                {EXPORT_LIMIT} dernières demandes (suppressions et exports) enregistrées dans le journal d'audit sécurisé.
              </p>
            </div>
            <div className="flex gap-2">
              <BoutonY2K
                variant="ghost"
                size="sm"
                onClick={chargerDemandes}
                disabled={loadingDemandes}
                aria-label="Recharger"
                iconeGauche={<RefreshCw className={`h-4 w-4 ${loadingDemandes ? 'animate-spin' : ''}`} />}
              >
              </BoutonY2K>
              <BoutonY2K
                variant="primary"
                size="sm"
                onClick={handleExportJSON}
                disabled={exporting || loadingDemandes || demandes.length === 0}
                loading={exporting}
                iconeGauche={!exporting ? <Download className="h-4 w-4" /> : undefined}
              >
                {exporting ? 'Export…' : `Télécharger JSON (${demandes.length})`}
              </BoutonY2K>
            </div>
          </div>

          {loadingDemandes ? (
            <div className="py-8 text-center text-sm text-muted-foreground">
              Chargement des demandes…
            </div>
          ) : demandes.length === 0 ? (
            <div className="py-8 text-center text-sm text-muted-foreground">
              Aucune demande RGPD enregistrée.
            </div>
          ) : (
            <>
              {/* Desktop table */}
              <div className="hidden md:block overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-border text-left">
                      <th className="py-2 px-3 font-medium text-muted-foreground">Date</th>
                      <th className="py-2 px-3 font-medium text-muted-foreground">Action</th>
                      <th className="py-2 px-3 font-medium text-muted-foreground">Acteur</th>
                      <th className="py-2 px-3 font-medium text-muted-foreground">Ressource</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border/50">
                    {demandes.slice(0, 50).map((d) => (
                      <tr key={d.id} className="hover:bg-muted/30 transition">
                        <td className="py-2 px-3 text-muted-foreground whitespace-nowrap text-xs">
                          {d.cree_le
                            ? format(new Date(d.cree_le), 'dd/MM/yy HH:mm', { locale: fr })
                            : '—'}
                        </td>
                        <td className="py-2 px-3">
                          <BadgeY2K
                            variant={d.action === 'RGPD_SUPPRESSION_COMPTE' ? 'error' : 'info'}
                            size="sm"
                          >
                            {libelle(LIBELLES_ACTION, d.action)}
                          </BadgeY2K>
                        </td>
                        <td className="py-2 px-3 text-xs text-muted-foreground">
                          <span>{libelle(LIBELLES_TYPE_ACTEUR, d.type_acteur)}</span>
                          <p className="text-[10px] text-muted-foreground/60 font-mono truncate max-w-[140px]">
                            {d.acteur_id?.slice(0, 8)}…
                          </p>
                        </td>
                        <td className="py-2 px-3 text-xs text-muted-foreground">
                          <span>{libelle(LIBELLES_TYPE_RESSOURCE, d.type_ressource)}</span>
                          {d.id_ressource && (
                            <p className="text-[10px] text-muted-foreground/60 font-mono truncate max-w-[140px]">
                              {d.id_ressource?.slice(0, 8)}…
                            </p>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Mobile cards */}
              <div className="md:hidden space-y-3 mt-2">
                {demandes.slice(0, 50).map((d) => (
                  <CardY2K key={d.id} hoverLift={false} className="space-y-2">
                    <div className="flex items-start justify-between gap-2">
                      <BadgeY2K
                        variant={d.action === 'RGPD_SUPPRESSION_COMPTE' ? 'error' : 'info'}
                        size="sm"
                        className="shrink-0"
                      >
                        {libelle(LIBELLES_ACTION, d.action)}
                      </BadgeY2K>
                      <span className="text-[10px] text-muted-foreground whitespace-nowrap">
                        {d.cree_le ? format(new Date(d.cree_le), 'dd/MM/yy HH:mm', { locale: fr }) : '—'}
                      </span>
                    </div>
                    <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
                      <div>
                        <p className="text-muted-foreground">Acteur</p>
                        <p className="text-foreground">{libelle(LIBELLES_TYPE_ACTEUR, d.type_acteur)}</p>
                        <p className="text-[10px] text-muted-foreground/60 font-mono">{d.acteur_id?.slice(0, 8)}…</p>
                      </div>
                      <div>
                        <p className="text-muted-foreground">Ressource</p>
                        <p className="text-foreground">{libelle(LIBELLES_TYPE_RESSOURCE, d.type_ressource)}</p>
                        {d.id_ressource && (
                          <p className="text-[10px] text-muted-foreground/60 font-mono">{d.id_ressource?.slice(0, 8)}…</p>
                        )}
                      </div>
                    </div>
                  </CardY2K>
                ))}
              </div>

              {demandes.length > 50 && (
                <p className="text-xs text-muted-foreground text-center mt-3">
                  Affichage des 50 premières. L'export JSON contient les {demandes.length} demandes.
                </p>
              )}
            </>
          )}
        </CardY2K>
      </div>
    </LayoutAdmin>
  );
}
