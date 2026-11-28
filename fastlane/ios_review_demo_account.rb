# Vérification du compte de démonstration de la revue Apple (lane `ios submit_native` et son pré-vol
# `ios preflight_review_native`, docs/mobile-swift/APP_STORE.md, section « Notes pour la revue et compte de
# démonstration »).
#
# Avec le nom et le mot de passe lus dans la fiche App Store Connect, la lane se connecte à Supabase de PRODUCTION
# exactement comme l'app native (`SupabaseAuthGateway.signIn` : `POST /auth/v1/token?grant_type=password`, clé
# publishable en `apikey`, aucun jeton captcha), relit le rôle par la même RPC que l'app (`fn_get_my_role`,
# `SupabaseRoleGateway`), puis révoque aussitôt la session (`POST /auth/v1/logout?scope=local` : cette session
# seulement). Hypothèse : le réglage Supabase Auth « session unique par utilisateur » est désactivé (il n'est pas fixé
# par le dépôt) ; s'il était actif, la connexion elle-même fermerait la session d'un relecteur. Le pré-vol ne se
# connecte pas quand la version est en revue, approuvée, en attente de publication ou en vente (ReviewNotes::SOUMISES).
# Il se connecte en revanche quand elle attend la revue (WAITING_FOR_REVIEW, état modifiable, contrôlé en entier),
# avant qu'un relecteur ne l'ouvre ; voir APP_STORE.md.
#
# URL et clé publishable : valeurs publiques de `ios-native/Config/Production.xcconfig`, lues dans le dépôt ; aucun
# secret nouveau. Rien n'est journalisé hors « compte de démo : … » : ni adresse, ni mot de passe, ni jeton, ni
# identifiant, ni corps de réponse. Net::HTTP n'écrit aucun journal.
require 'json'
require 'net/http'
require 'uri'
require_relative 'ios_review_submission'

