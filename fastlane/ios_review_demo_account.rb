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
# connecte jamais quand la version est déjà soumise ou en revue (ReviewNotes::SOUMISES), voir APP_STORE.md.
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
    class TransportHttps
      def post(url, entetes, corps)
        uri = URI(url)
        raise Failure, 'Transport refusé : HTTPS seulement' unless uri.scheme == 'https'
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20, write_timeout: 20) do |http|
          requete = Net::HTTP::Post.new(uri)
          entetes.each { |nom, valeur| requete[nom] = valeur }
          requete.body = corps
          reponse = http.request(requete)
          [reponse.code.to_i, reponse.body.to_s]
        end
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
      statut, corps = appeler('/rest/v1/rpc/fn_get_my_role', {}, jeton: jeton)
      raise Failure, refus("connexion OK, rôle illisible (HTTP #{statut})") unless statut == 200
      role = CompteDemo.lire_json(corps)['role']
      raise Failure, refus('connexion OK, rôle illisible (HTTP 200)') unless role.is_a?(String)
      role
    end

    def deconnecter(jeton)
      statut, = appeler('/auth/v1/logout?scope=local', {}, jeton: jeton)
      (200..299).cover?(statut) ? :ok : "HTTP #{statut}"
    rescue Failure => error
      error.message[/réseau : [A-Za-z0-9:_]+/] || 'réseau'
    end
  end
end
