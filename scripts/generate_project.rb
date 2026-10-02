#!/usr/bin/env ruby
require 'xcodeproj'

root = File.expand_path('..', __dir__)
project_path = File.join(root, 'CarMirror.xcodeproj')
abort 'Project exists. Pass --replace to regenerate only CarMirror.xcodeproj.' if File.exist?(project_path) && !ARGV.include?('--replace')
project = Xcodeproj::Project.new(project_path)
%w[Debug-CarPlay Release-CarPlay].each { |name| project.add_build_configuration(name, name.start_with?('Debug') ? :debug : :release) }
base = project.main_group.new_file('Config/Base.xcconfig')
app = project.new_target(:application, 'CarMirror', :ios, '18.0')
broadcast = project.new_target(:app_extension, 'CarMirrorBroadcast', :ios, '18.0')

[app, broadcast].each do |target|
  %w[Debug-CarPlay Release-CarPlay].each { |name| target.add_build_configuration(name, name.start_with?('Debug') ? :debug : :release) }
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
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Config/CarPlay.entitlements'
end
broadcast.build_configurations.each do |config|
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
project.root_object.attributes['LastUpgradeCheck'] = '2700'
project.save

{ 'CarMirror' => ['Debug', 'Release'], 'CarMirror CarPlay' => ['Debug-CarPlay', 'Release-CarPlay'] }.each do |name, configurations|
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(app)
  scheme.set_launch_target(app)
  scheme.launch_action.build_configuration = configurations[0]
  scheme.profile_action.build_configuration = configurations[1]
  scheme.archive_action.build_configuration = configurations[1]
  scheme.save_as(project_path, name, true)
end
puts "Created #{project_path}"