module IosReviewSubmission
  DOC_NOTES = 'docs/mobile-swift/APP_STORE.md, section « Notes pour la revue et compte de démonstration »'

  class CompteDemo
    CONFIG = 'ios-native/Config/Production.xcconfig'

    # Fonction pure : un objet JSON, ou {} pour toute autre réponse (rien n'en est jamais recopié).
    def self.lire_json(corps)
      valeur = JSON.parse(corps.to_s)
      valeur.is_a?(Hash) ? valeur : {}
    rescue JSON::ParserError
      {}
    end
    # Rôles que l'app sert nativement et que le bloc sait décrire ; tout autre rôle est refusé.
    ROLES = { 'SOIGNANT' => :soignant, 'ADMIN_ETABLISSEMENT' => :etablissement }.freeze
    LIBELLES = { soignant: 'soignant', etablissement: 'établissement' }.freeze
    # Autres valeurs connues de `fn_get_my_role`, citées telles quelles ; une valeur inconnue n'est jamais recopiée.
    ROLES_REFUSES = %w[ADMIN_PLATEFORME ADMIN_GROUPE INCONNU].freeze

    # Fonction pure : URL et clé publishable de production, depuis le xcconfig (`https:/$()/…` y protège `//`).
    def self.lire_config!(texte)
      valeur = lambda do |cle|
        lignes = texte.to_s.lines.map(&:strip).grep(/\A#{cle}\s*=/)
        raise Failure, "#{CONFIG} : #{cle} absent ou répété (voir #{DOC_NOTES})" unless lignes.one?
        lignes.first.split('=', 2).last.strip.gsub('$()', '')
      end
      environnement = valeur.call('JOLENE_ENVIRONMENT')
      url = valeur.call('JOLENE_SUPABASE_URL')
      cle = valeur.call('JOLENE_SUPABASE_PUBLISHABLE_KEY')
      unless environnement == 'production' && url.match?(%r{\Ahttps://[a-z0-9]{20}\.supabase\.co\z}) && cle.match?(/\Asb_publishable_[A-Za-z0-9_-]{20,}\z/)
        raise Failure, "#{CONFIG} : configuration de production illisible (voir #{DOC_NOTES})"
      end
      { url: url, cle: cle }
    end

    PREFIXE_REFUS = 'compte de démo : '
    FIN_REFUS = " ; rien n'est écrit ni soumis (voir #{DOC_NOTES})"

    # Fonction pure : message d'un refus, toujours préfixé et fermé.
    def self.refus_ferme(motif)
      "#{PREFIXE_REFUS}#{motif}#{FIN_REFUS}"
    end

    # Fonction pure : un refus fermé complété d'un motif fermé, avant sa fin (revue B8 n° 2 de #1202, m1). Un message
    # d'une autre forme est gardé tel quel, le complément ajouté à la suite.
    def self.completer_refus(message, complement)
      texte = message.to_s
      return "#{texte} ; #{complement}" unless texte.start_with?(PREFIXE_REFUS) && texte.end_with?(FIN_REFUS)
      refus_ferme("#{texte.delete_prefix(PREFIXE_REFUS).delete_suffix(FIN_REFUS)} ; #{complement}")
    end

    # Requêtes HTTPS de la vérification ; seul ce transport touche le réseau. Ni journal ni nouvelle tentative.
    # Rend [statut, corps, en-têtes], ces derniers réduits à ENTETES_REPONSE.
    #
    # Compression : chaque appel demande `Accept-Encoding: identity`, un corps non compressé. Net::HTTP ne décompresse
    # jamais une réponse qui porte `Content-Range` (net-http 0.9.1 comme 0.4.x, `response.rb`, `inflater` :
    # `return yield @socket if self['content-range']`). Or PostgREST pose `Content-Range: 0-0/*` sur ses réponses RPC,
    # que Cloudflare compresse ensuite en gzip : le corps de `fn_get_my_role` arrivait compressé (run `verifier` n° 2).
    # Une réponse encore encodée est refusée par `CompteDemo#appeler` (« réponse encodée »).
    class TransportHttps
      ENTETES_REPONSE = %w[content-type content-encoding content-range].freeze
      ENTETES_INTERDITS = %w[accept-encoding range].freeze

      # Fonction pure : la requête, `Accept-Encoding: identity` posé à la construction.
      def self.construire(uri, entetes, corps)
        interdits = entetes.keys.map { |nom| nom.to_s.downcase } & ENTETES_INTERDITS
        raise Failure, CompteDemo.refus_ferme("transport refusé : en-tête #{interdits.join(', ')} fourni par l'appelant") unless interdits.empty?
        requete = Net::HTTP::Post.new(uri, { 'Accept-Encoding' => 'identity' })
        entetes.each { |nom, valeur| requete[nom] = valeur }
        requete.body = corps
        raise Failure, CompteDemo.refus_ferme('transport refusé : corps non compressé non demandé') unless requete['accept-encoding'] == 'identity'
        requete
      end

      def self.executer(http, requete)
        reponse = http.request(requete)
        [reponse.code.to_i, reponse.body.to_s, ENTETES_REPONSE.to_h { |nom| [nom, reponse[nom]] }.compact]
      end

      def post(url, entetes, corps)
        uri = URI(url)
        raise Failure, CompteDemo.refus_ferme('transport refusé : HTTPS seulement') unless uri.scheme == 'https'
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20, write_timeout: 20) do |http|
          TransportHttps.executer(http, TransportHttps.construire(uri, entetes, corps))
        end
      end
    end

    # Lecture STRICTE, comme l'app (`SupabaseRoleGateway.roleResult`) : objet racine portant `role` texte, et rien
    # d'autre. `fn_get_my_role` est scalaire (RETURNS jsonb, non SETOF) : PostgREST rend l'objet nu.
    def self.extraire_role(corps)
      valeur = lire_json_brut(corps)
      valeur.is_a?(Hash) && valeur['role'].is_a?(String) ? valeur['role'] : nil
    end

    # Noms de clés que le diagnostic peut citer ; les autres ne sont que comptées.
    CLES_ROLE_CONNUES = %w[role user_id etablissement_id fn_get_my_role].freeze
    # Vocabulaires fermés : jamais la valeur brute d'un en-tête du serveur. `application/vnd.pgrst.object+json`
    # (PostgREST) et `zstd` (Cloudflare) y figurent pour un diagnostic précis (revue B8 n° 2 de #1202, n2).
    MIMES = %w[application/json application/vnd.pgrst.object+json text/html text/plain].freeze
    ENCODAGES = %w[gzip br deflate zstd identity].freeze

    def self.entete(entetes, nom)
      (entetes || {}).each { |cle, valeur| return valeur.to_s if cle.to_s.downcase == nom }
      nil
    end

    def self.mime_ferme(valeur)
      mime = valeur.to_s.split(';').first.to_s.strip.downcase
      return 'absent' if mime.empty?
      MIMES.include?(mime) ? mime : 'autre'
    end

    def self.encodage_ferme(valeur)
      encodage = valeur.to_s.strip.downcase
      return 'aucun' if encodage.empty?
      ENCODAGES.include?(encodage) ? encodage : 'autre'
    end

    # Fonction pure : diagnostic d'une réponse de rôle illisible, sans aucune valeur. Type JSON racine ; pour un objet,
    # les noms de clés de la liste blanche, le nombre des autres et le type de `role` s'il est présent ; pour un tableau,
    # le nombre d'éléments et le type d'un élément unique ; pour une chaîne, le type JSON qu'elle encode ; puis le type
    # MIME et l'encodage pris dans des listes fermées, la taille du corps et la présence de `Content-Range`.
    def self.diagnostic_role(corps, entetes)
      valeur = lire_json_brut(corps)
      elements = ["JSON racine : #{type_json(valeur)}"]
      case valeur
      when Hash
        connues = CLES_ROLE_CONNUES & valeur.keys
        autres = valeur.keys.length - connues.length
        elements << (connues.empty? ? 'aucune clé connue' : "clés : #{connues.join(', ')}")
        elements << "autres clés : #{autres}" if autres.positive?
        elements << "type de role : #{type_json(valeur['role'])}" if valeur.key?('role')
      when Array
        elements << "éléments : #{valeur.length}"
        elements << "type de l'élément : #{type_json(valeur.first)}" if valeur.length == 1
      when String
        elements << "contenu : #{type_json(lire_json_brut(valeur))}"
      end
      elements << "type : #{mime_ferme(entete(entetes, 'content-type'))}" << "corps : #{corps.to_s.bytesize} octets" <<
        "encodage : #{encodage_ferme(entete(entetes, 'content-encoding'))}" <<
        "Content-Range : #{entete(entetes, 'content-range').to_s.strip.empty? ? 'non' : 'oui'}"
      elements.join(' ; ')
    end

    # Fonction pure : la valeur JSON, ou :invalide.
    def self.lire_json_brut(texte)
      JSON.parse(texte.to_s)
    rescue JSON::ParserError
      :invalide
    end

    def self.type_json(valeur)
      case valeur
      when Hash then 'objet'
      when Array then 'tableau'
      when String then 'chaîne'
      when Integer, Float then 'nombre'
      when true, false then 'booléen'
      when nil then 'null'
      else 'invalide'
      end
    end

    def initialize(url:, cle:, transport: TransportHttps.new)
      @url, @cle, @transport = url, cle, transport
    end

    # Connexion, rôle, déconnexion. Rend :soignant ou :etablissement ; sinon lève, avec un motif fermé.
    def verifier!(nom:, mot_de_passe:)
      email = nom.to_s.strip
      raise Failure, refus('identifiants absents') if email.empty? || mot_de_passe.to_s.empty?
      statut, corps = appeler('/auth/v1/token?grant_type=password', { 'email' => email, 'password' => mot_de_passe.to_s }, etape: 'connexion')
      jeton = statut == 200 ? CompteDemo.lire_json(corps)['access_token'] : nil
      unless statut == 200 && jeton.is_a?(String) && !jeton.empty?
        raise Failure, refus(statut == 200 ? 'réponse illisible (HTTP 200)' : CompteDemo.motif_refus(statut, corps))
      end
      # Le rôle refusé ne masque pas l'issue de la déconnexion, tentée dans tous les cas : une session du compte de
      # démonstration restée ouverte est dite dans le même message (revue B8 n° 2 de #1202, m1).
      begin
        role = lire_role(jeton)
      rescue Failure => echec_role
        role = nil
      ensure
        sortie = deconnecter(jeton)
      end
      if echec_role
        raise echec_role if sortie == :ok
        raise Failure, CompteDemo.completer_refus(echec_role.message, "déconnexion non confirmée (#{sortie})")
      end
      raise Failure, refus("connexion OK, déconnexion non confirmée (#{sortie})") unless sortie == :ok
      ROLES.fetch(role) do
        affiche = ROLES_REFUSES.include?(role) ? role : 'inattendu'
        raise Failure, refus("connexion OK, rôle #{affiche} : l'app ne sert pas ce compte, seuls soignant et établissement sont admis")
      end
    end

    # Fonction pure : motif d'un refus de connexion, sans rien recopier de la réponse.
    def self.motif_refus(statut, corps)
      reponse = CompteDemo.lire_json(corps)
      captcha = reponse['error_code'] == 'captcha_failed' || [reponse['msg'], reponse['error_description']].any? { |m| m.to_s.match?(/captcha/i) }
      captcha ? "connexion refusée, captcha exigé (HTTP #{statut})" : "connexion refusée (HTTP #{statut})"
    end

    private

    def refus(motif)
      CompteDemo.refus_ferme(motif)
    end

    # Seule entrée des trois appels. Une réponse dont `Content-Encoding` n'est ni absent ni `identity` est refusée :
    # son corps n'a pas été décompressé (voir TransportHttps).
    def appeler(chemin, corps, etape:, jeton: nil)
      entetes = { 'apikey' => @cle, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
      entetes['Authorization'] = "Bearer #{jeton}" if jeton
      reponse = @transport.post("#{@url}#{chemin}", entetes, JSON.generate(corps))
      encodage = CompteDemo.encodage_ferme(CompteDemo.entete(reponse[2], 'content-encoding'))
      unless %w[aucun identity].include?(encodage)
        # Connexion acceptée (HTTP 200) mais corps illisible : le jeton n'est pas lu, la session éventuellement ouverte
        # ne peut pas être révoquée (revue B8 n° 2 de #1202, n1).
        session = etape == 'connexion' && reponse[0] == 200 ? ' ; session éventuellement ouverte, non révoquée' : ''
        raise Failure, refus("réponse encodée (#{etape}, HTTP #{reponse[0]} ; encodage : #{encodage})#{session}")
      end
      reponse
    rescue Failure
      raise
    rescue StandardError => error
      raise Failure, refus("connexion impossible (réseau : #{error.class})")
    end

    def lire_role(jeton)
      statut, corps, entetes = appeler('/rest/v1/rpc/fn_get_my_role', {}, etape: 'lecture du rôle', jeton: jeton)
      role = statut == 200 ? CompteDemo.extraire_role(corps) : nil
      return role if role
      raise Failure, refus("connexion OK, rôle illisible (HTTP #{statut} ; #{CompteDemo.diagnostic_role(corps, entetes)})")
    end

    def deconnecter(jeton)
      statut, = appeler('/auth/v1/logout?scope=local', {}, etape: 'déconnexion', jeton: jeton)
      (200..299).cover?(statut) ? :ok : "HTTP #{statut}"
    rescue Failure => error
      error.message[/réseau : [A-Za-z0-9:_]+|réponse encodée/] || 'réseau'
    end
  end
end
