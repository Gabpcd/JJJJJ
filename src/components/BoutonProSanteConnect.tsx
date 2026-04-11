import { useState } from 'react';
import { Loader2, ShieldCheck } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';

interface Props {
  intention?: 'login' | 'signup';
  fullWidth?: boolean;
}

export function BoutonProSanteConnect({ intention = 'login', fullWidth = true }: Props) {
  const [loading, setLoading] = useState(false);

  const lancer = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke('psc-authorize', {
        body: { intention },
      });

      if (error || data?.configured === false) {
        toast.info('Pro Santé Connect sera disponible très prochainement. Utilisez l\'inscription classique en attendant.');
        return;
      }

      if (data?.error) {
        toast.error(data.error);
        return;
      }

      if (data?.authorization_url) {
        window.location.href = data.authorization_url;
      } else {
        toast.error('Impossible de contacter Pro Santé Connect');
      }
    } catch {
      toast.info('Pro Santé Connect sera disponible très prochainement.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Button
      type="button"
      variant="outline"
      onClick={lancer}
      disabled={loading}
      className={`${fullWidth ? 'w-full' : ''} gap-2 border-2 border-primary/30 hover:border-primary hover:bg-primary/5`}
    >
      {loading ? (
        <Loader2 className="h-4 w-4 animate-spin" />
      ) : (
        <ShieldCheck className="h-4 w-4 text-primary" />
      )}
      {intention === 'signup' ? "S'inscrire avec Pro Santé Connect" : 'Se connecter avec Pro Santé Connect'}
    </Button>
  );
}
