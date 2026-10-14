#!/usr/bin/env ruby
# Génère uniquement un banc auxiliaire. Aucun build, installation, archive,
# connexion Apple, envoi store ou changement OTA n'est effectué par ce script.
require 'fileutils'
require 'json'
require 'optparse'
require 'pathname'
begin
  require 'xcodeproj'
rescue LoadError
  abort 'Gem xcodeproj absente : ne rien installer automatiquement ; utiliser le runtime Ruby déjà préparé.'
end

options = { team: 'GDU5AA28M9', screenshots: false }
parser = OptionParser.new do |arguments|
  arguments.banner = 'Usage: ruby scripts/native/prepare-ios-store-physical.rb --output NOUVEAU_DOSSIER [--team TEAM_ID] [--screenshots]'
  arguments.on('--output DIRECTORY', 'Dossier neuf, extérieur au checkout') { |value| options[:output] = value }
  arguments.on('--team TEAM_ID', 'Team Apple pour les seuls auxiliaires de développement') { |value| options[:team] = value }
  arguments.on('--screenshots', 'Opt-in : captures limitées à l’accueil public sans champs/alertes') { options[:screenshots] = true }
end
parser.parse!
abort parser.to_s unless options[:output] && ARGV.empty?
abort 'Team Apple invalide' unless options[:team].match?(/\A[A-Z0-9]{10}\z/)

checkout = Pathname.new(File.expand_path('../..', __dir__)).realpath
source = checkout.join('tests/native/ios/StorePhysicalTests.swift')
abort 'Source XCTest absente' unless source.file?
requested = Pathname.new(File.expand_path(options[:output]))
abort 'Le dossier de sortie existe déjà : choisir un nouveau dossier, sans effacer le précédent.' if requested.exist? || requested.symlink?
abort 'Le parent du dossier de sortie doit déjà exister.' unless requested.parent.directory?
output = requested.parent.realpath.join(requested.basename)
abort 'Le banc doit rester extérieur au checkout.' if output == checkout || output.to_s.start_with?(checkout.to_s + '/')

host_name = 'JolenePhysicalHost'
test_name = 'JoleneStorePhysicalUITests'
host_bundle = 'app.jolene.physicalrecette.host'
test_bundle = 'app.jolene.physicalrecette.uitests'
scheme_name = 'JoleneStorePhysical'
FileUtils.mkdir(output)
FileUtils.mkdir(output.join(host_name))
FileUtils.mkdir(output.join(test_name))
File.write(output.join(host_name, 'AppDelegate.swift'), <<~SWIFT)
  import UIKit

  // Auxiliaire vide, distinct de Jolene. Ne contient ni réseau ni données.
  @main
  final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
      let controller = UIViewController()
      controller.view.backgroundColor = .systemBackground
      let label = UILabel()
      label.text = "Banc de vérification Jolene"
      label.textAlignment = .center
      label.frame = UIScreen.main.bounds
      controller.view.addSubview(label)
      window = UIWindow(frame: UIScreen.main.bounds)
      window?.rootViewController = controller
      window?.makeKeyAndVisible()
      return true
    }
  }
SWIFT
FileUtils.cp(source, output.join(test_name, 'StorePhysicalTests.swift'))

project_path = output.join('JoleneStorePhysical.xcodeproj')
project = Xcodeproj::Project.new(project_path.to_s)
host = project.new_target(:application, host_name, :ios, '15.0')
tests = project.new_target(:ui_test_bundle, test_name, :ios, '15.0')
tests.add_dependency(host)
[[host, host_name, 'AppDelegate.swift'], [tests, test_name, 'StorePhysicalTests.swift']].each do |target, directory, filename|
  group = project.main_group.new_group(directory, directory)
  target.source_build_phase.add_file_reference(group.new_file(filename))
  target.build_configurations.each do |configuration|
    configuration.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => target == host ? host_bundle : test_bundle,
      'PRODUCT_NAME' => '$(TARGET_NAME)',
      'DEVELOPMENT_TEAM' => options[:team],
      'CODE_SIGN_STYLE' => 'Automatic',
      'CODE_SIGN_IDENTITY[sdk=iphoneos*]' => 'Apple Development',
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'SWIFT_VERSION' => '5.0',
      'IPHONEOS_DEPLOYMENT_TARGET' => '15.0',
      'TARGETED_DEVICE_FAMILY' => '1,2',
      'SDKROOT' => 'iphoneos',
      'SKIP_INSTALL' => 'YES'
    })
  end
