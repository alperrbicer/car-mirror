#!/usr/bin/env ruby
require 'xcodeproj'
require 'json'
require_relative 'cast_project'

root = File.expand_path('..', __dir__)
languages = JSON.parse(File.read(File.join(root, 'Config/Localizations.json')))
project_path = File.join(root, 'CarMirror.xcodeproj')
abort 'Project exists. Pass --replace to regenerate only CarMirror.xcodeproj.' if File.exist?(project_path) && !ARGV.include?('--replace')
project = Xcodeproj::Project.new(project_path)
base = project.main_group.new_file('Config/Base.xcconfig')
app = project.new_target(:application, 'CarMirror', :ios, '18.0')
broadcast = project.new_target(:app_extension, 'CarMirrorBroadcast', :ios, '18.0')

# Official VideoLAN binary, pinned for reproducible MKV/PiP support.
vlc = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
vlc.repositoryURL = 'https://github.com/videolan/vlckit.git'
vlc.requirement = {'kind' => 'revision', 'revision' => '2e0868f5ed40fe59cd92f377645fdcc260c6e759'}
project.root_object.package_references << vlc
vlc_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
vlc_product.package = vlc
vlc_product.product_name = 'VLCKit'
app.package_product_dependencies << vlc_product
vlc_build = project.new(Xcodeproj::Project::Object::PBXBuildFile)
vlc_build.product_ref = vlc_product
app.frameworks_build_phase.files << vlc_build

# RevenueCat observes the app's verified StoreKit 2 transactions.
revenuecat = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
revenuecat.repositoryURL = 'https://github.com/RevenueCat/purchases-ios.git'
revenuecat.requirement = {'kind' => 'upToNextMajorVersion', 'minimumVersion' => '5.43.0'}
project.root_object.package_references << revenuecat
rc_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
rc_product.package = revenuecat
rc_product.product_name = 'RevenueCat'
app.package_product_dependencies << rc_product
rc_build = project.new(Xcodeproj::Project::Object::PBXBuildFile)
rc_build.product_ref = rc_product
app.frameworks_build_phase.files << rc_build

# Remote Config, opt-in FCM and Analytics without advertising identifiers.
firebase = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
firebase.repositoryURL = 'https://github.com/firebase/firebase-ios-sdk.git'
firebase.requirement = {'kind' => 'exactVersion', 'version' => '12.19.2'}
project.root_object.package_references << firebase
%w[FirebaseCore FirebaseRemoteConfig FirebaseMessaging FirebaseAuth FirebaseFunctions FirebaseAppCheck FirebaseAnalyticsCore].each do |name|
  product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.package = firebase
  product.product_name = name
  app.package_product_dependencies << product
  build = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build.product_ref = product
  app.frameworks_build_phase.files << build
end
if File.file?(File.join(root, 'Config/GoogleService-Info.plist'))
  firebase_config = project.main_group.new_file('Config/GoogleService-Info.plist')
  app.resources_build_phase.add_file_reference(firebase_config)
end

[app, broadcast].each do |target|
  target.build_configurations.each do |config|
    config.base_configuration_reference = base
    settings = config.build_settings
    settings['SWIFT_VERSION'] = '5.0'
    settings['SDKROOT'] = 'iphoneos'
    settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
    settings['TARGETED_DEVICE_FAMILY'] = '1'
    settings['SUPPORTS_MACCATALYST'] = 'NO'
    settings['SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD'] = 'NO'
    settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    settings['CODE_SIGN_ENTITLEMENTS'] = 'Config/App.entitlements'
    settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
    if config.name.start_with?('Debug')
      settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
      settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
      settings['GCC_PREPROCESSOR_DEFINITIONS'] = ['$(inherited)', 'DEBUG=1']
    end
  end
end

app.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(MIRROR_BUNDLE_ID)'
  config.build_settings['INFOPLIST_FILE'] = 'Config/App-Info.plist'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Config/App.entitlements'
end
broadcast.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Config/Broadcast.entitlements'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(MIRROR_BUNDLE_ID).broadcast'
  config.build_settings['INFOPLIST_FILE'] = 'Config/Broadcast-Info.plist'
  config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  config.build_settings['SKIP_INSTALL'] = 'YES'
