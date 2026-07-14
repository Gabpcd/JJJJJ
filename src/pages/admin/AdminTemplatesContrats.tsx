import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, Power, ChevronDown } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { cn } from '@/lib/utils';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface TemplateLigne {
  id: string;
  nom: string;
  type_contrat: string;
  version: number;
  est_actif: boolean;
  variables: any;
  contenu_taille: number;
  cree_le: string;
  modifie_le: string;
}

export default function AdminTemplatesContrats() {
  usePageTitle('Admin · Templates contrats');
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [toggling, setToggling] = useState<string | null>(null);
  const [templates, setTemplates] = useState<TemplateLigne[]>([]);
  const [inactifsOuverts, setInactifsOuverts] = useState(false);

  const charger = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_lister_templates_contrats' as any);
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
      setLoading(false);
      return;
    }
    const result = data as any;
    if (!result?.success) {
      afficherNotification({ type: 'erreur', message: result?.error || 'Erreur.' });
      setLoading(false);
      return;
    }
    setTemplates(result.templates as TemplateLigne[]);
    setLoading(false);
  }, [afficherNotification]);

  useEffect(() => { charger(); }, [charger]);

  async function toggle(t: TemplateLigne) {
    if (!confirm(`${t.est_actif ? 'Désactiver' : 'Activer'} le template "${t.nom}" ?`)) return;
    setToggling(t.id);
    const { data, error } = await supabase.rpc('fn_admin_toggle_template_contrat' as any, { p_template_id: t.id });
    setToggling(null);
    if (error || !(data as any)?.success) {
      afficherNotification({ type: 'erreur', message: error?.message || (data as any)?.error || 'Erreur.' });
      return;
    }
    afficherNotification({ type: 'succes', message: `Template ${(data as any).est_actif ? 'activé' : 'désactivé'}.` });
    charger();
  }

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Templates de contrats" /></LayoutAdmin>;

  const actifs = templates.filter((t) => t.est_actif);
  const inactifs = templates.filter((t) => !t.est_actif);

  const colonnes: ColonneTableau<TemplateLigne>[] = [
    { cle: 'nom', titre: 'Nom' },
    { cle: 'type', titre: 'Type' },
    { cle: 'version', titre: 'Version' },
    { cle: 'statut', titre: 'Statut' },
    { cle: 'taille', titre: 'Taille' },
    { cle: 'modifie', titre: 'Modifié' },
    { cle: 'actions', titre: '', align: 'right', largeur: 'w-48' },
  ];

  const statutBadge = (actif: boolean) =>
    actif ? (
      <BadgeY2K variant="success" size="sm">Actif</BadgeY2K>
    ) : (
      <BadgeY2K variant="info" size="sm">Inactif</BadgeY2K>
    );

  const renduCellule = (t: TemplateLigne, col: ColonneTableau<TemplateLigne>) => {
    switch (col.cle) {
      case 'nom':
        return <span className="font-medium">{t.nom}</span>;
      case 'type':
        return <code className="text-xs">{t.type_contrat}</code>;
      case 'version':
        return <span className="text-xs">v{t.version}</span>;
      case 'statut':
        return statutBadge(t.est_actif);
      case 'taille':
        return <span className="text-xs text-muted-foreground">{(t.contenu_taille / 1024).toFixed(1)} KB</span>;
      case 'modifie':
        return (
          <span className="text-[11px] text-muted-foreground">
            {format(new Date(t.modifie_le), 'dd MMM yy HH:mm', { locale: fr })}
          </span>
        );
      case 'actions':
        return (
          <div className="flex justify-end gap-2" onClick={(e) => e.stopPropagation()}>
            <BoutonY2K
              variant="secondary"
              size="sm"
              onClick={() => navigate(`/admin/templates-contrats/${t.id}`)}
            >
              Éditer
            </BoutonY2K>
            <BoutonY2K
              variant={t.est_actif ? 'ghost' : 'secondary'}
              size="sm"
              onClick={() => toggle(t)}
              disabled={toggling === t.id}
              loading={toggling === t.id}
              iconeGauche={toggling !== t.id ? <Power className="h-3 w-3" /> : undefined}
            >
              {t.est_actif ? 'Désactiver' : 'Activer'}
            </BoutonY2K>
          </div>
        );
      default:
        return null;
    }
  };

  const renduCarte = (t: TemplateLigne) => (
    <div className="space-y-2">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="font-semibold text-foreground truncate">{t.nom}</p>
          <p className="text-xs"><code>{t.type_contrat}</code> · v{t.version} · {(t.contenu_taille / 1024).toFixed(1)} KB</p>
        </div>
        {statutBadge(t.est_actif)}
      </div>
      <p className="text-[11px] text-muted-foreground">
        Modifié le {format(new Date(t.modifie_le), 'dd MMM yy HH:mm', { locale: fr })}
      </p>
      <div className="flex gap-2 pt-2 border-t border-border">
        <BoutonY2K
          variant="secondary"
          size="sm"
          onClick={(e) => { e.stopPropagation(); navigate(`/admin/templates-contrats/${t.id}`); }}
          className="flex-1"
        >
          Éditer
        </BoutonY2K>
        <BoutonY2K
          variant={t.est_actif ? 'ghost' : 'secondary'}
          size="sm"
          onClick={(e) => { e.stopPropagation(); toggle(t); }}
          disabled={toggling === t.id}
          loading={toggling === t.id}
          iconeGauche={toggling !== t.id ? <Power className="h-3 w-3" /> : undefined}
          className="flex-1"
        >
          {t.est_actif ? 'Désactiver' : 'Activer'}
        </BoutonY2K>
      </div>
    </div>
  );

  return (
    <LayoutAdmin>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <FileText className="h-6 w-6 text-primary" /> Templates contrats
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Modèles de CDD, de remplacement libéral et de contrats libéraux spécifiques.
          Les modifications s'appliquent aux nouveaux contrats. Les contrats existants ne sont pas impactés.
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
        <div className="rounded-2xl border-2 border-primary/30 bg-primary/5 p-4">
          <p className="text-xs font-semibold text-foreground">Total</p>
          <p className="text-2xl font-bold text-primary tabular-nums mt-1">{templates.length}</p>
        </div>
        <div className="rounded-2xl border-2 border-success/30 bg-success/5 p-4">
          <p className="text-xs font-semibold text-foreground">Actifs</p>
          <p className="text-2xl font-bold text-success tabular-nums mt-1">{actifs.length}</p>
        </div>
        <div className="rounded-2xl border-2 border-warning/30 bg-warning/5 p-4">
          <p className="text-xs font-semibold text-foreground">Inactifs</p>
          <p className="text-2xl font-bold text-warning tabular-nums mt-1">{inactifs.length}</p>
        </div>
      </div>

      {templates.length === 0 ? (
        <EmptyState titre="Aucun modèle enregistré" description="Aucun modèle de contrat n’est actuellement disponible." />
      ) : (
        <div className="space-y-6">
          {/* ── Templates actifs : toujours visibles, en tête ── */}
          <section aria-label="Templates actifs">
            <h2 className="flex items-center gap-2 text-sm font-bold text-foreground mb-3">
              <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-success/15 text-success text-[11px] font-bold">
                {actifs.length}
              </span>
              Templates actifs
            </h2>
            {actifs.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                Aucun template actif. Activez un template depuis la section « Inactifs » ci-dessous pour le rendre disponible.
              </p>
            ) : (
              <TableOuCartes
                colonnes={colonnes}
                donnees={actifs}
                getId={(t) => t.id}
                renduCellule={renduCellule}
                renduCarte={renduCarte}
              />
            )}
          </section>

          {/* ── Templates inactifs : section repliée par défaut ── */}
          {inactifs.length > 0 && (
            <section aria-label="Templates inactifs">
              <button
                type="button"
                onClick={() => setInactifsOuverts((o) => !o)}
                aria-expanded={inactifsOuverts}
                className="flex items-center gap-2 text-sm font-semibold text-muted-foreground hover:text-foreground transition-colors mb-3"
              >
                <Power className="h-4 w-4" />
                Inactifs
                <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-muted text-muted-foreground text-[11px] font-semibold">
                  {inactifs.length}
                </span>
                <ChevronDown className={cn('h-4 w-4 transition-transform', inactifsOuverts && 'rotate-180')} />
              </button>
              {inactifsOuverts && (
                <TableOuCartes
                  colonnes={colonnes}
                  donnees={inactifs}
                  getId={(t) => t.id}
                  renduCellule={renduCellule}
                  renduCarte={renduCarte}
                />
              )}
            </section>
          )}
        </div>
      )}

      <div className="rounded-xl bg-muted/30 border border-border p-4 text-xs text-muted-foreground mt-6">
        <p className="font-semibold text-foreground mb-1">Mises en garde</p>
        <ul className="list-disc list-inside space-y-1">
          <li>Une modification de template incrémente automatiquement la version.</li>
          <li>Les contrats déjà signés conservent leur template d'origine (immutable).</li>
          <li>Désactiver un template empêche sa sélection pour les nouvelles missions, sans impacter les contrats en cours.</li>
          <li>Variables jinja-like supportées : <code>{`{{soignant_nom}}`}</code>, <code>{`{{rpps}}`}</code>, <code>{`{{date_debut}}`}</code>, <code>{`{{taux_horaire}}`}</code>, <code>{`{{etablissement_nom}}`}</code>, etc.</li>
        </ul>
      </div>
    </LayoutAdmin>
  );
}
