import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Save, Eye, Loader2, AlertCircle } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { CardY2K } from '@/components/y2k/CardY2K';
import { sanitizeHTML } from '@/lib/sanitize';

interface Template {
  id: string;
  nom: string;
  type_contrat: string;
  version: number;
  est_actif: boolean;
  variables: any;
  contenu_html: string;
  cree_le: string;
  modifie_le: string;
}

/** Libellés français des types de contrat de template (la valeur brute reste celle envoyée aux RPCs). */
const LIBELLES_TYPE_CONTRAT: Record<string, string> = {
  REMPLACEMENT_LIBERAL: 'Remplacement libéral',
  LIBERAL: 'Libéral',
  CDD: 'CDD',
  CDDU: "CDD d'usage",
  CDDU_USAGE: "CDD d'usage",
  VACATION: 'CDD court',
  SALARIE: 'Salarié',
  LIBERAL_MEDECIN_CLINIQUE: 'Libéral — médecin en clinique',
  LIBERAL_MEDECIN_EHPAD: 'Libéral — médecin en EHPAD',
  LIBERAL_MEDECIN_CABINET: 'Libéral — médecin en cabinet',
  LIBERAL_SAGE_FEMME_CLINIQUE: 'Libéral — sage-femme en clinique',
  LIBERAL_KINE_CLINIQUE: 'Libéral — kinésithérapeute en clinique',
  LIBERAL_ORTHOPHONISTE_CABINET: 'Libéral — orthophoniste en cabinet',
  LIBERAL_ERGOTHERAPEUTE_CABINET: 'Libéral — ergothérapeute en cabinet',
  LIBERAL_PSYCHOMOTRICIEN_CABINET: 'Libéral — psychomotricien en cabinet',
};

function libelleTypeContrat(type: string): string {
  return LIBELLES_TYPE_CONTRAT[type] || type.replace(/_/g, ' ').toLowerCase();
}

const VARIABLES_DISPONIBLES = [
  '{{soignant_nom}}',
  '{{soignant_prenom}}',
  '{{rpps}}',
  '{{soignant_adresse}}',
  '{{date_debut}}',
  '{{date_fin}}',
  '{{heure_debut}}',
  '{{heure_fin}}',
  '{{duree_heures}}',
  '{{taux_horaire}}',
  '{{etablissement_nom}}',
  '{{etablissement_siret}}',
  '{{etablissement_adresse}}',
  '{{profession}}',
  '{{service}}',
  '{{convention_collective}}',
];

