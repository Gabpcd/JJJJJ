import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Bell, Mail, MessageSquare, Smartphone, Loader2, ArrowLeft, Save } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';

type Canal = 'EMAIL' | 'SMS' | 'PUSH' | 'IN_APP';

interface PrefsGlobal {
  canal_email: boolean;
  canal_sms: boolean;
  canal_push: boolean;
  canal_in_app: boolean;
}

interface PrefEvenement {
  type_evenement: string;
  canal: Canal;
  actif: boolean;
}

interface EventDef {
  type: string;
  label: string;
  description: string;
  canaux: Canal[];
}

const EVENTS_SOIGNANT: EventDef[] = [
  { type: 'NOUVELLE_MISSION_MATCHANT_FILTRE', label: 'Nouvelles missions matchant mes filtres', description: 'Alertes sur les missions correspondant à mes recherches sauvegardées', canaux: ['EMAIL','PUSH'] },
  { type: 'CANDIDATURE_ACCEPTEE', label: 'Ma candidature est acceptée', description: 'Confirmation d\'assignation à une mission', canaux: ['EMAIL','PUSH','SMS'] },
  { type: 'MISSION_ASSIGNEE', label: 'Proposition de mission directe', description: 'Quand un établissement me propose directement une mission', canaux: ['EMAIL','PUSH'] },
  { type: 'RAPPEL_J1_MISSION', label: 'Rappel mission J-1', description: 'Rappel la veille du début de mission', canaux: ['EMAIL','PUSH','SMS'] },
  { type: 'POINTAGE_MANQUANT', label: 'Pointage manquant', description: 'Si j\'ai oublié de pointer mon départ', canaux: ['EMAIL','PUSH'] },
  { type: 'FACTURE_EMISE', label: 'Facture émise', description: 'Quand Jolene émet une nouvelle facture en mon nom', canaux: ['EMAIL','PUSH'] },
  { type: 'PAIEMENT_RECU', label: 'Paiement reçu', description: 'Quand un établissement règle ma facture', canaux: ['EMAIL','PUSH'] },
  { type: 'CONTRAT_TRAVAIL_DEPOSE', label: 'Contrat de travail SALARIE déposé', description: 'Quand mon établissement upload mon contrat CDDU', canaux: ['EMAIL','PUSH'] },
  { type: 'LITIGE_OUVERT', label: 'Litige ouvert', description: 'Notifications sur les litiges en cours', canaux: ['EMAIL','PUSH','SMS'] },
  { type: 'LITIGE_RESOLU', label: 'Litige résolu', description: 'Quand un litige a été clos', canaux: ['EMAIL','PUSH'] },
  { type: 'DOCUMENT_EXPIRANT', label: 'Document expirant bientôt', description: 'RCP, diplôme ou autre document arrivant à expiration', canaux: ['EMAIL','PUSH'] },
  { type: 'MANDAT_RE_SIGNATURE', label: 'Re-signature du mandat de facturation', description: 'Si une nouvelle version du mandat est publiée', canaux: ['EMAIL','PUSH'] },
  { type: 'SERIE_ONBOARDING', label: 'Série emails de bienvenue (J0-J7)', description: 'Séquence d\'emails d\'accueil pendant la première semaine', canaux: ['EMAIL'] },
];

const EVENTS_ETAB: EventDef[] = [
  { type: 'CANDIDATURE_RECUE', label: 'Nouvelle candidature reçue', description: 'Quand un soignant postule à une de mes missions', canaux: ['EMAIL','PUSH'] },
  { type: 'POINTAGE_MANQUANT', label: 'Pointage soignant manquant', description: 'Alerte si un soignant assigné n\'a pas pointé', canaux: ['EMAIL','PUSH'] },
  { type: 'CONTRAT_TRAVAIL_DEPOSE', label: 'Rappel contrat de travail SALARIE', description: 'Rappel J-1 si le contrat n\'a pas été uploadé', canaux: ['EMAIL'] },
  { type: 'FACTURE_EMISE', label: 'Facture de commission Jolene émise', description: 'Quand Jolene émet une facture de commission', canaux: ['EMAIL'] },
  { type: 'LITIGE_OUVERT', label: 'Litige ouvert par un soignant', description: 'Notifications sur les litiges en cours', canaux: ['EMAIL','PUSH','SMS'] },
  { type: 'LITIGE_RESOLU', label: 'Litige résolu', description: 'Quand un litige a été clos', canaux: ['EMAIL'] },
  { type: 'NOUVELLE_MISSION_MATCHANT_FILTRE', label: 'Nouveaux soignants disponibles', description: 'Alertes sur les soignants matchant mes recherches sauvegardées', canaux: ['EMAIL'] },
  { type: 'SERIE_ONBOARDING', label: 'Série emails de bienvenue (J0-J7)', description: 'Séquence d\'emails d\'accueil pendant la première semaine', canaux: ['EMAIL'] },
];

