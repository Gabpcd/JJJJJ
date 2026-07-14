import { useState, useEffect } from 'react';
import { Mail, Loader2, CheckCircle, AlertTriangle, RefreshCw } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { EmptyState } from '@/components/ui/EmptyState';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

interface MessageContact {
  id: string;
  expediteur_role: string | null;
  expediteur_nom: string | null;
  expediteur_email: string | null;
  sujet: string;
  corps: string;
  source: string;
  statut: string;
  cree_le: string;
}

const STATUT_BADGE: Record<string, { label: string; variant: 'warning' | 'info' | 'success' }> = {
  NOUVEAU: { label: 'Nouveau', variant: 'warning' },
  EN_COURS: { label: 'En cours', variant: 'info' },
  TRAITE: { label: 'Traité', variant: 'success' },
};

const LIBELLES_ROLE: Record<string, string> = {
  SOIGNANT: 'Soignant',
  ADMIN_ETABLISSEMENT: 'Établissement',
  ADMIN_GROUPE: 'Groupe de santé',
  ADMIN_PLATEFORME: 'Administration Jolene',
};

export default function AdminMessagesContact() {
  usePageTitle('Messages de contact — Admin');
  const [messages, setMessages] = useState<MessageContact[]>([]);
  const [loading, setLoading] = useState(true);
  const [maj, setMaj] = useState<string | null>(null);
  const [erreurChargement, setErreurChargement] = useState(false);

  const charger = async () => {
    setLoading(true);
    setErreurChargement(false);
    const { data, error } = await supabase
      .from('messages_contact' as any)
      .select('id, expediteur_role, expediteur_nom, expediteur_email, sujet, corps, source, statut, cree_le')
      .order('cree_le', { ascending: false })
      .limit(200);
    if (error) {
      toast.error('Impossible de charger les messages de contact.');
      setErreurChargement(true);
    } else {
      setMessages((data as any) || []);
    }
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const marquerTraite = async (id: string) => {
    setMaj(id);
    const { data, error } = await supabase.rpc(
      'fn_admin_traiter_message_contact' as any,
      { p_message_id: id },
    );
    if (error || (data as any)?.error) toast.error((data as any)?.error || 'Erreur mise à jour');
    else { toast.success('Marqué comme traité'); await charger(); }
    setMaj(null);
  };

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Messages de contact" />
      <div className="flex items-center gap-3 mb-6">
        <div className="p-2.5 rounded-xl bg-primary/10"><Mail className="h-6 w-6 text-primary" /></div>
        <div>
          <h1 className="text-xl font-bold text-foreground">Messages de contact</h1>
          <p className="text-sm text-muted-foreground">Messages « Contacter Jolene » envoyés par les utilisateurs.</p>
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center gap-2 py-16 text-sm text-muted-foreground" role="status"><Loader2 className="h-7 w-7 animate-spin text-primary" aria-hidden="true" /> Chargement des messages…</div>
      ) : erreurChargement ? (
        <div className="card-base flex flex-col items-center gap-3 py-10 text-center" role="alert">
          <AlertTriangle className="h-7 w-7 text-destructive" aria-hidden="true" />
          <div>
            <p className="font-semibold text-foreground">Messages indisponibles</p>
            <p className="text-sm text-muted-foreground">Le chargement a échoué. Aucune donnée n’a été modifiée.</p>
          </div>
          <BoutonY2K variant="secondary" size="sm" onClick={charger} iconeGauche={<RefreshCw className="h-4 w-4" />}>Réessayer</BoutonY2K>
        </div>
      ) : messages.length === 0 ? (
        <EmptyState icone={<Mail />} mascotte="happy" titre="Aucun message" description="Les messages envoyés via « Contacter Jolene » apparaîtront ici." variant="info" />
      ) : (
        <div className="space-y-3">
          {messages.map((m) => {
            const badge = STATUT_BADGE[m.statut] || STATUT_BADGE.NOUVEAU;
            return (
              <div key={m.id} className={`card-base ${m.statut === 'NOUVEAU' ? 'border-warning/40' : 'border-border'}`}>
                <div className="flex items-start justify-between gap-3 flex-wrap">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap mb-1">
                      <BadgeY2K variant={badge.variant} size="sm">{badge.label}</BadgeY2K>
                      {m.expediteur_role && <span className="text-[10px] badge-base bg-muted text-muted-foreground">{LIBELLES_ROLE[m.expediteur_role] ?? m.expediteur_role}</span>}
                      <span className="text-xs text-muted-foreground">{new Date(m.cree_le).toLocaleString('fr-FR')}</span>
                    </div>
                    <p className="font-semibold text-sm text-foreground">{m.sujet}</p>
                    <p className="text-sm text-muted-foreground mt-1 whitespace-pre-wrap">{m.corps}</p>
                    <p className="text-xs text-muted-foreground mt-2">
                      {m.expediteur_nom || 'Utilisateur'}
                      {m.expediteur_email && <> · <a href={`mailto:${m.expediteur_email}`} className="text-primary hover:underline">{m.expediteur_email}</a></>}
                    </p>
                  </div>
                  {m.statut !== 'TRAITE' && (
                    <button
                      type="button"
                      onClick={() => marquerTraite(m.id)}
                      disabled={maj === m.id}
                      className="btn-secondary text-xs px-3 py-1.5 inline-flex items-center gap-1.5 shrink-0"
                    >
                      {maj === m.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <CheckCircle className="h-3.5 w-3.5" />}
                      Marquer traité
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </LayoutAdmin>
  );
}
