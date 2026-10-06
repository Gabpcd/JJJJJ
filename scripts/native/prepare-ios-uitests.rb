# La gem xcodeproj 1.28.1 est déjà verrouillée dans le Gemfile.lock du produit.
require 'xcodeproj'
require 'fileutils'
require 'json'
abort 'Banc CI requis' unless ENV['CI'] == 'true' && ENV['NATIVE_RECETTE'] == '1'
project = Xcodeproj::Project.open('ios/App/App.xcodeproj')
app = project.targets.find { |target| target.name == 'App' }
abort 'Une seule cible produit attendue' unless app && project.targets.length == 1
app.build_configurations.each do |configuration|
  settings = configuration.build_settings
  abort 'Version livrée différente' unless settings['MARKETING_VERSION'] == '1.0.7' && settings['CURRENT_PROJECT_VERSION'].to_s == '24'
  abort 'Identifiant produit inattendu' unless settings['PRODUCT_BUNDLE_IDENTIFIER'] == 'app.jolene'
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'app.jolene.recette'
  settings['CODE_SIGNING_ALLOWED'] = 'NO'
  settings['CODE_SIGN_ENTITLEMENTS'] = ''
end
plist_path = 'ios/App/App/Info.plist'
plist = Xcodeproj::Plist.read_from_path(plist_path)
# Le client OTA natif utilise URLSession, hors WebView : son URL a été redirigée
# sur loopback. Cette dérogation ATS n'existe que dans le binaire de simulation.
plist['NSAppTransportSecurity'] = { 'NSAllowsArbitraryLoads' => true }
Xcodeproj::Plist.write_to_path(plist, plist_path)
FileUtils.mkdir_p('ios/App/JoleneRecetteUITests')
FileUtils.cp(ARGV.fetch(0), 'ios/App/JoleneRecetteUITests/NavigationTests.swift')
target = project.new_target(:ui_test_bundle, 'JoleneRecetteUITests', :ios, '15.0')
target.add_dependency(app)
group = project.main_group.new_group('JoleneRecetteUITests', 'JoleneRecetteUITests')
target.source_build_phase.add_file_reference(group.new_file('NavigationTests.swift'))
target.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'app.jolene.recette.uitests',
    # new_target ne reprend pas le PRODUCT_NAME de la cible App. Sans cette
    # valeur, Xcode crée -Runner.app/PlugIns/.xctest et fait entrer le répertoire
    # du bundle en collision avec sa commande de liaison universelle.
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
    'TEST_TARGET_NAME' => 'App', 'CODE_SIGNING_ALLOWED' => 'NO',
    'TARGETED_DEVICE_FAMILY' => '1,2', 'IPHONEOS_DEPLOYMENT_TARGET' => '15.0'
  })
end
project.root_object.attributes['TargetAttributes'][target.uuid] = { 'TestTargetID' => app.uuid }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(target)
scheme.add_test_target(target)
scheme.test_action.build_configuration = 'Release'
scheme.launch_action.build_configuration = 'Release'
scheme.save_as(project.path, 'JoleneRecette', true)
