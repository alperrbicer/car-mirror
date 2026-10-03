# Shared by project generation and incremental setup; no binary is vendored.
def add_google_cast(project, app)
  path = 'Dependencies/GoogleCast'
  package = project.root_object.package_references.find { |p| p.respond_to?(:relative_path) && p.relative_path == path }
  unless package
    package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
    package.relative_path = path
    project.root_object.package_references << package
  end
  unless app.package_product_dependencies.any? { |p| p.product_name == 'GoogleCast' }
    product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    product.package = package
    product.product_name = 'GoogleCast'
    app.package_product_dependencies << product
    file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    file.product_ref = product
    app.frameworks_build_phase.files << file
  end
  app.build_configurations.each do |config|
    flags = config.build_settings['OTHER_LDFLAGS'] || ['$(inherited)']
    flags = flags.split if flags.is_a?(String)
    config.build_settings['OTHER_LDFLAGS'] = (flags + ['-ObjC', '-lc++']).uniq
  end
  # Native copy phases track the complete resource directories produced by SwiftPM.
  # A script's flattened input list only grants access to the framework directory itself.
  app.shell_script_build_phases.select { |p| p.name == 'Copy Cast SDK resources' }.each(&:remove_from_project)
  phase = app.copy_files_build_phases.find { |p| p.name == 'Copy Cast SDK resources' } || app.new_copy_files_build_phase('Copy Cast SDK resources')
  phase.dst_subfolder_spec = '7'
  %w[GoogleCastCoreResources GoogleCastUIResources GoogleCastOptionalUIResources GoogleSansRegular GoogleSansMedium GoogleSansBold MaterialDialogs].each do |name|
    path = "GoogleCast.framework/#{name}.bundle"
    ref = project.files.find { |f| f.path == path && f.source_tree == 'BUILT_PRODUCTS_DIR' } || project.main_group.new_file(path, :built_products)
    phase.add_file_reference(ref) unless phase.files_references.include?(ref)
  end
  privacy = app.copy_files_build_phases.find { |p| p.name == 'Copy Cast privacy manifest' } || app.new_copy_files_build_phase('Copy Cast privacy manifest')
  privacy.dst_subfolder_spec = '7'
  privacy.dst_path = 'GoogleCastPrivacy.bundle'
  path = 'GoogleCast.framework/PrivacyInfo.xcprivacy'
  ref = project.files.find { |f| f.path == path && f.source_tree == 'BUILT_PRODUCTS_DIR' } || project.main_group.new_file(path, :built_products)
  privacy.add_file_reference(ref) unless privacy.files_references.include?(ref)
end
