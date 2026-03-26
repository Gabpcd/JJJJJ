import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { UserRole } from '@/lib/types';
import type { RpcGetMyRole } from '@/lib/supabase-rpc-types';

interface UseRoleResult {
  role: UserRole | 'INCONNU';
  etablissement_id: string | null;
  loading: boolean;
}

export function useRole(): UseRoleResult {
  const [role, setRole] = useState<UserRole | 'INCONNU'>('INCONNU');
  const [etablissementId, setEtablissementId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function fetchRole() {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        if (!cancelled) { setRole('INCONNU'); setLoading(false); }
        return;
      }

      const { data, error } = await supabase.rpc('fn_get_my_role');
      if (!cancelled) {
        if (data && !error) {
          const result = data as unknown as RpcGetMyRole;
          setRole((result.role as UserRole) || 'INCONNU');
          setEtablissementId(result.etablissement_id || null);
        }
        setLoading(false);
      }
    }

    fetchRole();

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      if (session) {
        fetchRole();
      } else {
        setRole('INCONNU');
        setEtablissementId(null);
        setLoading(false);
      }
    });

    return () => {
      cancelled = true;
      subscription.unsubscribe();
    };
  }, []);

  return { role, etablissement_id: etablissementId, loading };
}
