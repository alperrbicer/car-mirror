def add_crashlytics_symbols(project, app)
  app.build_configurations.each do |config|
    config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf-with-dsym'
    # Xcode's default package location; CLI builds override this for the shared cache.
    config.build_settings['MIRIVO_CRASHLYTICS_DIR'] = '$(BUILD_ROOT)/../../SourcePackages/checkouts/firebase-ios-sdk/Crashlytics'
    # Skipped Debug/simulator phases must not require an uploader in a custom cache.
    config.build_settings['MIRIVO_CRASHLYTICS_UPLOADER_INPUT'] = '$(SRCROOT)/scripts/upload-crashlytics-symbols.sh'
    if config.name == 'Release'
      config.build_settings['MIRIVO_CRASHLYTICS_UPLOADER_INPUT[sdk=iphoneos*]'] = '$(MIRIVO_CRASHLYTICS_DIR)/upload-symbols'
    end
  end
  phase = app.shell_script_build_phases.find { |item| item.name == 'Upload Crashlytics symbols' } ||
    app.new_shell_script_build_phase('Upload Crashlytics symbols')
  phase.shell_script = '"${SRCROOT}/scripts/upload-crashlytics-symbols.sh"'
  phase.input_paths = [
    '$(SRCROOT)/scripts/upload-crashlytics-symbols.sh',
    '$(MIRIVO_CRASHLYTICS_UPLOADER_INPUT)',
    '${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}',
    '${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${PRODUCT_NAME}',
    '${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Info.plist',
    '$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist',
    '$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)'
  ]
  phase.always_out_of_date = '1'
end
