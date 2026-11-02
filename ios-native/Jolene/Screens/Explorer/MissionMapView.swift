import SwiftUI
import MapKit
import JoleneCore
import JoleneDesign

/// Source du fond de carte. Le mode démonstration n'envoie aucune requête réseau (PRINCIPES §2,
/// §7 niveau 2) : il affiche un aperçu dessiné localement au lieu des tuiles Apple Plans.
enum CarteTuiles: Equatable, Sendable {
    case mapKit
    case horsLigne
}

private struct CarteTuilesKey: EnvironmentKey {
    /// Défaut prudent : sans réglage explicite (`MainTabView`), aucune tuile n'est demandée.
    static let defaultValue: CarteTuiles = .horsLigne
}

extension EnvironmentValues {
    var carteTuiles: CarteTuiles {
        get { self[CarteTuilesKey.self] }
        set { self[CarteTuilesKey.self] = newValue }
    }
}

/// Carte en lecture seule du détail mission (lot 1, T4a) : un repère sur l'établissement
/// (`CarteMission.point(pour:)`), ni déplacement ni zoom, aucune position du soignant (pas de
/// demande de localisation). Les coordonnées sont des valeurs serveur (`fn_etablissements_safe`).
///
/// Identifiants : `mission-detail-carte` (bloc), `mission-detail-carte-map` (MapKit),
/// `mission-detail-carte-demo` (aperçu hors ligne), `mission-detail-carte-legende` (légende).
struct MissionMapView: View {
    let point: PointCarte
    @Environment(\.carteTuiles) private var tuiles

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            Text("Localisation")
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            fond
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(JoleneColor.rose100, lineWidth: 1))
            Text(point.legende)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("mission-detail-carte-legende")
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mission-detail-carte")
    }

    @ViewBuilder private var fond: some View {
        switch tuiles {
        case .mapKit:
            CarteMapKit(point: point)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(point.accessibilityLabel)
                .accessibilityIdentifier("mission-detail-carte-map")
        case .horsLigne:
            CarteHorsLigne(point: point)
        }
    }
}

/// Tuiles Apple Plans (STAGING, production). iOS 17 et suivants : `Map(initialPosition:)` +
/// `Marker` ; iOS 16 : `Map(coordinateRegion:)` + `MapMarker`, API dépréciée en iOS 17 seulement.
private struct CarteMapKit: View {
    let point: PointCarte

    private struct Repere: Identifiable {
        let id = 0
        let coordonnee: CLLocationCoordinate2D
    }

    private var coordonnee: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(center: coordonnee, latitudinalMeters: CarteMission.etendueMetres,
                           longitudinalMeters: CarteMission.etendueMetres)
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            Map(initialPosition: .region(region), interactionModes: []) {
                Marker(point.titre, coordinate: coordonnee)
                    .tint(JoleneColor.rose700)
            }
        } else {
            Map(coordinateRegion: .constant(region), interactionModes: [], showsUserLocation: false,
                annotationItems: [Repere(coordonnee: coordonnee)]) { repere in
                MapMarker(coordinate: repere.coordonnee, tint: JoleneColor.rose700)
            }
        }
    }
}

/// Aperçu sans réseau du mode démonstration : repère centré sur un quadrillage dessiné
/// localement, légende identique à la carte réelle.
private struct CarteHorsLigne: View {
    let point: PointCarte

    var body: some View {
        ZStack {
            JoleneColor.softGradient
            Canvas { contexte, taille in
                let pas: CGFloat = 24
                var trace = Path()
                var x: CGFloat = 0
                while x <= taille.width { trace.move(to: CGPoint(x: x, y: 0)); trace.addLine(to: CGPoint(x: x, y: taille.height)); x += pas }
                var y: CGFloat = 0
                while y <= taille.height { trace.move(to: CGPoint(x: 0, y: y)); trace.addLine(to: CGPoint(x: taille.width, y: y)); y += pas }
                contexte.stroke(trace, with: .color(JoleneColor.mauve.opacity(0.18)), lineWidth: 1)
            }
            .accessibilityHidden(true)
            VStack(spacing: JoleneSpacing.xs) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(JoleneColor.rose700)
                    .accessibilityHidden(true)
                Text("Aperçu de démonstration, sans fond de carte")
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.midnight)
                    .padding(.horizontal, JoleneSpacing.sm)
                    .padding(.vertical, JoleneSpacing.xs)
                    .background(JoleneColor.cloud.opacity(0.9))
                    .clipShape(Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(point.accessibilityLabel). Aperçu de démonstration, sans fond de carte")
        .accessibilityIdentifier("mission-detail-carte-demo")
    }
}
