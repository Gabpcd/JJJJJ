import Foundation

/// Lot 3, T3b — revue fraîche B8, M1 (`DECISIONS_LOT3.md`, section T3b) : fin d'identité native vue par le navigateur
/// intégré de l'app. Le renvoi web (`SFSafariViewController`, présenté par le coordinateur des liens) garde dans le
/// magasin de données **de l'app** les cookies, le cache et le `localStorage` où le web Supabase conserve sa session :
/// sans effacement, une page `/soignant/*` rouverte après une déconnexion servirait l'espace web de l'identité close.
///
/// `SessionStore` appelle `identiteTerminee()` :
/// - une fois par fin d'identité : déconnexion volontaire (`signOut`), fin de compte (`signOutLocally`), absence de
///   session confirmée par le contrôleur après une identité (`.signedOut` du SDK, revalidation sans session) ;
/// - avant chaque connexion par mot de passe (`signIn`) : l'identité qui s'ouvre ne trouve jamais les données web d'une
///   autre (identité close hors de l'app, session web ouverte sans identité native, identité remplacée après une fin
///   transitoire) ;
/// - jamais sur une fin transitoire (le SDK détient encore la session) ni au lancement à froid sans session.
///
/// Implémentation de l'app (`DeepLinkCoordinator`) : ferme le renvoi affiché, puis efface le magasin
/// (`SFSafariViewController.DataStore.default.clearWebsiteData`, iOS 16) en différant tout renvoi demandé pendant
/// l'effacement (`PresentationsRacine`). En démo : aucun effacement (le double du renvoi n'a ni réseau ni données) ; la
/// feuille du double est fermée comme ailleurs. Sans port (doubles du lot 1), rien ne change.
@MainActor
public protocol FinIdentiteWebPort: AnyObject {
    func identiteTerminee()
}
