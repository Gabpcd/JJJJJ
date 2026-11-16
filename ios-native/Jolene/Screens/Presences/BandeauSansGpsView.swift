import SwiftUI
import JoleneCore
import JoleneDesign

/// Bandeau du pointage sans localisation (lot 2, T4b), port de `BandeauSansGPS.tsx` l.4-13 : affiché en tête de la page
/// Présences quand le consentement relu est un refus (`consentementGPS === false`, `PresencesSoignant.tsx` l.509). Texte
/// verbatim `TextesWeb.BandeauSansGps.texte` (HARD STOP n°4, tutoiement du web conservé). Identifiant `bandeau-sans-gps`.
struct BandeauSansGpsView: View {
    var body: some View {
        InlineNotice(TextesWeb.BandeauSansGps.texte, tone: .warning, identifier: "bandeau-sans-gps")
    }
}
