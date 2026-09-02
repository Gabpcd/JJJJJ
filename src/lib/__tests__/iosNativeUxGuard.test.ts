import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const lire = (chemin: string) => readFileSync(resolve(process.cwd(), chemin), 'utf8');

describe('garde-fous de l’expérience iOS native', () => {
  it('ne déclenche la permission push système qu’après une action explicite', () => {
    const push = lire('src/lib/pushNative.ts');
    const demande = lire('src/components/DemandePermissionPush.tsx');
    const parametres = lire('src/pages/PageParametresNotifications.tsx');

    expect(push).toContain('demanderPermissionNativePush');
    expect(push).toContain('autoriserDemande');
    expect(demande).toContain('Activer les notifications');
    expect(demande).toContain('demanderPermissionNativePush');
    expect(parametres).toContain('Activer sur cet appareil');
    expect(parametres).toContain('demanderPermissionNativePush');
    expect(parametres).toContain('native-push-permission-status');
  });

  it('utilise la modale responsive avec zones fixes et contenu scrollable', () => {
    const contact = lire('src/components/ModalContacterJolene.tsx');

    expect(contact).toContain('DialogResponsiveContent');
    expect(contact).toContain('DialogResponsiveBody');
    expect(contact).toContain('DialogResponsiveFooter');
    expect(contact).not.toContain('fixed inset-0 z-[9999]');
  });

  it('neutralise les déplacements de survol sur les écrans tactiles', () => {
    const styles = lire('src/index.css');

    expect(styles).toContain('@media (hover: none) and (pointer: coarse)');
    expect(styles).toContain('.transition-bouncy:hover:not(:active)');
    expect(styles).toContain('transform: none !important');
  });

  it('conserve un seul contrôle retour sur mobile dans les deux interfaces', () => {
    const profilEtablissement = lire('src/pages/ProfilSoignantEtablissement.tsx');
    const missionSoignant = lire('src/pages/DetailMissionSoignant.tsx');

    expect(profilEtablissement).toContain('app-inline-back');
    expect(missionSoignant).toContain('app-inline-back');
    expect(lire('src/index.css')).toContain('.app-inline-back');
  });

  it('garde le contenu principal et le CTA Revenus dans le premier viewport', () => {
    const layout = lire('src/components/LayoutApp.tsx');
    const revenus = lire('src/pages/MesGains.tsx');

    expect(layout).toContain('px-4 py-4 md:py-6');
    expect(revenus).toMatch(/titre="Pas encore de gains"[\s\S]{0,300}compact/);
  });
});
