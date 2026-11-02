import SwiftUI
import JoleneCore
import JoleneDesign

/// Profil › Sécurité (lot 1, T9, décision 1) : déverrouillage biométrique du compte connecté.
/// Identifiants : `securite-screen`, `biometrie-toggle`, `biometrie-indisponible`, `biometrie-message`.
/// Démo et appareil sans biométrie enrôlée : interrupteur grisé, « Non disponible sur cet appareil ».
struct SecuriteScreen: View {
    @StateObject private var model: SecuriteModel

    init(session: SessionStore, snapshot: SessionSnapshot) {
        _model = StateObject(wrappedValue: SecuriteModel(gate: session.biometrie, userId: snapshot.user.id))
    }

    var body: some View {
        List {
            Section {
                Toggle(model.libelleInterrupteur, isOn: Binding(
                    get: { model.interrupteur },
                    set: { activer in Task { await model.basculer(activer) } }
                ))
                .tint(JoleneColor.rose700)
                .disabled(!model.interrupteurModifiable)
                .accessibilityIdentifier("biometrie-toggle")
                if model.estIndisponible {
                    Text(SecuriteModel.indisponibleMessage)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityIdentifier("biometrie-indisponible")
                }
                if let message = model.message {
                    InlineNotice(message, tone: .error, identifier: "biometrie-message", announcesOnAppear: true)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            } header: {
                Text("Déverrouillage")
            } footer: {
                Text(model.explication)
            }
        }
        .accessibilityIdentifier("securite-screen")
        .scrollContentBackground(.hidden)
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle("Sécurité")
        .task { await model.charger() }
    }
}