end

references = {}
%w[Core Shared App Media Broadcast].each do |folder|
  group = project.main_group.new_group(folder, "Sources/#{folder}")
  Dir.glob(File.join(root, "Sources/#{folder}/*.swift")).sort.each do |path|
    reference = group.new_file(File.basename(path))
    references[path] = reference
    app.source_build_phase.add_file_reference(reference) if %w[Core Shared App].include?(folder)
    broadcast.source_build_phase.add_file_reference(reference) if %w[Core Shared Media Broadcast].include?(folder)
  end
end
privacy = project.main_group.new_file('Resources/PrivacyInfo.xcprivacy')
app.resources_build_phase.add_file_reference(privacy)
broadcast.resources_build_phase.add_file_reference(privacy)
assets = project.main_group.new_file('Resources/Assets.xcassets')
app.resources_build_phase.add_file_reference(assets)
probe = project.main_group.new_file('Resources/ConnectionProbe.mp4')
app.resources_build_phase.add_file_reference(probe)
app.add_dependency(broadcast)
embed = app.new_copy_files_build_phase('Embed Broadcast Extension')
embed.dst_subfolder_spec = '13'
embed.add_file_reference(broadcast.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
# Only third-party SDK licenses are bundled; product documents open on Netlify.
notices = project.main_group.new_file('Resources/Notices')
notices.last_known_file_type = 'folder'
app.resources_build_phase.add_file_reference(notices)
%w[Localizable.strings InfoPlist.strings].each do |filename|
  variant = project.main_group.new_variant_group(filename)
  languages.each do |language|
    abort "Missing #{language}/#{filename}" unless File.file?(File.join(root, "Resources/#{language}.lproj/#{filename}"))
    ref = variant.new_file("Resources/#{language}.lproj/#{filename}")
    ref.name = language
  end
  app.resources_build_phase.add_file_reference(variant)
  broadcast.resources_build_phase.add_file_reference(variant)
end
project.root_object.development_region = 'tr'
project.root_object.known_regions = languages + ['Base']
project.root_object.attributes['LastUpgradeCheck'] = '2700'
# Local StoreKit and UI suites run in the simulator; no live purchase is made.
tests = project.new_target(:unit_test_bundle, 'MirivoTests', :ios, '18.0')
ui_tests = project.new_target(:ui_test_bundle, 'MirivoUITests', :ios, '18.0')
[tests, ui_tests].each do |target|
  target.add_dependency(app)
  target.build_configurations.each do |config|
    config.base_configuration_reference = base
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "$(MIRROR_BUNDLE_ID).#{target.name}"
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
    config.build_settings['SDKROOT'] = 'iphoneos'
    config.build_settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = ''
    if target == tests
      config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/CarMirror.app/CarMirror'
      config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
    else
      config.build_settings['TEST_TARGET_NAME'] = 'CarMirror'
    end
  end
end
{tests => 'App', ui_tests => 'UI'}.each do |target, folder|
  Dir.glob(File.join(root, "Tests/#{folder}/*.swift")).sort.each do |path|
    target.source_build_phase.add_file_reference(project.main_group.new_file("Tests/#{folder}/#{File.basename(path)}"))
  end
end
fixture = project.main_group.new_file('Tests/App/Mirivo.storekit')
tests.resources_build_phase.add_file_reference(fixture)
video_fixture = project.main_group.new_file('Tests/Fixtures/InlineVideo.mkv')
tests.resources_build_phase.add_file_reference(video_fixture)
add_google_cast(project, app)
project.save

{ 'CarMirror' => ['Debug', 'Release'] }.each do |name, configurations|
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(app)
  scheme.set_launch_target(app)
  if name == 'CarMirror'
    scheme.add_test_target(tests)
    scheme.add_test_target(ui_tests)
    scheme.launch_action.xml_element.add_element('StoreKitConfigurationFileReference', { 'identifier' => '../../Tests/App/Mirivo.storekit' })
  end
  scheme.launch_action.build_configuration = configurations[0]
  scheme.profile_action.build_configuration = configurations[1]
  scheme.archive_action.build_configuration = configurations[1]
  scheme.save_as(project_path, name, true)
end
puts "Created #{project_path}"