export default function PageParametresNotifications() {
  usePageTitle('Préférences de notifications');
  const navigate = useNavigate();
  const { user, role } = useAuth();
  const isEtab = role === 'ADMIN_ETABLISSEMENT';
  const events = isEtab ? EVENTS_ETAB : EVENTS_SOIGNANT;

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [global, setGlobal] = useState<PrefsGlobal>({
    canal_email: true, canal_sms: false, canal_push: true, canal_in_app: true,
  });
  const [parEvenement, setParEvenement] = useState<Map<string, boolean>>(new Map());

  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data, error } = await supabase.rpc('fn_obtenir_mes_preferences_notifications' as any);
      if (error) {
        toast.error('Impossible de charger vos préférences. Vos modifications ne seront pas sauvegardées tant que la page ne charge pas correctement.');
        setLoading(false);
        return;
      }
      if (data && (data as any).global) {
        setGlobal((data as any).global);
        const m = new Map<string, boolean>();
        for (const p of ((data as any).par_evenement || []) as PrefEvenement[]) {
          m.set(`${p.type_evenement}:${p.canal}`, p.actif);
        }
        setParEvenement(m);
      }
      setLoading(false);
    })();
  }, [user]);

  const isEnabled = (event: string, canal: Canal) => {
    const key = `${event}:${canal}`;
    return parEvenement.has(key) ? !!parEvenement.get(key) : true;
  };

  const toggle = (event: string, canal: Canal) => {
    const key = `${event}:${canal}`;
    const current = isEnabled(event, canal);
    const m = new Map(parEvenement);
    m.set(key, !current);
    setParEvenement(m);
  };

  const enregistrer = async () => {
    setSaving(true);
    try {
      const par_evenement: any[] = [];
      for (const [key, actif] of parEvenement) {
        const [type_evenement, canal] = key.split(':');
        par_evenement.push({ type_evenement, canal, actif });
      }
      const { data, error } = await supabase.rpc('fn_modifier_preferences_notifications' as any, {
        p_canal_email: global.canal_email,
        p_canal_sms: global.canal_sms,
        p_canal_push: global.canal_push,
        p_canal_in_app: global.canal_in_app,
        p_par_evenement: par_evenement,
      });
      if (error) throw error;
      if ((data as any)?.error) throw new Error((data as any).error);
      toast.success('Préférences enregistrées');
    } catch (err: any) {
      toast.error(err?.message || 'Erreur enregistrement');
    } finally {
      setSaving(false);
    }
  };

  const role_safe = (isEtab ? 'ADMIN_ETABLISSEMENT' : 'SOIGNANT') as any;

  if (loading) {
    return (
      <LayoutApp role={role_safe}>
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      </LayoutApp>
    );
  }

  return (
    <LayoutApp role={role_safe}>
      <div className="max-w-4xl mx-auto space-y-6">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={() => navigate(-1)}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
              <Bell className="h-5 w-5 text-primary" /> Préférences de notifications
            </h1>
            <p className="text-xs text-muted-foreground">Choisissez par canal et par type d'événement</p>
          </div>
        </div>

        {/* Canaux globaux */}
        <section className="card-base space-y-3">
          <h2 className="text-base font-semibold text-foreground">Canaux globaux</h2>
          <p className="text-xs text-muted-foreground">
            Désactiver un canal ici coupe TOUTES les notifications de ce canal, peu importe les préférences par événement.
          </p>
          <div className="grid sm:grid-cols-2 gap-3">
            <ToggleCanal icone={<Mail className="h-4 w-4" />} label="Email" actif={global.canal_email} onChange={v => setGlobal(g => ({ ...g, canal_email: v }))} />
            <ToggleCanal icone={<Smartphone className="h-4 w-4" />} label="Notifications push (mobile / web)" actif={global.canal_push} onChange={v => setGlobal(g => ({ ...g, canal_push: v }))} />
            <ToggleCanal icone={<MessageSquare className="h-4 w-4" />} label="SMS (urgences uniquement par défaut)" actif={global.canal_sms} onChange={v => setGlobal(g => ({ ...g, canal_sms: v }))} />
            <ToggleCanal icone={<Bell className="h-4 w-4" />} label="In-app (cloche en haut de l'écran)" actif={global.canal_in_app} onChange={v => setGlobal(g => ({ ...g, canal_in_app: v }))} />
          </div>
        </section>

        {/* Préférences par événement */}
        <section className="card-base space-y-3">
          <h2 className="text-base font-semibold text-foreground">Par type d'événement</h2>
          <p className="text-xs text-muted-foreground">
            Pour chaque type d'événement, choisissez les canaux activés. Les notifications d'urgence (sécurité, danger) sont toujours envoyées et non désactivables.
          </p>
          <div className="overflow-x-auto -mx-4 px-4">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left py-2 pr-3 font-semibold text-foreground">Événement</th>
                  <th className="text-center py-2 px-2 font-semibold text-foreground w-20">Email</th>
                  <th className="text-center py-2 px-2 font-semibold text-foreground w-20">Push</th>
                  <th className="text-center py-2 px-2 font-semibold text-foreground w-20">SMS</th>
                </tr>
              </thead>
              <tbody>
                {events.map(e => (
                  <tr key={e.type} className="border-b border-border last:border-0">
                    <td className="py-3 pr-3">
                      <p className="font-medium text-foreground">{e.label}</p>
                      <p className="text-xs text-muted-foreground">{e.description}</p>
                    </td>
                    {(['EMAIL','PUSH','SMS'] as Canal[]).map(c => (
                      <td key={c} className="text-center px-2">
                        {e.canaux.includes(c) ? (
                          <button
                            type="button"
                            role="switch"
                            aria-checked={isEnabled(e.type, c)}
                            onClick={() => toggle(e.type, c)}
                            className={`relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors ${isEnabled(e.type, c) ? 'bg-primary' : 'bg-muted-foreground/30'}`}
                            aria-label={`${c} pour ${e.label} : ${isEnabled(e.type, c) ? 'activé' : 'désactivé'}`}
                          >
                            <span className={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${isEnabled(e.type, c) ? 'translate-x-4' : 'translate-x-0'}`} />
                          </button>
                        ) : (
                          <span className="text-xs text-muted-foreground/50">—</span>
                        )}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <div className="rounded-xl border border-warning/30 bg-warning/5 p-3 text-xs text-muted-foreground">
          <p className="font-semibold text-foreground mb-1">⚠️ Notifications d'urgence</p>
          Les notifications d'urgence critique (incident sécurité, litige sécurité, alerte fraude) sont toujours envoyées sur tous les canaux configurés et ne peuvent pas être désactivées. C'est une exigence de sécurité.
        </div>

        <div className="flex justify-end sticky bottom-4">
          <Button onClick={enregistrer} disabled={saving} className="gap-2 shadow-lg">
            {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
            Enregistrer
          </Button>
        </div>
      </div>
    </LayoutApp>
  );
}

function ToggleCanal({ icone, label, actif, onChange }: { icone: JSX.Element; label: string; actif: boolean; onChange: (v: boolean) => void }) {
  return (
    <div className="flex items-center justify-between gap-3 rounded-lg border border-border p-3">
      <div className="flex items-center gap-2">
        <span className="text-primary">{icone}</span>
        <span className="text-sm text-foreground">{label}</span>
      </div>
      <button
        onClick={() => onChange(!actif)}
        className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors ${actif ? 'bg-primary' : 'bg-muted-foreground/30'}`}
      >
        <span className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform ${actif ? 'translate-x-5' : 'translate-x-0'}`} />
      </button>
    </div>
  );
}
