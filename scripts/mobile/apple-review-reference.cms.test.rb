#!/usr/bin/env ruby
# Local crypto only. Generates one disposable test key, never an ASC credential.
require_relative 'apple-review-reference'
require 'securerandom'

module AppleReviewCmsTest
  A = AppleReviewReference
  def self.assert(value); raise 'Closed CMS test assertion failed' unless value; end
  def self.run(binary)
    assert(['/usr/bin/openssl', '/opt/homebrew/bin/openssl'].include?(binary))
    File.umask(0o077)
    Dir.mktmpdir('apple-review-cms-synthetic-') do |directory|
      # Commands and all child output remain private. Nothing invokes an HTTP client.
      invoke = lambda do |args, input = ''|
        Open3.capture3({ 'PATH' => '/usr/bin:/bin', 'HOME' => directory, 'OPENSSL_CONF' => '/dev/null' },
          binary, *args, stdin_data: input, binmode: true, unsetenv_others: true)
      end
      key = File.join(directory, 'test-only-key.pem'); cert = File.join(directory, 'test-only-cert.pem')
      _out, _err, status = invoke.call(['req', '-new', '-x509', '-newkey', 'rsa:3072', '-nodes',
        '-subj', '/CN=Jolene synthetic CMS test', '-days', '1', '-keyout', key, '-out', cert])
      assert(status.success? && (File.stat(key).mode & 0o777) == 0o600)
      pem = File.read(cert); parsed = OpenSSL::X509::Certificate.new(pem)
      config = { 'schema' => 1, 'certificateDerSha256' => Digest::SHA256.hexdigest(parsed.to_der), 'certificatePem' => pem }
      private_data = { 'reference' => SecureRandom.hex(20) + '@example.invalid', 'notes' => SecureRandom.hex(32) }
      envelope = A::Envelope.new(config, directory, binary: binary)
      encrypted = envelope.encrypt(private_data)
      assert(!encrypted.include?(private_data['notes']) && !encrypted.include?(private_data['reference']))
      decrypt = ['cms', '-decrypt', '-binary', '-inform', 'DER', '-recip', cert, '-inkey', key]
      plaintext, _err, status = invoke.call(decrypt, encrypted)
      assert(status.success? && JSON.parse(plaintext) == private_data)
      puts 'PASS CMS AES-256-GCM/RSA-OAEP synthetic roundtrip'

      # Change one byte of the GCM authentication tag while preserving ASN.1 syntax.
      altered = OpenSSL::ASN1.decode(encrypted)
      auth_envelope = altered.value[1].value[0]
      mac = auth_envelope.value.reverse.find { |field| field.is_a?(OpenSSL::ASN1::OctetString) }
      assert(mac && mac.value.bytesize == 16)
      mac.value.setbyte(0, mac.value.getbyte(0) ^ 1)
      _private_output, _private_error, status = invoke.call(decrypt, altered.to_der)
      assert(!status.success?) # Never consume decrypt output before successful authentication.
      puts 'PASS CMS altered authentication tag is refused'

      begin
        A::Envelope.new(config.merge('certificateDerSha256' => '0' * 64), directory, binary: binary)
        raise 'Expected closed refusal'
      rescue A::Failure => error
        assert(error.code == 'recipient_invalid')
      end
      puts 'PASS CMS wrong reviewed recipient fingerprint is refused'
      begin
        A::Envelope.new(config.merge('certificatePem' => pem + pem), directory, binary: binary)
        raise 'Expected closed refusal'
      rescue A::Failure => error
        assert(error.code == 'recipient_invalid')
      end
      puts 'PASS CMS additional recipient certificate is refused'
    end
    puts '4 local CMS checks passed; temporary synthetic key cleaned; no provider or application credential.'
  rescue StandardError
    warn 'CMS synthetic checks failed (closed diagnostic).'
    exit 1
  end
end

if $PROGRAM_NAME == __FILE__
  AppleReviewCmsTest.run(ARGV.empty? ? '/usr/bin/openssl' : ARGV.fetch(0))
end
