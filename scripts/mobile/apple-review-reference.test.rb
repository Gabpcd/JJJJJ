#!/usr/bin/env ruby
# Pure fixtures: no provider, keyring, browser, or OpenSSL process is used here.
require_relative 'apple-review-reference'
require 'securerandom'
require 'stringio'

module AppleReviewReferenceTest
  A = AppleReviewReference
  Response = Struct.new(:code, :body)
  def self.assert(value); raise 'Closed test assertion failed' unless value; end
  def self.rejects(code)
    yield
    raise 'Expected closed refusal'
  rescue A::Failure => error
    assert(error.code == code && error.message == code)
  end
  def self.page(rows, next_url = nil)
    { 'data' => rows, 'links' => { 'next' => next_url } }
  end
  def self.resource(type, id, attributes)
    { 'type' => type, 'id' => id, 'attributes' => attributes }
  end
  def self.fixture
    {
      '/v1/apps' => page([resource('apps', '1234567890', { 'bundleId' => 'app.jolene' })]),
      '/v1/apps/1234567890/appStoreVersions' => page([
        resource('appStoreVersions', 'v-ios', { 'platform' => 'IOS', 'versionString' => '1.0.6' }),
        resource('appStoreVersions', 'v-mac', { 'platform' => 'MAC_OS', 'versionString' => '0.1.0' })
      ]),
      '/v1/appStoreVersions/v-ios/appStoreReviewDetail' => { 'data' => resource('appStoreReviewDetails', 'd-ios', {
        'demoAccountName' => 'owner-a@example.invalid', 'demoAccountRequired' => true, 'notes' => nil }) },
      '/v1/appStoreVersions/v-mac/appStoreReviewDetail' => { 'data' => resource('appStoreReviewDetails', 'd-mac', {
        'demoAccountName' => nil, 'demoAccountRequired' => false, 'notes' => '' }) },
      '/v1/appStoreReviewDetails/d-ios/appStoreReviewAttachments' => page([]),
      '/v1/appStoreReviewDetails/d-mac/appStoreReviewAttachments' => page([]),
      '/v1/apps/1234567890/betaAppReviewDetail' => { 'data' => resource('betaAppReviewDetails', 'd-beta', {
        'demoAccountName' => 'owner-b@example.invalid', 'demoAccountRequired' => true, 'notes' => '' }) }
    }
  end
  def self.transport(fixture, calls = [])
    lambda do |uri, request|
      calls << [uri, request]
      value = fixture.fetch(uri.path)
      value = value.call(uri, request) if value.respond_to?(:call)
      value.is_a?(Response) ? value : Response.new('200', JSON.generate(value))
    end
  end
  def self.collect(fixture = self.fixture, calls = [])
    A.collect(A::Reader.new(SecureRandom.hex(16), transport: transport(fixture, calls)))
  end
  def self.attrs(fixture, suffix = 'v-ios')
    fixture.fetch("/v1/appStoreVersions/#{suffix}/appStoreReviewDetail").fetch('data').fetch('attributes')
  end
  def self.diagnostic_refusal(fixture, endpoint, check, observed, code = 'response_invalid')
    collect(fixture)
    raise 'Expected closed diagnostic refusal'
  rescue A::Failure => error
    assert(error.code == code && error.message == code)
    assert(error.diagnostic == { 'endpoint' => endpoint, 'check' => check, 'observed' => observed })
  end
  def self.diagnostic_fixture
    f = fixture
    f['/v1/appStoreReviewDetails/d-ios/appStoreReviewAttachments']['data'] = [resource('appStoreReviewAttachments', 'file-1', { 'fileSize' => 2 })]
    f
  end
  def self.diagnostic_resource(f, path)
    data = f.fetch(path).fetch('data'); data.is_a?(Array) ? data.first : data
  end
  def self.run
    cases = {
      'all versions and separate TestFlight references; no platform/state filter' => lambda {
        calls = []; private_data, public_data = collect(fixture, calls)
        assert(private_data['references'] == %w[owner-a@example.invalid owner-b@example.invalid])
        assert(public_data['appleComplete'] && !public_data['confinementReady'] && !public_data['googleChecked'])
        assert(calls.all? { |u, r| r.method == 'GET' && !u.query.include?('Password') && !u.query.include?('contact') && !u.query.include?('filter%5Bplatform') })
        assert(public_data['versions'] == 2 && public_data['testFlightDetails'] == 1)
        assert(!JSON.generate(public_data).include?('owner-a'))
      },
      'versions and attachment pagination remain in the exact sparse scope' => lambda {
        f = fixture; vpath = '/v1/apps/1234567890/appStoreVersions'; original = f[vpath]['data']
        vparams = { 'fields[appStoreVersions]' => 'platform,versionString', 'limit' => '200' }
        f[vpath] = ->(u, _) { A.query(u.query)['cursor'] ? page([original[1]]) : page([original[0]], A.url(vpath, vparams.merge('cursor' => 'next-1'))) }
        apath = '/v1/appStoreReviewDetails/d-ios/appStoreReviewAttachments'
        aparams = { 'fields[appStoreReviewAttachments]' => 'fileSize', 'limit' => '200' }
        f[apath] = ->(u, _) { A.query(u.query)['cursor'] ? page([resource('appStoreReviewAttachments', 'file-2', { 'fileSize' => 0 })]) : page([resource('appStoreReviewAttachments', 'file-1', { 'fileSize' => 2 })], A.url(apath, aparams.merge('cursor' => 'next-2'))) }
        _, report = collect(f)
        assert(report['attachments'] == 2 && report['reasons'] == ['attachments_review_required'] && !report['appleComplete'])
      },
      'notes, opaque accounts and missing required names block completeness' => lambda {
        f = fixture; a = attrs(f); a['notes'] = SecureRandom.hex(16); a['demoAccountName'] = 'opaque user'
        _, report = collect(f)
        assert(report['reasons'] == %w[notes_review_required opaque_account_reference required_account_missing])
        assert(!report['appleComplete'])
      },
      'case normalization deduplicates exact references, including non-required stored accounts' => lambda {
        f = fixture; attrs(f)['demoAccountName'] = 'OWNER-B@example.invalid'; attrs(f)['demoAccountRequired'] = false
        private_data, report = collect(f)
        assert(private_data['references'] == ['owner-b@example.invalid'] && report['references'] == 1)
        assert(A.reference('label:owner@example.invalid').nil?)
        assert(A.reference('owner@example.invalid extra').nil?)
      },
      'unexpected password/contact attributes are never projected or accepted' => lambda {
        %w[demoAccountPassword contactEmail].each do |field|
          f = fixture; attrs(f)[field] = SecureRandom.hex(16)
          rejects('response_invalid') { collect(f) }
        end
      },
      'missing review resource, field or TestFlight permissions cannot mean no references' => lambda {
        f = fixture; f['/v1/appStoreVersions/v-ios/appStoreReviewDetail']['data'] = nil
        rejects('response_invalid') { collect(f) }
        f = fixture; attrs(f).delete('notes'); rejects('response_invalid') { collect(f) }
        %w[302 403 404 429 500].each do |code|
          f = fixture; f['/v1/apps/1234567890/betaAppReviewDetail'] = Response.new(code, SecureRandom.hex(16))
          rejects('http_refused') { collect(f) }
        end
      },
      'pagination rejects broadened fields, application, host, duplicate query and loops' => lambda {
        path = '/v1/apps/1234567890/appStoreVersions'
        params = { 'fields[appStoreVersions]' => 'platform,versionString', 'limit' => '200' }
        urls = [A.url(path, params.merge('fields[appStoreVersions]' => 'appStoreReviewDetail', 'cursor' => 'x')),
          A.url(path, params.merge('include' => 'appStoreReviewDetail', 'cursor' => 'x')),
          A.url(path, params.merge('cursor' => 'x')) + '&cursor=y']
        urls.each do |u|
          f = fixture; f[path]['links']['next'] = u
          rejects('pagination_refused') { collect(f) }
        end
        [A.url(path.sub('1234567890','1234567891'), params), A.url(path, params).sub(A::HOST,'example.invalid')].each do |u|
          f = fixture; f[path]['links']['next'] = u
          rejects('endpoint_refused') { collect(f) }
        end
        f = fixture; f[path]['links']['next'] = A.url(path, params)
        rejects('pagination_loop') { collect(f) }
      },
      'pagination cap, duplicate IDs and declared totals are fail closed' => lambda {
        path = '/v1/apps/1234567890/appStoreVersions'; params = { 'fields[appStoreVersions]' => 'platform,versionString', 'limit' => '200' }
        f = fixture; f[path] = ->(u, _) { n = A.query(u.query).fetch('cursor', '0').to_i; page([], A.url(path, params.merge('cursor' => (n+1).to_s))) }
        rejects('pagination_limit') { collect(f) }
        f = fixture; f[path]['data'] << f[path]['data'][0].dup
        rejects('duplicate_resource') { collect(f) }
        f = fixture; f[path]['meta'] = { 'paging' => { 'total' => 3 } }
        rejects('response_invalid') { collect(f) }
      },
      'changed version listing at readback is refused' => lambda {
        f = fixture; path = '/v1/apps/1234567890/appStoreVersions'; first = f[path]; count = 0
        f[path] = ->(_, _) { count += 1; count == 1 ? first : page([]) }
        rejects('inventory_changed') { collect(f) }
      },
      'every present pagination total requires a nonnegative integer, including false and null' => lambda {
        path = '/v1/apps/1234567890/appStoreVersions'
        [false, true, nil, '2', 2.0, -1, [], {}].each do |invalid_total|
          f = fixture; f[path]['meta'] = { 'paging' => { 'total' => invalid_total } }
          rejects('response_invalid') { collect(f) }
        end
        f = fixture; f[path]['meta'] = { 'paging' => { 'total' => 2 } }
        f['/v1/appStoreReviewDetails/d-ios/appStoreReviewAttachments']['meta'] = { 'paging' => { 'total' => 0 } }
        assert(collect(f).last['appleComplete'])
      },
      'malformed nested pagination metadata refuses with a closed code, absence stays optional' => lambda {
        path = '/v1/apps/1234567890/appStoreVersions'
        [false, true, nil, [], 'metadata', 2].each do |invalid_shape|
          f = fixture; f[path]['meta'] = invalid_shape
          rejects('response_invalid') { collect(f) }
          f = fixture; f[path]['meta'] = { 'paging' => invalid_shape }
          rejects('response_invalid') { collect(f) }
        end
        [{}, { 'paging' => {} }].each do |valid_optional_meta|
          f = fixture; f[path]['meta'] = valid_optional_meta
          assert(collect(f).last['appleComplete'])
        end
      },
      'malformed JSON, provider exception, oversized body and runtime budget are closed' => lambda {
        ['{', 'x' * 1_000_001].each do |body|
          f = fixture; f['/v1/apps'] = Response.new('200', body)
          rejects(body.length > 1_000_000 ? 'response_invalid' : 'read_failed') { collect(f) }
        end
        f = fixture; f['/v1/apps'] = ->(_, _) { raise SecureRandom.hex(16) }
        rejects('read_failed') { collect(f) }
        time = 0; reader = A::Reader.new('unused', transport: transport(fixture), clock: -> { time += 301 })
        rejects('budget_exceeded') { A.collect(reader) }
      },
      'trusted main SHA, repository and event are exact before any credential use' => lambda {
        sha = 'a' * 40
        env = { 'GITHUB_ACTIONS' => 'true', 'GITHUB_REPOSITORY' => 'Gabpcd/JJJJJ', 'GITHUB_REF' => 'refs/heads/main',
          'GITHUB_EVENT_NAME' => 'workflow_dispatch', 'GITHUB_SHA' => sha }
        assert(A.validate_source(env, sha, sha) == sha)
        env.keys.each { |key| rejects('source_refused') { A.validate_source(env.merge(key => 'refused'), sha, sha) } }
        rejects('source_refused') { A.validate_source(env, 'b' * 40, sha) }
        rejects('source_refused') { A.validate_source(env, sha, 'b' * 40) }
        rejects('source_refused') { A.validate_source(env, 'invalid', 'invalid') }
      },
      'unconfigured encryption recipient refuses before token or API access' => lambda {
        Dir.mktmpdir do |parent|
          called = false
          status = A.run(File.join(parent, 'output'), config: { 'schema' => 1 }, token_factory: -> { called = true; raise 'forbidden' })
          assert(status == 1 && !called)
          report = JSON.parse(File.read(File.join(parent, 'output/apple-review-public.json')))
          assert(report['reasons'] == ['recipient_unconfigured'] && Dir.children(File.join(parent,'output')) == ['apple-review-public.json'])
        end
      },
      'private runtime canaries never enter public files or stdout, even on encryption failure' => lambda {
        canary = SecureRandom.hex(24); f = fixture; attrs(f)['notes'] = canary
        fake = Object.new
        fake.define_singleton_method(:encrypt) { |value| raise canary unless value['details'].first['notes'] == canary; "-----BEGIN PGP MESSAGE-----\n#{'A' * 100}\n-----END PGP MESSAGE-----\n" }
        Dir.mktmpdir do |parent|
          output = File.join(parent,'output'); captured = StringIO.new; previous = $stdout; $stdout = captured
          begin
            status = A.run(output, config: {}, token_factory: -> { canary }, transport: transport(f), envelope_factory: ->(_, _) { fake }, source_factory: -> { 'a' * 40 })
          ensure
            $stdout = previous
          end
          assert(status == 1 && captured.string.empty?)
          bytes = Dir.children(output).map { |name| File.read(File.join(output,name)) }.join
          assert(!bytes.include?(canary) && !bytes.include?('owner-a'))
          assert((File.stat(output).mode & 0o777) == 0o700 && Dir.children(output).all? { |name| (File.stat(File.join(output,name)).mode & 0o777) == 0o600 })
          fake.define_singleton_method(:encrypt) { |_| raise canary }
          failed = File.join(parent,'failed')
          assert(A.run(failed, config: {}, token_factory: -> { canary }, transport: transport(f), envelope_factory: ->(_, _) { fake }, source_factory: -> { 'a' * 40 }) == 1)
          assert(Dir.children(failed) == ['apple-review-public.json'] && !File.read(File.join(failed,'apple-review-public.json')).include?(canary))
        end
      }
    }
    endpoints = {
      'apps' => '/v1/apps',
      'versions' => '/v1/apps/1234567890/appStoreVersions',
      'review_detail' => '/v1/appStoreVersions/v-ios/appStoreReviewDetail',
      'beta_detail' => '/v1/apps/1234567890/betaAppReviewDetail',
      'attachments' => '/v1/appStoreReviewDetails/d-ios/appStoreReviewAttachments'
    }
    endpoints.each do |endpoint, path|
      { 'missing_keys' => ->(a) { a.delete(a.keys.first) },
        'extra_keys' => ->(a) { a[SecureRandom.hex(16)] = SecureRandom.hex(24) },
        'missing_and_extra_keys' => ->(a) { a.delete(a.keys.first); a[SecureRandom.hex(16)] = SecureRandom.hex(24) }
      }.each do |observation, change|
        cases["diagnostic #{endpoint} attributes #{observation}"] = lambda {
          f = diagnostic_fixture; change.call(diagnostic_resource(f, path)['attributes'])
          diagnostic_refusal(f, endpoint, 'attributes', observation)
        }
      end
      { 'null' => nil, 'array' => [], 'string' => 'synthetic', 'boolean' => false, 'integer' => 1 }.each do |observation, value|
        cases["diagnostic #{endpoint} attributes #{observation}"] = lambda {
          f = diagnostic_fixture; diagnostic_resource(f, path)['attributes'] = value
          diagnostic_refusal(f, endpoint, 'attributes', observation)
        }
      end
      cases["diagnostic #{endpoint} attributes absent"] = lambda {
        f = diagnostic_fixture; diagnostic_resource(f, path).delete('attributes')
        diagnostic_refusal(f, endpoint, 'attributes', 'missing')
      }
      { 'null' => nil, 'integer' => 1, 'invalid_format' => 'not/an/id' }.each do |observation, value|
        cases["diagnostic #{endpoint} id #{observation}"] = lambda {
          f = diagnostic_fixture; diagnostic_resource(f, path)['id'] = value
          diagnostic_refusal(f, endpoint, 'id', observation)
        }
      end
      cases["diagnostic #{endpoint} id absent"] = lambda {
        f = diagnostic_fixture; diagnostic_resource(f, path).delete('id')
        diagnostic_refusal(f, endpoint, 'id', 'missing')
      }
      { 'null' => nil, 'mismatch' => 'unexpected-resource' }.each do |observation, value|
        cases["diagnostic #{endpoint} resource type #{observation}"] = lambda {
          f = diagnostic_fixture; diagnostic_resource(f, path)['type'] = value
          diagnostic_refusal(f, endpoint, 'resource_type', observation)
        }
      end
      cases["diagnostic #{endpoint} data absent"] = lambda {
        f = diagnostic_fixture; f[path].delete('data'); diagnostic_refusal(f, endpoint, 'data', 'missing')
      }
      cases["diagnostic #{endpoint} data nil"] = lambda {
        f = diagnostic_fixture; f[path]['data'] = nil; diagnostic_refusal(f, endpoint, 'data', 'null')
      }
      cases["diagnostic #{endpoint} root wrong type"] = lambda {
        f = diagnostic_fixture; f[path] = []; diagnostic_refusal(f, endpoint, 'root', 'array')
      }
    end
    %w[apps versions attachments].each do |endpoint|
      path = endpoints.fetch(endpoint)
      %w[meta paging total].each do |check|
        { 'null' => nil, 'boolean' => false, 'string' => 'synthetic' }.each do |observation, value|
          cases["diagnostic #{endpoint} pagination #{check} #{observation}"] = lambda {
            f = diagnostic_fixture
            f[path]['meta'] = check == 'meta' ? value : { 'paging' => check == 'paging' ? value : { 'total' => value } }
            diagnostic_refusal(f, endpoint, check, observation)
          }
        end
      end
      cases["diagnostic #{endpoint} negative total"] = lambda {
        f = diagnostic_fixture; f[path]['meta'] = { 'paging' => { 'total' => -1 } }
        diagnostic_refusal(f, endpoint, 'total', 'negative')
      }
      cases["diagnostic #{endpoint} wrong total"] = lambda {
        f = diagnostic_fixture; f[path]['meta'] = { 'paging' => { 'total' => 20 } }
        diagnostic_refusal(f, endpoint, 'pagination_total', 'mismatch')
      }
      cases["diagnostic #{endpoint} next type"] = lambda {
        f = diagnostic_fixture; f[path]['links']['next'] = false
        diagnostic_refusal(f, endpoint, 'next_url', 'boolean', 'pagination_refused')
      }
      cases["diagnostic #{endpoint} missing links"] = lambda {
        f = diagnostic_fixture; f[path].delete('links'); diagnostic_refusal(f, endpoint, 'links', 'missing')
      }
    end
    { 'review_detail' => endpoints['review_detail'], 'beta_detail' => endpoints['beta_detail'] }.each do |endpoint, path|
      { 'demoAccountRequired' => ['demo_account_required', nil, 'null'],
        'demoAccountName' => ['demo_account_name', false, 'boolean'],
        'notes' => ['notes', [], 'array'] }.each do |field, (check, value, observation)|
        cases["diagnostic #{endpoint} field #{check}"] = lambda {
          f = diagnostic_fixture; diagnostic_resource(f, path)['attributes'][field] = value
          diagnostic_refusal(f, endpoint, check, observation)
        }
      end
    end
    cases['diagnostic bundle mismatch separate from nil and wrong cardinality'] = lambda {
      f = diagnostic_fixture; f[endpoints['apps']]['data'].first['attributes']['bundleId'] = 'another.synthetic.app'
      diagnostic_refusal(f, 'apps', 'bundle_id', 'mismatch')
      f = diagnostic_fixture; f[endpoints['apps']]['data'].first['attributes']['bundleId'] = nil
      diagnostic_refusal(f, 'apps', 'bundle_id', 'null')
      f = diagnostic_fixture; f[endpoints['apps']]['data'] = []
      diagnostic_refusal(f, 'apps', 'app_count', 'mismatch')
    }
    cases['diagnostic HTTP body JSON and transport keep original reason classifications'] = lambda {
      [ ['{', 'read_failed', 'json', 'malformed'], ['x' * 1_000_001, 'response_invalid', 'body', 'oversized'],
        [nil, 'response_invalid', 'body', 'null'] ].each do |body, reason, check, observation|
        f = fixture; f[endpoints['apps']] = Response.new('200', body)
        diagnostic_refusal(f, 'apps', check, observation, reason)
      end
      f = fixture; f[endpoints['apps']] = ->(_, _) { raise SecureRandom.hex(16) }
      diagnostic_refusal(f, 'apps', 'transport', 'exception', 'read_failed')
      f = fixture; f[endpoints['apps']] = Response.new('403', SecureRandom.hex(16))
      diagnostic_refusal(f, 'apps', 'http', 'refused', 'http_refused')
    }
    cases['diagnostic actual unavailable receipt is closed at every endpoint and never encrypted'] = lambda {
      endpoints.each do |endpoint, path|
        canary = SecureRandom.hex(24); f = diagnostic_fixture
        diagnostic_resource(f, path)['attributes'][canary] = canary
        fake = Object.new; fake.define_singleton_method(:encrypt) { |_| raise 'Encryption must not run on refused response' }
        captured_out = StringIO.new; captured_err = StringIO.new; previous_out = $stdout; previous_err = $stderr
        Dir.mktmpdir do |parent|
          output = File.join(parent, 'output'); $stdout = captured_out; $stderr = captured_err
          begin
            status = A.run(output, config: {}, token_factory: -> { canary }, transport: transport(f), envelope_factory: ->(_, _) { fake }, source_factory: -> { 'a' * 40 })
          ensure
            $stdout = previous_out; $stderr = previous_err
          end
          assert(status == 1 && Dir.children(output) == ['apple-review-public.json'])
          bytes = File.read(File.join(output, 'apple-review-public.json')); report = JSON.parse(bytes)
          assert(report == { 'schema' => 1, 'status' => 'unavailable', 'appleComplete' => false,
            'confinementReady' => false, 'reasons' => ['response_invalid'],
            'diagnostic' => { 'endpoint' => endpoint, 'check' => 'attributes', 'observed' => 'extra_keys' } })
          assert(captured_out.string.empty? && captured_err.string.empty?)
          assert(!bytes.include?(canary) && !bytes.include?('owner-a') && !bytes.include?('1234567890') && !bytes.include?('file-1'))
        end
      end
    }
    cases['diagnostic allowlists reject every free coordinate and additional property at both boundaries'] = lambda {
      valid = { 'endpoint' => 'apps', 'check' => 'id', 'observed' => 'null' }
      assert(A.closed_diagnostic(valid) == valid)
      invalid = valid.keys.map { |key| valid.merge(key => SecureRandom.hex(16)) } + [valid.merge('extra' => 'value'), {}, nil, []]
      invalid.each do |value|
        assert(A.closed_diagnostic(value).nil? && A::Failure.new('response_invalid', value).diagnostic.nil?)
      end
      Dir.mktmpdir do |parent|
        # Even an internal error with a tampered diagnostic is revalidated before publication.
        fake = Object.new; fake.define_singleton_method(:encrypt) { |_| raise 'Must not run' }
        error = A::Failure.new('response_invalid', valid)
        error.instance_variable_set(:@diagnostic, valid.merge('observed' => SecureRandom.hex(16)))
        output = File.join(parent, 'output')
        assert(A.run(output, config: {}, envelope_factory: ->(_, _) { fake }, source_factory: -> { raise error }) == 1)
        report = JSON.parse(File.read(File.join(output, 'apple-review-public.json')))
        assert(report['reasons'] == ['response_invalid'] && !report.key?('diagnostic'))
      end
    }
    cases.each_with_index { |(_, test), index| test.call; puts "PASS apple canonical fixture #{index + 1}" }
    puts "#{cases.length} pure Apple reference checks passed; no provider or real encryption executed."
  end
end
AppleReviewReferenceTest.run if $PROGRAM_NAME == __FILE__
