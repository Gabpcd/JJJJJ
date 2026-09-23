import type { QueryClient } from '@tanstack/react-query';

/** Les écrans restent montés : propager les modifications de profil au cache. */
export function invaliderProfilNavigation(client: QueryClient, userId?: string) {
  if (!userId) return;
  for (const prefix of ['navigation-profil', 'explorer-profil', 'explorer-rcp', 'explorer-missions']) {
    void client.invalidateQueries({ queryKey: [prefix, userId] });
  }
}
