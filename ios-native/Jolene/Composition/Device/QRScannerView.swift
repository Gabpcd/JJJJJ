import AVFoundation
import SwiftUI
import UIKit

/// Événement d'un scanner de QR (réel ou démo), remis à la feuille de scan (`ScannerQRSheet`), qui décide de la remise
/// unique (`SessionScanQR`, JoleneCore).
enum EvenementScanner: Equatable, Sendable {
    /// Contenu d'un QR détecté (chaque nouveau contenu, une fois).
    case payload(String)
    /// Caméra refusée par l'utilisateur ou par les réglages : saisie manuelle (web l.190-192).
    case refus
    /// Aucune caméra utilisable (simulateur, appareil sans caméra, configuration impossible) : saisie manuelle.
    case indisponible
}

/// Scanner réel du QR affiché par l'établissement (décision 3 : `AVCaptureMetadataOutput` `.qr`, pas VisionKit ; le QR
/// encode `code_pointage_actif`, `AffichageCodeRotatifEtab.tsx` l.284). La session ne démarre qu'avec l'autorisation de la
/// caméra (chaîne `NSCameraUsageDescription` du lot 0) ; pendant une demande d'autorisation en vol, rien ne démarre, et
/// une fermeture pendant cette demande n'ouvre jamais la caméra ensuite (tests web `PointageRotatifSoignant.qr.test.tsx`
/// l.132-157) ; la session s'arrête à la disparition de la vue. Chaque contenu distinct n'est remis qu'une fois : la
/// remise unique d'un CODE par session est la règle de `SessionScanQR`. Aucun contenu n'est journalisé.
struct QRScannerView: UIViewControllerRepresentable {
    let surEvenement: @MainActor (EvenementScanner) -> Void

    func makeUIViewController(context: Context) -> ControleurScannerQR {
        let controleur = ControleurScannerQR()
        controleur.surEvenement = surEvenement
        return controleur
    }

    func updateUIViewController(_ controleur: ControleurScannerQR, context: Context) {
        controleur.surEvenement = surEvenement
    }

    static func dismantleUIViewController(_ controleur: ControleurScannerQR, coordinator: ()) {
        controleur.arreter()
    }
}

/// Session de capture et sa file série : `AVCaptureSession` n'est pas `Sendable` ; elle n'est démarrée et arrêtée que sur
/// `file` (appels bloquants hors du fil principal), configurée sur le fil principal avant tout démarrage.
final class SessionCaptureQR: @unchecked Sendable {
    let session = AVCaptureSession()
    private let file = DispatchQueue(label: "app.jolene.scanner-qr")

    func demarrer() {
        file.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    func arreter() {
        file.async { if self.session.isRunning { self.session.stopRunning() } }
    }
}

final class ControleurScannerQR: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var surEvenement: (@MainActor (EvenementScanner) -> Void)?

    private let capture = SessionCaptureQR()
    private var apercu: AVCaptureVideoPreviewLayer?
    private var configuree = false
    private var arrete = false
    private var demandeEnVol = false
    private var remis: Set<String> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.isAccessibilityElement = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arrete = false
        demarrerSiAutorise()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arreter()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        apercu?.frame = view.bounds
    }

    func arreter() {
        arrete = true
        capture.arreter()
    }

    private func demarrerSiAutorise() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configurerEtDemarrer()
        case .notDetermined:
            guard !demandeEnVol else { return }
            demandeEnVol = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] accorde in
                Task { @MainActor [weak self] in self?.reponseAutorisation(accorde) }
            }
        default:
            surEvenement?(.refus)
        }
    }

    private func reponseAutorisation(_ accorde: Bool) {
        demandeEnVol = false
        // Fermée pendant la demande : la caméra ne s'ouvre jamais après coup.
        guard !arrete else { return }
        if accorde { configurerEtDemarrer() } else { surEvenement?(.refus) }
    }

    private func configurerEtDemarrer() {
        guard !arrete else { return }
        if !configuree {
            guard let camera = AVCaptureDevice.default(for: .video), let entree = try? AVCaptureDeviceInput(device: camera) else {
                surEvenement?(.indisponible)
                return
            }
            let session = capture.session
            let sortie = AVCaptureMetadataOutput()
            session.beginConfiguration()
            guard session.canAddInput(entree), session.canAddOutput(sortie) else {
                session.commitConfiguration()
                surEvenement?(.indisponible)
                return
            }
            session.addInput(entree)
            session.addOutput(sortie)
            sortie.setMetadataObjectsDelegate(self, queue: .main)
            sortie.metadataObjectTypes = sortie.availableMetadataObjectTypes.contains(.qr) ? [.qr] : []
            session.commitConfiguration()
            let couche = AVCaptureVideoPreviewLayer(session: session)
            couche.videoGravity = .resizeAspectFill
            couche.frame = view.bounds
            view.layer.addSublayer(couche)
            apercu = couche
            configuree = true
        }
        capture.demarrer()
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate (file principale, posée ci-dessus)

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        let contenus = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        Task { @MainActor [weak self] in self?.recevoir(contenus) }
    }

    private func recevoir(_ contenus: [String]) {
        guard !arrete else { return }
        for contenu in contenus where remis.insert(contenu).inserted {
            surEvenement?(.payload(contenu))
        }
    }
}
