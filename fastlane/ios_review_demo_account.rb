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

    # Requêtes HTTPS de la vérification ; seul ce transport touche le réseau. Ni journal ni nouvelle tentative.
    # Rend [statut, corps, en-têtes], ces derniers réduits à ENTETES_REPONSE (diagnostic d'une réponse illisible).
    #
    # Compression : la requête est construite sans en-têtes initiaux, donc Net::HTTP pose lui-même
    # `Accept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3` et garde `decode_content` vrai : un corps gzip ou
    # deflate est décompressé à la lecture, puis Net::HTTP retire `Content-Encoding`. Un `Accept-Encoding` ou un `Range`
    # fournis par l'appelant désactiveraient ce décodage : ils sont refusés.
    class TransportHttps
      ENTETES_REPONSE = %w[content-type content-encoding].freeze
      ENTETES_INTERDITS = %w[accept-encoding range].freeze

      # Fonction pure : la requête, décompression automatique comprise.
      def self.construire(uri, entetes, corps)
        interdits = entetes.keys.map { |nom| nom.to_s.downcase } & ENTETES_INTERDITS
        raise Failure, "Transport refusé : en-tête #{interdits.join(', ')} (décompression de Net::HTTP)" unless interdits.empty?
        requete = Net::HTTP::Post.new(uri)
        entetes.each { |nom, valeur| requete[nom] = valeur }
        requete.body = corps
        raise Failure, 'Transport refusé : décompression de Net::HTTP désactivée' unless requete.decode_content
        requete
      end

      def self.executer(http, requete)
        reponse = http.request(requete)
        [reponse.code.to_i, reponse.body.to_s, ENTETES_REPONSE.to_h { |nom| [nom, reponse[nom]] }.compact]
      end

      def post(url, entetes, corps)
        uri = URI(url)
        raise Failure, 'Transport refusé : HTTPS seulement' unless uri.scheme == 'https'
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20, write_timeout: 20) do |http|
          TransportHttps.executer(http, TransportHttps.construire(uri, entetes, corps))
        end
      end
    end

    # Formes admises de la réponse de `fn_get_my_role` (RETURNS jsonb, non SETOF), et leurs combinaisons, trois déballages
    # au plus : objet portant `role` texte ; tableau d'un seul élément (forme SETOF ou vnd.pgrst) ; objet à la seule clé
    # `fn_get_my_role` ; chaîne JSON qui encode l'une de ces formes. Toute autre forme est refusée.
    CLES_ROLE_CONNUES = %w[role user_id etablissement_id fn_get_my_role].freeze

    # Fonction pure : le rôle (texte) ou nil. Rien n'est recopié ni journalisé.
    def self.extraire_role(corps)
      valeur = lire_json_brut(corps)
      4.times do
        case valeur
        when Hash
          return valeur['role'] if valeur['role'].is_a?(String)
          return nil unless valeur.keys == ['fn_get_my_role']
          valeur = valeur['fn_get_my_role']
        when Array
          return nil unless valeur.length == 1
          valeur = valeur.first
        when String
          valeur = lire_json_brut(valeur)
        else
          return nil
        end
      end
      nil
    end

    # Fonction pure : diagnostic d'une réponse de rôle illisible, sans aucune valeur. Type JSON racine ; pour un objet,
    # les noms de clés de premier niveau de la liste blanche, et le nombre des autres ; pour un tableau, le nombre
    # d'éléments ; pour une chaîne, le type JSON qu'elle encode ; puis le type MIME, la taille du corps et l'encodage
    # restant après la décompression de Net::HTTP.
    def self.diagnostic_role(corps, entetes)
      valeur = lire_json_brut(corps)
      elements = ["JSON racine : #{type_json(valeur)}"]
      case valeur
      when Hash
        connues = CLES_ROLE_CONNUES & valeur.keys
        autres = valeur.keys.length - connues.length
        elements << (connues.empty? ? 'aucune clé connue' : "clés : #{connues.join(', ')}")
        elements << "autres clés : #{autres}" if autres.positive?
      when Array
        elements << "éléments : #{valeur.length}"
      when String
        elements << "contenu : #{type_json(lire_json_brut(valeur))}"
      end
      entetes = (entetes || {}).to_h { |nom, v| [nom.to_s.downcase, v.to_s] }
      mime = entetes['content-type'].to_s.split(';').first.to_s.strip.downcase
      mime = 'absent' if mime.empty?
      mime = 'illisible' unless mime == 'absent' || mime.match?(%r{\A[a-z0-9.+-]+/[a-z0-9.+-]+\z})
      encodage = entetes['content-encoding'].to_s.strip.downcase
      encodage = 'aucun' if encodage.empty?
      encodage = 'illisible' unless encodage.match?(/\A[a-z0-9-]+\z/)
      elements << "type : #{mime}" << "corps : #{corps.to_s.bytesize} octets" << "encodage : #{encodage}"
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
      statut, corps = appeler('/auth/v1/token?grant_type=password', { 'email' => email, 'password' => mot_de_passe.to_s })
      jeton = statut == 200 ? CompteDemo.lire_json(corps)['access_token'] : nil
      unless statut == 200 && jeton.is_a?(String) && !jeton.empty?
        raise Failure, refus(statut == 200 ? 'réponse illisible (HTTP 200)' : CompteDemo.motif_refus(statut, corps))
      end
      begin
        role = lire_role(jeton)
      ensure
        sortie = deconnecter(jeton)
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
      "compte de démo : #{motif} ; rien n'est écrit ni soumis (voir #{DOC_NOTES})"
    end

    def appeler(chemin, corps, jeton: nil)
      entetes = { 'apikey' => @cle, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
      entetes['Authorization'] = "Bearer #{jeton}" if jeton
      @transport.post("#{@url}#{chemin}", entetes, JSON.generate(corps))
    rescue Failure
      raise
    rescue StandardError => error
      raise Failure, refus("connexion impossible (réseau : #{error.class})")
    end

    def lire_role(jeton)
      statut, corps, entetes = appeler('/rest/v1/rpc/fn_get_my_role', {}, jeton: jeton)
      role = statut == 200 ? CompteDemo.extraire_role(corps) : nil
      return role if role
      raise Failure, refus("connexion OK, rôle illisible (HTTP #{statut} ; #{CompteDemo.diagnostic_role(corps, entetes)})")
    end

    def deconnecter(jeton)
      statut, = appeler('/auth/v1/logout?scope=local', {}, jeton: jeton)
      (200..299).cover?(statut) ? :ok : "HTTP #{statut}"
    rescue Failure => error
      error.message[/réseau : [A-Za-z0-9:_]+/] || 'réseau'
    end
  end
end