end
host.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    'INFOPLIST_KEY_CFBundleDisplayName' => 'Jolene Physical Host',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'NO'
  })
end
tests.build_configurations.each do |configuration|
  configuration.build_settings['TEST_TARGET_NAME'] = host_name
end
project.root_object.attributes['TargetAttributes'] = {
  host.uuid => { 'DevelopmentTeam' => options[:team], 'ProvisioningStyle' => 'Automatic' },
  tests.uuid => { 'DevelopmentTeam' => options[:team], 'ProvisioningStyle' => 'Automatic', 'TestTargetID' => host.uuid }
}

# Le scheme ne connaît aucun produit app.jolene. Apple's documented lookup
# then uses the app already installed for XCUIApplication(bundleIdentifier:).
abort 'Dépendance auxiliaire inattendue' unless tests.dependencies.map(&:target) == [host] && host.dependencies.empty?
abort 'Une cible ne doit jamais remplacer Jolene' if project.targets.any? { |target|
  target.build_configurations.any? { |configuration| configuration.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] == 'app.jolene' }
}
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(host, false)
scheme.add_build_target(tests, false)
scheme.build_action.parallelize_buildables = false
scheme.build_action.build_implicit_dependencies = false
scheme.test_action.build_configuration = 'Debug'
scheme.test_action.xml_element.attributes['shouldUseLaunchSchemeArgsEnv'] = 'NO'
scheme.test_action.xml_element.delete_element('Testables')
scheme.test_action.xml_element.add_element('TestPlans').add_element('TestPlanReference', {
  'reference' => 'container:JoleneStorePhysical.xctestplan', 'default' => 'YES'
})
scheme.save_as(project_path.to_s, scheme_name, true)

plan = {
  'configurations' => [{ 'id' => '1542B7D8-557F-4AE5-BDCB-20B261C9AC70', 'name' => 'PhysicalStore', 'options' => {} }],
  'defaultOptions' => {
    'codeCoverage' => false,
    'systemAttachmentLifetime' => 'keepNever',
    'userAttachmentLifetime' => 'keepAlways',
    'environmentVariableEntries' => [{
      'key' => 'JOLENE_PHYSICAL_CAPTURE_SCREENSHOTS', 'value' => options[:screenshots] ? '1' : '0', 'enabled' => true
    }]
  },
  'testTargets' => [{
    'parallelizable' => false,
    'target' => { 'containerPath' => 'container:JoleneStorePhysical.xcodeproj', 'identifier' => tests.uuid, 'name' => test_name }
  }],
  'version' => 1
}
File.write(output.join('JoleneStorePhysical.xctestplan'), JSON.pretty_generate(plan) + "\n")
manifest = {
  schema: 'jolene-store-physical-harness/v1',
  project: project_path.to_s, scheme: scheme_name, developmentTeam: options[:team],
  installedAppUnderTest: 'app.jolene', hostBundle: host_bundle, testBundle: test_bundle,
  expectedRunnerBundle: test_bundle + '.xctrunner', screenshotsOptIn: options[:screenshots],
  installedAppRebuilt: false, buildExecuted: false, deviceAccessed: false,
  warning: 'Ouverture et relancement seulement. Aucun login, permission, document, GPS, push, PSC ou paiement validé. Vérifier le bundle store installé et les clés AttachmentLifetime du .xctestrun avant exécution.'
}
File.write(output.join('harness-manifest.json'), JSON.pretty_generate(manifest) + "\n")
puts JSON.pretty_generate(manifest)
