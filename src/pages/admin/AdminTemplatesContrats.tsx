import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, Power, Loader2 } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
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

  async function charger() {
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
  }

  useEffect(() => { charger(); }, []);

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

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  const actifs = templates.filter((t) => t.est_actif);
  const inactifs = templates.filter((t) => !t.est_actif);

  return (
    <LayoutAdmin>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <FileText className="h-6 w-6 text-primary" /> Templates contrats
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          14 templates Sprint 2 : CDD master (18 professions) + REMPLACEMENT_LIBERAL + 12 LIBERAL spécifiques.
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

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border text-xs uppercase text-muted-foreground">
              <th className="text-left py-2 px-2">Nom</th>
              <th className="text-left py-2 px-2">Type</th>
              <th className="text-left py-2 px-2">Version</th>
              <th className="text-left py-2 px-2">Statut</th>
              <th className="text-left py-2 px-2">Taille</th>
              <th className="text-left py-2 px-2">Modifié</th>
              <th className="text-right py-2 px-2">Actions</th>
            </tr>
          </thead>
          <tbody>
            {templates.map((t) => (
              <tr key={t.id} className="border-b border-border hover:bg-muted/30">
                <td className="py-2 px-2 font-medium">{t.nom}</td>
                <td className="py-2 px-2 text-xs"><code className="text-xs">{t.type_contrat}</code></td>
                <td className="py-2 px-2 text-xs">v{t.version}</td>
                <td className="py-2 px-2">
                  {t.est_actif ? (
                    <span className="text-[11px] px-2 py-0.5 rounded-full bg-success/20 text-success font-medium">ACTIF</span>
                  ) : (
                    <span className="text-[11px] px-2 py-0.5 rounded-full bg-muted text-muted-foreground font-medium">INACTIF</span>
                  )}
                </td>
                <td className="py-2 px-2 text-xs text-muted-foreground">{(t.contenu_taille / 1024).toFixed(1)} KB</td>
                <td className="py-2 px-2 text-[11px] text-muted-foreground">
                  {format(new Date(t.modifie_le), 'dd MMM yy HH:mm', { locale: fr })}
                </td>
                <td className="py-2 px-2 text-right flex justify-end gap-2">
                  <button
                    onClick={() => navigate(`/admin/templates-contrats/${t.id}`)}
                    className="btn-secondary text-xs py-1 px-3"
                  >
                    Éditer
                  </button>
                  <button
                    onClick={() => toggle(t)}
                    disabled={toggling === t.id}
                    className={`text-xs py-1 px-3 rounded-lg font-medium border-2 ${
                      t.est_actif
                        ? 'border-warning text-warning hover:bg-warning/5'
                        : 'border-success text-success hover:bg-success/5'
                    } disabled:opacity-50`}
                  >
                    {toggling === t.id ? <Loader2 className="h-3 w-3 animate-spin inline" /> : (
                      <>
                        <Power className="h-3 w-3 inline mr-1" />
                        {t.est_actif ? 'Désactiver' : 'Activer'}
                      </>
                    )}
                  </button>
                </td>
              </tr>
            ))}
            {templates.length === 0 && (
              <tr>
                <td colSpan={7} className="py-8 text-center text-sm text-muted-foreground italic">
                  Aucun template enregistré.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="rounded-xl bg-muted/30 border border-border p-4 text-xs text-muted-foreground mt-6">
        <p className="font-semibold text-foreground mb-1">⚠️ Mises en garde</p>
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
