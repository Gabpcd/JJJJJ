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

  it('ouvre les deux parcours document iOS sans menu caméra ambigu', () => {
    const infoPlist = lire('ios/App/App/Info.plist');
    const platform = lire('src/lib/platform.ts');

    expect(infoPlist).toContain('<key>NSCameraUsageDescription</key>');
    expect(infoPlist).toContain('<key>NSPhotoLibraryUsageDescription</key>');
    expect(infoPlist).toContain('<key>NSPhotoLibraryAddUsageDescription</key>');
    expect(platform).toContain('source: CameraSource.Camera');
    expect(platform).not.toContain('source: CameraSource.Prompt');
  });

  it('conserve la modale documentaire au retour de la photothèque native', () => {
    const authContext = lire('src/contexts/AuthContext.tsx');
    const documents = lire('src/pages/DocumentsSoignant.tsx');

    expect(authContext).toContain('conserverUtilisateurStable');
    expect(authContext).toContain('setUser((precedent) => conserverUtilisateurStable');
    expect(documents).toContain('const userId = user?.id');
    expect(documents).toContain('}, [userId]);');
  });

  it('retire immédiatement un verdict FINESS devenu obsolète', () => {
    const inscription = lire('src/pages/InscriptionEtablissement.tsx');

    expect(inscription).toMatch(/setFinessCheck\(null\);[\s\S]{0,160}maj\('finess'/);
  });

  it('laisse les commandes critiques de l’admin accessibles sur mobile', () => {
    const layoutAdmin = lire('src/components/LayoutAdmin.tsx');

    expect(layoutAdmin).toContain('aria-label="Se déconnecter"');
    expect(layoutAdmin).toContain("'translate-y-0'");
    expect(layoutAdmin).not.toContain("'-translate-y-full'");
  });
});
