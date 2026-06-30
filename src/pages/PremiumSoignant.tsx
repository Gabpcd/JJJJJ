import { useState } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { Crown } from 'lucide-react';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

/**
 * Page dépubliée pré-lancement (Lot 1) : plus de liste de fonctionnalités non
 * livrées ni de prix — seule la capture d'intérêt est conservée. La page n'est
 * plus liée depuis les menus ; elle reste accessible en URL directe.
 */
export default function PremiumSoignant() {
  const [email, setEmail] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const inscrire = async () => {
    const trimmed = email.trim();
    if (!trimmed || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) {
      toast.error('Email invalide');
      return;
    }
    setSubmitting(true);
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await (supabase.from('liste_attente_premium' as any) as any).insert({ email: trimmed, type_offre: 'PREMIUM', utilisateur_id: user?.id });
    setSubmitting(false);
    if (error) { toast.error('Erreur lors de l\'inscription. Réessaie.'); return; }
    toast.success('Inscrit(e) à la liste d\'attente !');
    setEmail('');
  };

  return (
    <LayoutApp role="SOIGNANT">
      <div className="max-w-xl mx-auto space-y-6 text-center py-8">
        <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-warning/10 mx-auto">
          <Crown className="h-8 w-8 text-warning" />
        </div>
        <h1 className="text-2xl font-bold text-foreground">Jolene est 100% gratuit pour les soignants</h1>
        <p className="text-muted-foreground text-sm">
          Missions, contrats, paiements, parcours libéral : tout est inclus, sans frais ni commission
          pour toi. Une offre Premium (outils comptables libéral, statistiques avancées) arrivera
          plus tard — laisse ton email pour être prévenu(e) en premier.
        </p>
        <CardY2K hoverLift={false}>
          <CardY2KContent>
            <div className="flex flex-col sm:flex-row gap-2">
              <Input
                type="email"
                placeholder="ton@email.fr"
                value={email}
                onChange={e => setEmail(e.target.value)}
                className="flex-1"
              />
              <BoutonY2K onClick={inscrire} disabled={submitting} loading={submitting}>
                Me prévenir
              </BoutonY2K>
            </div>
          </CardY2KContent>
        </CardY2K>
      </div>
    </LayoutApp>
  );
}
