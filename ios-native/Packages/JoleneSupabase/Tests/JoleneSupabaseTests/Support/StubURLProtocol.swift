import Foundation

/// Requête capturée par le transport de test (méthode, chemin, query décodée, en-têtes, corps).
struct RecordedRequest: Sendable {
    let method: String
    let url: URL
    let path: String
    let queryItems: [URLQueryItem]
    let headers: [String: String]
    let body: Data?
    /// Politique de cache de la requête (L3-T10, revue B8 m11 : lecture de l'avatar sans cache local).
    let cachePolicy: URLRequest.CachePolicy

    init(_ request: URLRequest) {
        method = request.httpMethod ?? "GET"
        cachePolicy = request.cachePolicy
        url = request.url ?? URL(string: "about:blank")!
        path = url.path
        queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        headers = request.allHTTPHeaderFields ?? [:]
        body = request.httpBody ?? Self.read(stream: request.httpBodyStream)
    }

    func query(_ name: String) -> String? {
        queryItems.first { $0.name == name }?.value
    }

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var bodyJSON: Any? {
        guard let body, !body.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: body)
    }

    private static func read(stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Réponse simulée : statut + en-têtes + corps, ou échec réseau.
struct StubResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var body: Data
    var failure: URLError?

    static func json(_ status: Int, _ text: String, headers: [String: String] = [:]) -> StubResponse {
        var merged = ["Content-Type": "application/json"]
        merged.merge(headers) { _, new in new }
        return StubResponse(status: status, headers: merged, body: Data(text.utf8), failure: nil)
    }

    static func networkFailure(_ code: URLError.Code = .notConnectedToInternet) -> StubResponse {
        StubResponse(status: 0, headers: [:], body: Data(), failure: URLError(code))
    }
}

/// Registre partagé des stubs (une entrée = méthode + chemin + prédicat optionnel).
/// Thread-safe : URLProtocol est appelé sur des files système.
final class StubRegistry: @unchecked Sendable {
    static let shared = StubRegistry()

    struct Stub {
        let method: String
        let path: String
        let predicate: (@Sendable (RecordedRequest) -> Bool)?
        let response: StubResponse
    }

    private let lock = NSLock()
    private var stubs: [Stub] = []
    private var recorded: [RecordedRequest] = []
    private var unmatchedRequests: [RecordedRequest] = []

    func reset() {
        lock.lock(); defer { lock.unlock() }
        stubs = []; recorded = []; unmatchedRequests = []
    }

    func add(_ method: String, _ path: String, where predicate: (@Sendable (RecordedRequest) -> Bool)? = nil, respond response: StubResponse) {
        lock.lock(); defer { lock.unlock() }
        stubs.append(Stub(method: method, path: path, predicate: predicate, response: response))
    }

    var requests: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    var unmatched: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return unmatchedRequests
    }

    func requests(to path: String) -> [RecordedRequest] {
        requests.filter { $0.path == path }
    }

    /// Issue de la résolution d'une requête arrivée au transport.
    enum Resolution {
        /// La tâche URLSession était déjà annulée : la requête n'est ni enregistrée ni servie.
        case annulee
        case sansStub
        case reponse(StubResponse)
    }

    /// `annulee` est évalué SOUS le verrou du registre. Une lecture lancée par `async let` puis annulée (l'appel
    /// principal a levé) peut n'atteindre le transport qu'après le retour de la passerelle, donc après le `reset()`
    /// suivant du test : enregistrée, elle fausse un « aucune requête » (échec intermittent du 23/11/2026, run CI
    /// 45200687105, `SupabaseEtabDashboardGatewayTests`). Sous le verrou, il n'y a que deux ordres possibles : soit
    /// l'annulation précède ce contrôle et la requête est ignorée, soit l'enregistrement précède le `reset()` qui suit
    /// le retour de l'appel, et il est effacé. L'argument est complet pour une lecture attendue avant le retour
    /// (`async let`) ; pour un perdant annulé sans être attendu (`bounded`), il repose sur le fait que
    /// `URLSessionTask.cancel()` marque la tâche avant de rendre la main. Une requête tardive NON annulée (tâche non
    /// structurée) reste enregistrée : ces tests attendent déjà leurs requêtes.
    func resolve(_ request: RecordedRequest, annulee: () -> Bool = { false }) -> Resolution {
        lock.lock(); defer { lock.unlock() }
        if annulee() { return .annulee }
        recorded.append(request)
        let match = stubs.first { stub in
            stub.method == request.method && stub.path == request.path && (stub.predicate?(request) ?? true)
        }
        guard let match else {
            unmatchedRequests.append(request)
            return .sansStub
        }
        return .reponse(match.response)
    }
}

/// Transport injecté via `URLSessionConfiguration.protocolClasses` (plan §4.1 : transports
/// injectés). Toute requête non stubée échoue avec `URLError.unsupportedURL` et est listée
/// dans `StubRegistry.unmatched` pour que le test l'affirme. Seule exception : une requête dont la
/// tâche est déjà annulée à son arrivée n'est ni enregistrée ni listée (voir `StubRegistry.resolve`).
final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// Vrai pour une tâche annulée, qu'elle soit encore en cours d'annulation ou déjà terminée : une tâche annulée
    /// avant d'atteindre le transport y arrive le plus souvent à l'état `.completed`. Sans tâche (`nil`), la requête
    /// est tenue pour vivante.
    static func tacheAnnulee(_ tache: URLSessionTask?) -> Bool {
        tache?.state == .canceling || tache?.state == .completed
    }

    override func startLoading() {
        let recorded = RecordedRequest(request)
        let tache = task
        let stub: StubResponse
        switch StubRegistry.shared.resolve(recorded, annulee: { Self.tacheAnnulee(tache) }) {
        case .annulee:
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        case .sansStub:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        case .reponse(let reponse):
            stub = reponse
        }
        if let failure = stub.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(url: recorded.url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
