#!/usr/bin/env ruby
# No credentials or network; stdlib-only harness, compatible with bundle exec.
require_relative 'store-status'

module StoreStatusTest
  SECRET = 'SECRET_FIXTURE_NEVER_REPORT_BEARER_PRIVATE_KEY'.freeze
  Response = Struct.new(:code, :body)
  def self.assert(condition, message)
    raise "Assertion failed: #{message}" unless condition
  end
  def self.rejects(code)
    yield
    raise 'Expected a controlled failure'
  rescue StoreStatus::Failure => error
    assert(error.code == code, "expected #{code}, got #{error.code}")
    assert(!error.message.include?(SECRET), 'failure message must be sanitized')
  end
  def self.reader(responses, calls = [])
    StoreStatus::Reader.new(SECRET, transport: lambda { |uri, request|
      calls << [uri, request]
      value = responses.fetch(uri.path) { raise 'Unexpected fixture endpoint' }
      Response.new('200', JSON.generate(value))
    })
  end

  def self.run
    cases = {
      'Apple maps review, linked build and progressive rollout without metadata or secrets' => lambda {
        responses = {
          '/v1/apps' => { 'data' => [{ 'id' => '1234567890', 'attributes' => { 'bundleId' => 'app.jolene', 'private_key' => SECRET } }] },
          '/v1/apps/1234567890/appStoreVersions' => {
            'data' => [{ 'id' => 'v1', 'type' => 'appStoreVersions', 'attributes' => { 'versionString' => '1.0.6', 'appStoreState' => 'IN_REVIEW', 'releaseType' => 'AFTER_APPROVAL', 'createdDate' => '2026-09-28T13:00:00Z', 'reviewNotes' => SECRET },
              'relationships' => { 'build' => { 'data' => { 'id' => 'b23' } }, 'appStoreVersionPhasedRelease' => { 'data' => { 'id' => 'ph1' } } } }],
            'included' => [{ 'type' => 'appStoreVersionPhasedReleases', 'id' => 'ph1', 'attributes' => { 'phasedReleaseState' => 'ACTIVE', 'secret' => SECRET } }]
          },
          '/v1/builds' => { 'data' => [{ 'id' => 'b23', 'type' => 'builds', 'attributes' => { 'version' => '23', 'processingState' => 'VALID', 'uploadedDate' => '2026-09-28T12:00:00Z', 'expired' => false, 'access_token' => SECRET }, 'relationships' => { 'preReleaseVersion' => { 'data' => { 'id' => 'p1' } } } }],
            'included' => [{ 'id' => 'p1', 'type' => 'preReleaseVersions', 'attributes' => { 'version' => '1.0.6' } }] }
        }
        calls = []; result = StoreStatus.apple(reader(responses, calls))
        assert(result['status'] == 'ok', 'complete Apple read')
        assert(result['versions'][0].slice('version', 'build', 'state', 'phasedReleaseState') == { 'version' => '1.0.6', 'build' => '23', 'state' => 'IN_REVIEW', 'phasedReleaseState' => 'ACTIVE' }, 'linked version/build/state')
        assert(result['builds'][0]['version'] == '1.0.6', 'marketing version from pre-release relation')
        assert(!JSON.generate(result).include?(SECRET), 'drop unapproved Apple fields')
        assert(calls.length == 3 && calls.all? { |_, request| request.method == 'GET' }, 'only three GET requests')
      },
      'Apple unknown release type or phased release state makes the diagnostic partial' => lambda {
        statuses = [['NEW_RELEASE_TYPE', 'ACTIVE'], ['AFTER_APPROVAL', 'NEW_PHASED_STATE'], ['AFTER_APPROVAL', nil]].map do |release_type, phased_state|
          version = { 'type' => 'appStoreVersions', 'id' => 'v1', 'attributes' => { 'versionString' => '1.0.6', 'appStoreState' => 'READY_FOR_SALE', 'releaseType' => release_type } }
          version['relationships'] = { 'appStoreVersionPhasedRelease' => { 'data' => { 'id' => 'ph1' } } } if phased_state
          extras = phased_state ? [{ 'type' => 'appStoreVersionPhasedReleases', 'id' => 'ph1', 'attributes' => { 'phasedReleaseState' => phased_state } }] : []
          result = StoreStatus.apple(reader({
            '/v1/apps' => { 'data' => [{ 'id' => '1234567890', 'attributes' => { 'bundleId' => 'app.jolene' } }] },
            '/v1/apps/1234567890/appStoreVersions' => { 'data' => [version], 'included' => extras },
            '/v1/builds' => { 'data' => [] }
          }))
          assert(result['versions'][0]['releaseType'] == 'UNKNOWN', 'unrecognized release type is sanitized') if release_type == 'NEW_RELEASE_TYPE'
          assert(result['versions'][0]['phasedReleaseState'] == 'UNKNOWN', 'unrecognized rollout state is sanitized') if phased_state == 'NEW_PHASED_STATE'
          assert(result['versions'][0]['phasedReleaseState'].nil?, 'no phased rollout is a valid absence') if phased_state.nil?
          result['status']
        end
        assert(statuses == ['partial', 'partial', 'ok'], "unknown release/rollout must be partial, absent rollout remains valid: #{statuses.inspect}")
      },
      'Google reads production review without edits and filters provider fields' => lambda {
        path = '/androidpublisher/v3/applications/app.jolene/tracks/production/releases'
        calls = []
        result = StoreStatus.android(reader({ path => { 'releases' => [{ 'releaseName' => '1.0.6', 'track' => 'production', 'activeArtifacts' => [{ 'versionCode' => 23, 'access_token' => SECRET }], 'releaseLifecycleState' => 'RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED', 'private_key' => SECRET }] } }, calls))
        assert(result['status'] == 'ok' && result['releases'][0]['versionCodes'] == ['23'], 'Google versionCode')
        assert(result['releases'][0]['state'] == 'RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED', 'approval is not publication')
        assert(calls.length == 1 && calls[0][1].method == 'GET' && !calls[0][0].path.include?('/edits'), 'no edit creation')
        assert(!JSON.generate(result).include?(SECRET), 'drop unapproved Google fields')
      },
      'Unknown statuses stay partial and arbitrary release names are not printed' => lambda {
        path = '/androidpublisher/v3/applications/app.jolene/tracks/production/releases'
        result = StoreStatus.android(reader({ path => { 'releases' => [{ 'releaseName' => SECRET, 'track' => 'production', 'activeArtifacts' => [{ 'versionCode' => SECRET }], 'releaseLifecycleState' => SECRET }] } }))
        assert(result['status'] == 'partial', 'unknown must not appear successful')
        report = { 'observedAt' => '2026-09-28T13:00:00Z', 'ios' => { 'status' => 'unavailable', 'reason' => 'http_403' }, 'android' => result }
        assert(!JSON.generate(report).include?(SECRET) && !StoreStatus.markdown(report).include?(SECRET), 'JSON and Markdown sanitized')
      },
      'A malformed successful HTTP response is not a store status' => lambda {
        path = '/androidpublisher/v3/applications/app.jolene/tracks/production/releases'
        rejects('unexpected_response') { StoreStatus.android(reader({ path => { 'error' => SECRET } })) }
        rejects('unexpected_response') { StoreStatus.android(reader({ path => { 'releases' => SECRET } })) }
        empty = StoreStatus.android(reader({ path => {} }))
        assert(empty['releases'].empty?, 'valid empty response does not invent a published release')
      },
      'HTTP failure body is never surfaced, including auth details' => lambda {
        r = StoreStatus::Reader.new(SECRET, transport: ->(_uri, _request) { Response.new('401', SECRET) })
        rejects('http_401') { r.get('https://api.appstoreconnect.apple.com/v1/apps') }
      },
      'Requests refuse arbitrary hosts, HTTP, credentials, edits and redirects' => lambda {
        attempted = 0
        r = StoreStatus::Reader.new(SECRET, transport: ->(_uri, _request) { attempted += 1; Response.new('302', SECRET) })
        ["https://evil.example/v1/apps", "http://api.appstoreconnect.apple.com/v1/apps", "https://user:pass@api.appstoreconnect.apple.com/v1/apps", "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/app.jolene/edits", "https://api.appstoreconnect.apple.com/v1/appStoreVersionSubmissions"].each { |url| rejects('endpoint_refused') { r.get(url) } }
        assert(attempted.zero?, 'refused before transport')
        rejects('http_302') { r.get('https://api.appstoreconnect.apple.com/v1/apps') }
        assert(attempted == 1, 'redirect never followed')
      },
      'Pagination refuses a different origin and cannot loop silently' => lambda {
        r = reader({ '/v1/builds' => { 'data' => [], 'links' => { 'next' => 'https://evil.example/v1/builds' } } })
        rejects('pagination_refused') { StoreStatus.collection(r, 'https://api.appstoreconnect.apple.com/v1/builds') }
        r = reader({ '/v1/builds' => { 'data' => [], 'links' => { 'next' => 'https://api.appstoreconnect.apple.com/v1/builds' } } })
        rejects('pagination_loop') { StoreStatus.collection(r, 'https://api.appstoreconnect.apple.com/v1/builds') }
      }
    }
    cases.each { |name, test| test.call; puts "PASS: #{name}" }
    puts "#{cases.length} store status checks passed (fixtures only)."
  end
end

StoreStatusTest.run if $PROGRAM_NAME == __FILE__
