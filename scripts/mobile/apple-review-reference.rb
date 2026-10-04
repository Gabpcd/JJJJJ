#!/usr/bin/env ruby
# GET-only canonical Apple review metadata. No account/notes plaintext is exported.
require_relative 'store-status'
require 'digest'
require 'open3'
require 'tmpdir'
require 'openssl'

module AppleReviewReference
  HOST = 'api.appstoreconnect.apple.com'.freeze
  FIELDS = 'demoAccountName,demoAccountRequired,notes'.freeze
  CODES = %w[recipient_unconfigured recipient_invalid encryption_failed endpoint_refused
             read_failed http_refused response_invalid pagination_refused pagination_loop
             pagination_limit duplicate_resource resource_limit inventory_changed budget_exceeded
             notes_review_required attachments_review_required opaque_account_reference
             required_account_missing reference_limit auth_unavailable output_failed source_refused].freeze
  class Failure < StandardError
    attr_reader :code
    def initialize(code)
      @code = CODES.include?(code) ? code : 'read_failed'
      super(@code)
    end
  end
  def self.fail!(code); raise Failure, code; end
  def self.id(value)
    fail!('response_invalid') unless value.is_a?(String) && value.match?(/\A[A-Za-z0-9-]{1,100}\z/)
    value
  end
  def self.query(value)
    pairs = URI.decode_www_form(value.to_s)
    fail!('pagination_refused') unless pairs.map(&:first).uniq.length == pairs.length
    pairs.to_h
  rescue ArgumentError
    fail!('pagination_refused')
  end
  def self.url(path, params)
    "https://#{HOST}#{path}?#{URI.encode_www_form(params)}"
  end
  def self.checked_url(value, path, params, cursor: false)
    spec = case path
    when '/v1/apps'
      { 'filter[bundleId]' => 'app.jolene', 'fields[apps]' => 'bundleId', 'limit' => '2' }
    when %r{\A/v1/apps/[A-Za-z0-9-]{1,100}/appStoreVersions\z}
      { 'fields[appStoreVersions]' => 'platform,versionString', 'limit' => '200' }
    when %r{\A/v1/appStoreVersions/[A-Za-z0-9-]{1,100}/appStoreReviewDetail\z}
      { 'fields[appStoreReviewDetails]' => FIELDS }
    when %r{\A/v1/apps/[A-Za-z0-9-]{1,100}/betaAppReviewDetail\z}
      { 'fields[betaAppReviewDetails]' => FIELDS }
    when %r{\A/v1/appStoreReviewDetails/[A-Za-z0-9-]{1,100}/appStoreReviewAttachments\z}
      { 'fields[appStoreReviewAttachments]' => 'fileSize', 'limit' => '200' }
    end
    fail!('endpoint_refused') unless spec && params == spec
    u = URI(value)
    fail!('endpoint_refused') unless u.scheme == 'https' && u.host == HOST && u.port == 443 &&
      !u.userinfo && !u.fragment && u.path == path
    q = query(u.query)
    token = q.delete('cursor') if cursor
    fail!('pagination_refused') unless q == params
    fail!('pagination_refused') if token && (!token.match?(/\A[\x21-\x7e]{1,2048}\z/))
    url(path, token ? params.merge('cursor' => token) : params)
  rescue URI::InvalidURIError, TypeError
    fail!('endpoint_refused')
  end

  class Reader
    def initialize(token, transport: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @token, @transport, @clock, @requests = token, transport, clock, 0
      @started = @clock.call
    end
    def get(url, path, params, cursor: false)
      canonical = AppleReviewReference.checked_url(url, path, params, cursor: cursor)
      AppleReviewReference.fail!('budget_exceeded') if (@requests += 1) > 250 || @clock.call - @started > 300
      uri = URI(canonical)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@token}"
      request['Accept'] = 'application/json'
      if @transport
        response = @transport.call(uri, request)
        code, body = response.code, response.body
      else
        body = +''
        # No redirects, proxy environment, retry, or provider-error body output.
        http = Net::HTTP.new(uri.host, 443, nil)
        http.use_ssl = true; http.open_timeout = 10; http.read_timeout = 20; http.max_retries = 0
        http.start do |connection|
          connection.request(request) do |response|
            code = response.code
            AppleReviewReference.fail!('http_refused') unless code == '200'
            response.read_body do |chunk|
              body << chunk
              AppleReviewReference.fail!('response_invalid') if body.bytesize > 1_000_000
            end
          end
        end
      end
      AppleReviewReference.fail!('http_refused') unless code == '200'
      AppleReviewReference.fail!('response_invalid') unless body.is_a?(String) && body.bytesize <= 1_000_000
      parsed = JSON.parse(body)
      AppleReviewReference.fail!('response_invalid') unless parsed.is_a?(Hash)
      parsed
    rescue Failure
      raise
    rescue StandardError
      AppleReviewReference.fail!('read_failed')
    end
  end

  def self.rows(reader, path, params, type)
    next_url = url(path, params); seen_pages = {}; seen_ids = {}; result = []; total = nil
    20.times do
      next_url = checked_url(next_url, path, params, cursor: true)
      fail!('pagination_loop') if seen_pages[next_url]
      seen_pages[next_url] = true
      response = reader.get(next_url, path, params, cursor: true)
      page = response['data']; links = response['links']
      fail!('response_invalid') unless page.is_a?(Array) && links.is_a?(Hash)
      if response.key?('meta')
        meta = response['meta']
        fail!('response_invalid') unless meta.is_a?(Hash)
        if meta.key?('paging')
          paging = meta['paging']
          fail!('response_invalid') unless paging.is_a?(Hash)
          if paging.key?('total')
            declared = paging['total']
            fail!('response_invalid') unless declared.is_a?(Integer) && declared >= 0 && (total.nil? || total == declared)
            total = declared
          end
        end
      end
      page.each do |row|
        fail!('response_invalid') unless row.is_a?(Hash) && row['type'] == type
        identifier = id(row['id'])
        fail!('duplicate_resource') if seen_ids[identifier]
        seen_ids[identifier] = true; result << row
        fail!('resource_limit') if result.length > 2000
      end
      next_url = links['next']
      if next_url.nil?
        fail!('response_invalid') if total && total != result.length
        return result
      end
      fail!('pagination_refused') unless next_url.is_a?(String)
    end
    fail!('pagination_limit')
  end
  def self.attributes(row, keys)
    attrs = row['attributes']
    # A provider ignoring sparse fields must not cause password/contact export.
    fail!('response_invalid') unless attrs.is_a?(Hash) && attrs.keys.sort == keys.sort
    attrs
  end
  def self.versions(reader, app)
    rows(reader, "/v1/apps/#{app}/appStoreVersions",
      { 'fields[appStoreVersions]' => 'platform,versionString', 'limit' => '200' }, 'appStoreVersions').map do |row|
      a = attributes(row, %w[platform versionString])
      fail!('response_invalid') unless a.values.all? { |v| v.is_a?(String) && v.bytesize.between?(1,128) }
      { 'id' => row['id'], 'platform' => a['platform'], 'version' => a['versionString'] }
    end.sort_by { |row| row['id'] }
  end
  def self.reference(value)
    return nil if value.nil? || value.empty?
    return nil unless value.bytesize <= 254 && (value.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i) ||
      (value.match?(URI::MailTo::EMAIL_REGEXP) && value.split('@').last.include?('.')))
    value.downcase
  end
  def self.detail(reader, path, type, scope)
    params = { "fields[#{type}]" => FIELDS }
    data = reader.get(url(path, params), path, params)['data']
    fail!('response_invalid') unless data.is_a?(Hash) && data['type'] == type
    identifier = id(data['id']); a = attributes(data, FIELDS.split(','))
    fail!('response_invalid') unless [true, false].include?(a['demoAccountRequired']) &&
      [a['demoAccountName'], a['notes']].all? { |v| v.nil? || (v.is_a?(String) && v.bytesize <= 20_000) }
    attachments = if type == 'appStoreReviewDetails'
      rows(reader, "/v1/appStoreReviewDetails/#{identifier}/appStoreReviewAttachments",
        { 'fields[appStoreReviewAttachments]' => 'fileSize', 'limit' => '200' }, 'appStoreReviewAttachments').map do |row|
        size = attributes(row, ['fileSize'])['fileSize']
        fail!('response_invalid') unless size.is_a?(Integer) && size >= 0
        { 'id' => row['id'], 'bytes' => size }
      end
    else
      [] # BetaAppReviewDetail has no review-attachment relationship in the documented schema.
    end
    { 'scope' => scope, 'id' => identifier, 'demoAccountName' => a['demoAccountName'],
      'demoAccountRequired' => a['demoAccountRequired'], 'notes' => a['notes'], 'attachments' => attachments }
  end
  def self.collect(reader, checked_at: Time.now.utc.iso8601)
    apps = rows(reader, '/v1/apps', { 'filter[bundleId]' => 'app.jolene', 'fields[apps]' => 'bundleId', 'limit' => '2' }, 'apps')
    fail!('response_invalid') unless apps.length == 1 && attributes(apps.first, ['bundleId'])['bundleId'] == 'app.jolene'
    app = id(apps.first['id']); listing = versions(reader, app)
    fail!('response_invalid') if listing.empty?
    details = listing.map do |v|
      detail(reader, "/v1/appStoreVersions/#{v['id']}/appStoreReviewDetail", 'appStoreReviewDetails', v)
    end
    details << detail(reader, "/v1/apps/#{app}/betaAppReviewDetail", 'betaAppReviewDetails', { 'testFlight' => true })
    # Catch version additions/removals during this bounded, non-transactional read.
    fail!('inventory_changed') unless versions(reader, app) == listing
    refs = []; reasons = []
    details.each do |d|
      name = d['demoAccountName']; ref = reference(name)
      refs << ref if ref
      reasons << 'opaque_account_reference' if name && !name.empty? && !ref
      reasons << 'required_account_missing' if d['demoAccountRequired'] && !ref
      reasons << 'notes_review_required' if d['notes'] && !d['notes'].strip.empty?
      reasons << 'attachments_review_required' unless d['attachments'].empty?
    end
    refs = refs.uniq.sort
    fail!('reference_limit') if refs.length > 100
    private_inventory = { 'schema' => 1, 'source' => 'apple-canonical-review-reference', 'application' => 'app.jolene',
      'checkedAt' => checked_at, 'appleComplete' => reasons.empty?, 'references' => refs, 'details' => details,
      'reasons' => reasons.uniq.sort, 'confinementReady' => false }
    public_report = { 'schema' => 1, 'source' => 'apple-canonical-review-reference', 'application' => 'app.jolene',
      'checkedAt' => checked_at, 'status' => reasons.empty? ? 'apple_complete' : 'review_required',
      'appleComplete' => reasons.empty?, 'confinementReady' => false, 'googleChecked' => false,
      'versions' => listing.length, 'testFlightDetails' => 1, 'references' => refs.length,
      'notesNonEmpty' => details.count { |d| d['notes'] && !d['notes'].strip.empty? },
      'attachments' => details.sum { |d| d['attachments'].length }, 'reasons' => reasons.uniq.sort }
    [private_inventory, public_report]
  end

  # Standard authenticated CMS envelope. Only the reviewed public certificate is on CI.
  class Envelope
    def initialize(config, home, binary: '/usr/bin/openssl')
      AppleReviewReference.fail!('recipient_unconfigured') unless config.is_a?(Hash) && config['schema'] == 1 &&
        %w[certificateDerSha256 certificatePem].all? { |k| config[k].is_a?(String) }
      @home, @binary = home, binary
      AppleReviewReference.fail!('recipient_invalid') unless ['/usr/bin/openssl', '/opt/homebrew/bin/openssl'].include?(@binary)
      pem = config['certificatePem']
      AppleReviewReference.fail!('recipient_invalid') unless pem.bytesize <= 32_768 &&
        pem.match?(/\A-----BEGIN CERTIFICATE-----\n[A-Za-z0-9+\/=\n]+-----END CERTIFICATE-----\n?\z/)
      certificate = OpenSSL::X509::Certificate.new(pem)
      AppleReviewReference.fail!('recipient_invalid') unless config['certificateDerSha256'].match?(/\A[a-f0-9]{64}\z/) &&
        Digest::SHA256.hexdigest(certificate.to_der) == config['certificateDerSha256'] &&
        certificate.public_key.is_a?(OpenSSL::PKey::RSA) && certificate.public_key.n.num_bits >= 3072 &&
        certificate.not_before <= Time.now && certificate.not_after > Time.now + 1200
      AppleReviewReference.fail!('encryption_failed') unless command(['version'], '').start_with?('OpenSSL 3.')
      @certificate_path = File.join(@home, 'recipient.pem')
      File.write(@certificate_path, pem, mode: 'wx', perm: 0o600)
    rescue Failure
      raise
    rescue StandardError
      AppleReviewReference.fail!('recipient_invalid')
    end
    def command(args, input)
      # No ASC variables, provider configuration, external engines or logs are inherited.
      output, _error, status = Open3.capture3({ 'PATH' => '/usr/bin:/bin', 'HOME' => @home,
        'OPENSSL_CONF' => '/dev/null' }, @binary, *args, stdin_data: input, binmode: true, unsetenv_others: true)
      AppleReviewReference.fail!('encryption_failed') unless status.success?
      output
    rescue Failure
      raise
    rescue StandardError
      AppleReviewReference.fail!('encryption_failed')
    end
    def encrypt(value)
      plaintext = JSON.generate(value)
      AppleReviewReference.fail!('resource_limit') if plaintext.bytesize > 4_000_000
      encrypted = command(['cms', '-encrypt', '-binary', '-outform', 'DER', '-aes-256-gcm',
        '-recip', @certificate_path, '-keyopt', 'rsa_padding_mode:oaep',
        '-keyopt', 'rsa_oaep_md:sha256', '-keyopt', 'rsa_mgf1_md:sha256'], plaintext)
      AppleReviewReference.fail!('encryption_failed') unless encrypted.bytesize.between?(100, 8_000_000)
      structure = OpenSSL::ASN1.decode(encrypted)
      # AuthEnvelopedData, rather than an unauthenticated CBC envelope or plaintext fallback.
      AppleReviewReference.fail!('encryption_failed') unless structure.is_a?(OpenSSL::ASN1::Sequence) &&
        structure.value.first.is_a?(OpenSSL::ASN1::ObjectId) && structure.value.first.oid == '1.2.840.113549.1.9.16.1.23'
      encrypted
    rescue Failure
      raise
    rescue StandardError
      AppleReviewReference.fail!('encryption_failed')
    end
  end
  def self.validate_source(env, head, origin)
    fail!('source_refused') unless env['GITHUB_ACTIONS'] == 'true' && env['GITHUB_REPOSITORY'] == 'Gabpcd/JJJJJ' &&
      env['GITHUB_REF'] == 'refs/heads/main' && env['GITHUB_EVENT_NAME'] == 'workflow_dispatch' &&
      head.is_a?(String) && head.match?(/\A[a-f0-9]{40}\z/) && head == origin && head == env['GITHUB_SHA']
    head
  end
  def self.trusted_main
    root = File.expand_path('../..', __dir__)
    revisions = %w[HEAD refs/remotes/origin/main].map do |ref|
      result, _error, status = Open3.capture3({ 'PATH' => '/usr/bin:/bin', 'GIT_NO_LAZY_FETCH' => '1' },
        '/usr/bin/git', 'rev-parse', '--verify', ref, chdir: root, unsetenv_others: true)
      fail!('source_refused') unless status.success?
      result.strip
    end
    validate_source(ENV, *revisions)
  rescue Failure
    raise
  rescue StandardError
    fail!('source_refused')
  end
  def self.run(directory, config:, token_factory: -> { StoreStatus.apple_token(ENV) }, transport: nil,
    envelope_factory: nil, source_factory: -> { trusted_main })
    File.umask(0o077)
    fail!('output_failed') unless directory.is_a?(String) && File.absolute_path(directory) == directory && !File.exist?(directory)
    Dir.mkdir(directory, 0o700)
    public_report = nil; encrypted = nil
    begin
      Dir.mktmpdir('apple-review-private-') do |private_home|
        envelope = envelope_factory ? envelope_factory.call(config, private_home) : Envelope.new(config, private_home)
        source_sha = source_factory.call
        begin
          token = token_factory.call
        rescue StandardError
          fail!('auth_unavailable')
        end
        private_inventory, public_report = collect(Reader.new(token, transport: transport))
        private_inventory['sourceSha'] = source_sha
        public_report['sourceSha'] = source_sha
        encrypted = envelope.encrypt(private_inventory)
        public_report['ciphertextSha256'] = Digest::SHA256.hexdigest(encrypted)
      end
    rescue Failure => error
      public_report = { 'schema' => 1, 'status' => 'unavailable', 'appleComplete' => false,
        'confinementReady' => false, 'reasons' => [error.code] }
    rescue StandardError
      public_report = { 'schema' => 1, 'status' => 'unavailable', 'appleComplete' => false,
        'confinementReady' => false, 'reasons' => ['read_failed'] }
    end
    File.write(File.join(directory, 'apple-review-reference.cms'), encrypted, mode: 'wx', perm: 0o600) if encrypted
    File.write(File.join(directory, 'apple-review-public.json'), JSON.pretty_generate(public_report) + "\n", mode: 'wx', perm: 0o600)
    public_report['appleComplete'] == true ? 0 : 1
  end
end

if $PROGRAM_NAME == __FILE__
  diagnostic = STDERR.dup
  STDOUT.reopen(File::NULL, 'w'); STDERR.reopen(File::NULL, 'w')
  begin
    raise AppleReviewReference::Failure, 'output_failed' unless ARGV.length == 1
    config = JSON.parse(File.read(File.join(__dir__, 'apple-review-recipient.json')))
    exit AppleReviewReference.run(ARGV[0], config: config)
  rescue StandardError
    diagnostic.puts 'Apple canonical reference inventory unavailable (closed diagnostic).'
    exit 1
  end
end
