#!/usr/bin/env ruby
# Read-only store diagnostics. No edit transaction, upload or release action.
require 'json'
require 'base64'
require 'net/http'
require 'uri'
require 'time'
require 'fileutils'
require 'stringio'

module StoreStatus
  APPLE = 'https://api.appstoreconnect.apple.com'.freeze
  GOOGLE = 'https://androidpublisher.googleapis.com'.freeze
  PACKAGE = 'app.jolene'.freeze
  APPLE_STATES = %w[ACCEPTED DEVELOPER_REMOVED_FROM_SALE DEVELOPER_REJECTED IN_REVIEW INVALID_BINARY METADATA_REJECTED PENDING_APPLE_RELEASE PENDING_CONTRACT PENDING_DEVELOPER_RELEASE PREPARE_FOR_SUBMISSION PREORDER_READY_FOR_SALE PROCESSING_FOR_APP_STORE READY_FOR_REVIEW READY_FOR_SALE READY_FOR_DISTRIBUTION REJECTED REMOVED_FROM_SALE WAITING_FOR_EXPORT_COMPLIANCE WAITING_FOR_REVIEW REPLACED_WITH_NEW_VERSION NOT_APPLICABLE].freeze
  GOOGLE_STATES = %w[RELEASE_LIFECYCLE_STATE_UNSPECIFIED RELEASE_LIFECYCLE_STATE_DRAFT RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW RELEASE_LIFECYCLE_STATE_IN_REVIEW RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED RELEASE_LIFECYCLE_STATE_NOT_APPROVED RELEASE_LIFECYCLE_STATE_PUBLISHED].freeze
  class Failure < StandardError
    attr_reader :code
    def initialize(code)
      @code = code
      super(code)
    end
  end

  def self.version(value)
    value.is_a?(String) && value.match?(/\A\d{1,8}(?:\.\d{1,8}){0,3}\z/) ? value : nil
  end

  def self.number(value)
    text = value.to_s
    text.match?(/\A\d{1,16}\z/) ? text : nil
  end

  def self.timestamp(value)
    return nil unless value.is_a?(String) && value.match?(/\A\d{4}-\d\d-\d\dT/)
    Time.iso8601(value).utc.iso8601
  rescue ArgumentError
    nil
  end

  def self.enum(value, allowed)
    allowed.include?(value) ? value : 'UNKNOWN'
  end

  # Hard allowlist also applies to Apple's pagination links. Never follow redirects.
  def self.allowed_get?(uri)
    return false unless uri.scheme == 'https' && uri.port == 443 && uri.userinfo.nil? && uri.fragment.nil?
    if uri.host == 'api.appstoreconnect.apple.com'
      uri.path == '/v1/apps' || uri.path == '/v1/builds' || uri.path.match?(%r{\A/v1/apps/\d+/appStoreVersions\z})
    elsif uri.host == 'androidpublisher.googleapis.com'
      uri.path.match?(%r{\A/androidpublisher/v3/applications/app\.jolene/tracks/(production|beta|alpha|internal)/releases\z})
    else
      false
    end
  end

  class Reader
    def initialize(token, transport: nil)
      @token = token
      @transport = transport
    end

    def get(url)
      uri = URI(url)
      raise Failure, 'endpoint_refused' unless StoreStatus.allowed_get?(uri)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@token}"
      request['Accept'] = 'application/json'
      response = if @transport
        @transport.call(uri, request)
      else
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) { |http| http.request(request) }
      end
      code = response.code.to_i
      raise Failure, "http_#{code}" unless (200..299).cover?(code)
      raise Failure, 'response_too_large' if response.body.bytesize > 4_000_000
      result = JSON.parse(response.body)
      raise Failure, 'unexpected_response' unless result.is_a?(Hash)
      result
    rescue Failure
      raise
    rescue StandardError
      # Exceptions can contain headers, URLs, tokens or provider response bodies.
      raise Failure, 'read_failed'
    end
  end

  def self.collection(reader, url)
    rows = []; included = []; visited = []
    5.times do
      raise Failure, 'pagination_loop' if visited.include?(url)
      visited << url
      response = reader.get(url)
      data = response['data']
      extras = response.fetch('included', [])
      raise Failure, 'unexpected_response' unless data.is_a?(Array) && extras.is_a?(Array) && (data + extras).all? { |row| row.is_a?(Hash) }
      rows.concat(data); included.concat(extras)
      next_url = response.dig('links', 'next')
      return [rows, included, false] if next_url.nil?
      raise Failure, 'unexpected_response' unless next_url.is_a?(String)
      candidate = URI(next_url)
      original = URI(url)
      raise Failure, 'pagination_refused' unless candidate.host == original.host && candidate.path == original.path
      url = next_url
    end
    [rows, included, true]
  end

  def self.apple(reader)
    apps = reader.get("#{APPLE}/v1/apps?#{URI.encode_www_form('filter[bundleId]' => PACKAGE, 'limit' => '2')}")['data']
    raise Failure, 'app_not_found_or_ambiguous' unless apps.is_a?(Array) && apps.length == 1 && apps[0].is_a?(Hash)
    app = apps[0]
    raise Failure, 'unexpected_app' unless app.dig('attributes', 'bundleId') == PACKAGE && number(app['id'])
    query = URI.encode_www_form('filter[platform]' => 'IOS', 'include' => 'build,appStoreVersionPhasedRelease', 'limit' => '200')
    versions, extra, versions_limited = collection(reader, "#{APPLE}/v1/apps/#{app['id']}/appStoreVersions?#{query}")
    query = URI.encode_www_form('filter[app]' => app['id'], 'sort' => '-uploadedDate', 'include' => 'preReleaseVersion', 'limit' => '50')
    builds, build_extra, builds_limited = collection(reader, "#{APPLE}/v1/builds?#{query}")
    included = (extra + builds + build_extra).to_h { |row| [[row['type'], row['id']], row] }
    version_rows = versions.map do |row|
      attrs = row.fetch('attributes', {})
      build_id = row.dig('relationships', 'build', 'data', 'id')
      build = included.fetch(['builds', build_id], {}).fetch('attributes', {})
      phased_id = row.dig('relationships', 'appStoreVersionPhasedRelease', 'data', 'id')
      phased = included.fetch(['appStoreVersionPhasedReleases', phased_id], {}).fetch('attributes', {})
      {
        'version' => version(attrs['versionString']), 'build' => number(build['version']),
        'state' => enum(attrs['appVersionState'] || attrs['appStoreState'], APPLE_STATES),
        'releaseType' => enum(attrs['releaseType'], %w[MANUAL AFTER_APPROVAL SCHEDULED]),
        'phasedReleaseState' => phased.empty? ? nil : enum(phased['phasedReleaseState'], %w[INACTIVE ACTIVE PAUSED COMPLETE]),
        'createdAt' => timestamp(attrs['createdDate']), 'uploadedAt' => timestamp(build['uploadedDate'])
      }
    end
    build_rows = builds.map do |row|
      attrs = row.fetch('attributes', {})
      pre_id = row.dig('relationships', 'preReleaseVersion', 'data', 'id')
      pre = included.fetch(['preReleaseVersions', pre_id], {}).fetch('attributes', {})
      { 'version' => version(pre['version']), 'build' => number(attrs['version']),
        'processingState' => enum(attrs['processingState'], %w[PROCESSING FAILED INVALID VALID]),
        'uploadedAt' => timestamp(attrs['uploadedDate']), 'expired' => [true, false].include?(attrs['expired']) ? attrs['expired'] : nil }
    end
    unknown = version_rows.any? do |row|
      row['version'].nil? || %w[state releaseType phasedReleaseState].any? { |field| row[field] == 'UNKNOWN' }
    end || build_rows.any? { |row| row['build'].nil? || row['processingState'] == 'UNKNOWN' }
    { 'status' => unknown || versions_limited || builds_limited ? 'partial' : 'ok', 'versions' => version_rows, 'builds' => build_rows,
      'truncated' => versions_limited || builds_limited }
  end

  def self.android(reader)
    response = reader.get("#{GOOGLE}/androidpublisher/v3/applications/#{PACKAGE}/tracks/production/releases")
    releases = response.fetch('releases', [])
    raise Failure, 'unexpected_response' unless releases.is_a?(Array) && releases.all? { |row| row.is_a?(Hash) }
    # An empty protobuf JSON object is a valid empty releases list, never evidence of publication.
    raise Failure, 'unexpected_response' unless response.keys.all? { |key| key == 'releases' }
    rows = releases.map do |row|
      artifacts = row.fetch('activeArtifacts', [])
      raise Failure, 'unexpected_response' unless artifacts.is_a?(Array) && artifacts.all? { |artifact| artifact.is_a?(Hash) }
      raise Failure, 'unexpected_track' unless row['track'] == 'production'
      { 'releaseName' => version(row['releaseName']), 'versionCodes' => artifacts.map { |artifact| number(artifact['versionCode']) },
        'state' => enum(row['releaseLifecycleState'], GOOGLE_STATES) }
    end
    { 'status' => rows.any? { |row| row['state'].end_with?('UNSPECIFIED') || row['state'] == 'UNKNOWN' || row['versionCodes'].any?(&:nil?) } ? 'partial' : 'ok',
      'track' => 'production', 'releases' => rows,
      'distributionNote' => 'PUBLISHED includes full, partial and resumable halted rollouts; this endpoint does not distinguish them.',
      'historyNote' => 'API excludes obsolete releases and returns at most 20 releases. releaseName is not a guaranteed marketing version.' }
  end

  def self.apple_token(env)
    require 'spaceship'
    Spaceship::ConnectAPI::Token.create(key_id: env.fetch('ASC_KEY_ID'), issuer_id: env.fetch('ASC_ISSUER_ID'),
      key: env.fetch('ASC_PRIVATE_KEY_BASE64'), is_key_content_base64: true, duration: 500).text
  rescue StandardError
    raise Failure, 'apple_auth_unavailable'
  end

  def self.google_token(env)
    require 'googleauth'
    json = Base64.strict_decode64(env.fetch('GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64'))
    credentials = Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: StringIO.new(json),
      scope: 'https://www.googleapis.com/auth/androidpublisher',
      token_credential_uri: 'https://oauth2.googleapis.com/token', audience: 'https://oauth2.googleapis.com/token')
    # Only permitted POST: OAuth token exchange. No edit transaction is created.
    credentials.fetch_access_token!.fetch('access_token')
  rescue StandardError
    raise Failure, 'google_auth_unavailable'
  end

  def self.result
    report = { 'schemaVersion' => 1, 'observedAt' => Time.now.utc.iso8601, 'application' => PACKAGE }
    %w[ios android].each do |platform|
      begin
        token = platform == 'ios' ? apple_token(ENV) : google_token(ENV)
        report[platform] = platform == 'ios' ? apple(Reader.new(token)) : android(Reader.new(token))
      rescue Failure => error
        report[platform] = { 'status' => 'unavailable', 'reason' => error.code }
      rescue StandardError
        report[platform] = { 'status' => 'unavailable', 'reason' => 'unexpected_response' }
      end
    end
    report
  end

  def self.markdown(report)
    lines = ['## Statut des stores — lecture seule', '', "Observation UTC : #{report['observedAt']}", '',
      '| Plateforme | Version / releaseName | Build / versionCode | État API |', '| --- | --- | --- | --- |']
    report.fetch('ios').fetch('versions', []).each { |r| lines << "| iOS | #{r['version'] || 'inconnue'} | #{r['build'] || 'aucun'} | #{r['state']} |" }
    report.fetch('android').fetch('releases', []).each { |r| lines << "| Android production | #{r['releaseName'] || 'non numérique'} | #{r['versionCodes'].map { |v| v || 'inconnu' }.join(', ')} | #{r['state']} |" }
    %w[ios android].each { |p| lines << "\n#{p} : #{report[p]['status']}#{report[p]['reason'] ? " (#{report[p]['reason']})" : ''}." }
    lines << "\nVoir le JSON pour les builds en traitement, la publication progressive iOS et les limites Android. Une liste vide ne confirme aucune publication."
    lines.join("\n") + "\n"
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    directory = ARGV.fetch(0)
    report = StoreStatus.result
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'store-status.json'), JSON.pretty_generate(report) + "\n", mode: 'w', perm: 0o600)
    File.write(File.join(directory, 'store-status.md'), StoreStatus.markdown(report), mode: 'w', perm: 0o600)
    puts StoreStatus.markdown(report)
    exit(report.values.grep(Hash).any? { |value| value['status'] != 'ok' } ? 1 : 0)
  rescue StandardError
    warn 'Store status report could not be written. No provider details or credentials were logged.'
    exit 1
  end
end