export default function AdminEditerTemplateContrat() {
  usePageTitle('Admin · Éditer template');
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [template, setTemplate] = useState<Template | null>(null);
  const [nom, setNom] = useState('');
  const [contenuHtml, setContenuHtml] = useState('');
  const [showPreview, setShowPreview] = useState(false);

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    async function load() {
      const { data, error } = await supabase.rpc('fn_admin_detail_template_contrat' as any, { p_template_id: id });
      if (cancelled) return;
      if (error || !(data as any)?.success) {
        afficherNotification({ type: 'erreur', message: error?.message || (data as any)?.error || 'Erreur.' });
        setLoading(false);
        return;
      }
      const tpl = (data as any).template as Template;
      setTemplate(tpl);
      setNom(tpl.nom);
      setContenuHtml(tpl.contenu_html);
      setLoading(false);
    }
    load();
    return () => { cancelled = true; };
  }, [id, afficherNotification]);

  async function sauvegarder() {
    if (!template) return;
    if (contenuHtml.length < 50) {
      afficherNotification({ type: 'erreur', message: 'Le contenu HTML doit faire au moins 50 caractères.' });
      return;
    }
    if (!confirm(`Confirmer la modification du template "${nom}" ?\nVersion ${template.version} → ${template.version + 1}.\nLes contrats existants ne sont pas impactés.`)) return;

    setSaving(true);
    const { data, error } = await supabase.rpc('fn_admin_modifier_template_contrat' as any, {
      p_template_id: template.id,
      p_contenu_html: contenuHtml,
      p_nom: nom,
    });
    setSaving(false);
    if (error || !(data as any)?.success) {
      afficherNotification({ type: 'erreur', message: error?.message || (data as any)?.error || 'Erreur.' });
      return;
    }
    afficherNotification({ type: 'succes', message: `Template enregistré (version ${(data as any).version}).` });
    navigate('/admin/templates-contrats');
  }

  function insererVariable(v: string) {
    setContenuHtml((prev) => prev + ' ' + v);
  }

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Éditer le template" /></LayoutAdmin>;
  if (!template) return <LayoutAdmin><div className="space-y-2"><h1 className="text-2xl font-bold text-foreground">Template introuvable</h1><p className="text-sm text-muted-foreground">Ce template n’existe pas ou n’est plus accessible.</p></div></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <button onClick={() => navigate('/admin/templates-contrats')} className="flex items-center gap-1 text-sm text-primary hover:underline mb-2">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

      <div className="mb-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-foreground">Éditer le template</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Type <strong>{libelleTypeContrat(template.type_contrat)}</strong> · Version actuelle <strong>v{template.version}</strong>
          </p>
        </div>
        <BoutonY2K
          variant="primary"
          size="md"
          onClick={sauvegarder}
          disabled={saving || contenuHtml === template.contenu_html}
          loading={saving}
          iconeGauche={!saving ? <Save className="h-4 w-4" /> : undefined}
        >
          Enregistrer (v{template.version + 1})
        </BoutonY2K>
      </div>

      <div className="rounded-lg bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 p-3 text-xs text-amber-800 dark:text-amber-300 flex gap-2 mb-4">
        <AlertCircle className="h-4 w-4 shrink-0" />
        <p>
          Cette modification s'appliquera aux <strong>nouveaux contrats uniquement</strong>. Les contrats déjà signés conservent leur version d'origine (immutable).
          Audit complet via journaux_audit (admin + ancienne/nouvelle version).
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-[1fr,280px] gap-4">
        <div className="space-y-4">
          <label className="block">
            <span className="text-xs font-medium text-foreground mb-1 block">Nom</span>
            <input aria-label="Nom du template de contrat" value={nom} onChange={(e) => setNom(e.target.value)} className="input-base" disabled={saving} />
          </label>

          <div>
            <div className="flex items-center justify-between mb-1">
              <span className="text-xs font-medium text-foreground">Contenu HTML</span>
              <button
                onClick={() => setShowPreview(!showPreview)}
                className="text-xs text-primary hover:underline inline-flex items-center gap-1"
              >
                <Eye className="h-3 w-3" /> {showPreview ? 'Éditer' : 'Aperçu'}
              </button>
            </div>
            {showPreview ? (
              <div
                className="rounded-lg border border-border bg-card p-4 prose prose-sm max-w-none min-h-[400px] max-h-[600px] overflow-y-auto"
                dangerouslySetInnerHTML={{ __html: sanitizeHTML(contenuHtml) }}
              />
            ) : (
              <textarea
                aria-label="Contenu HTML du template de contrat"
                value={contenuHtml}
                onChange={(e) => setContenuHtml(e.target.value)}
                className="input-base font-mono text-xs min-h-[400px]"
                rows={20}
                disabled={saving}
              />
            )}
            <p className="text-[11px] text-muted-foreground mt-1">
              {contenuHtml.length} caractères ({(contenuHtml.length / 1024).toFixed(1)} KB)
            </p>
          </div>
        </div>

        <aside className="space-y-3">
          <CardY2K hoverLift={false}>
            <h3 className="text-sm font-bold text-foreground mb-2">Variables disponibles</h3>
            <p className="text-[11px] text-muted-foreground mb-2">Cliquez pour insérer à la fin du contenu.</p>
            <ul className="space-y-1">
              {VARIABLES_DISPONIBLES.map((v) => (
                <li key={v}>
                  <button
                    onClick={() => insererVariable(v)}
                    className="text-xs font-mono text-primary hover:underline block text-left w-full truncate"
                    disabled={saving}
                  >
                    {v}
                  </button>
                </li>
              ))}
            </ul>
          </CardY2K>

          {template.variables && Object.keys(template.variables).length > 0 && (
            <CardY2K hoverLift={false}>
              <h3 className="text-sm font-bold text-foreground mb-2">Variables originales</h3>
              <pre className="text-[10px] font-mono text-muted-foreground overflow-x-auto">
                {JSON.stringify(template.variables, null, 2)}
              </pre>
            </CardY2K>
          )}
        </aside>
      </div>
    </LayoutAdmin>
  );
}
