module Zipr
  module_function

  def seven_zip_executable_path
    path = node['seven_zip']['home']
    EasyIO.logger.debug "7-zip home: '#{path}'" unless path.nil?
    path ||= seven_zip_exe_from_registry if OS.windows?
    EasyIO.logger.debug "7-zip path: '#{path}'"
    ::File.join(path, OS.windows? ? '7z.exe' : '7z')
  end

  def seven_zip_exe_from_registry
    key_path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\7zFM.exe'
    return nil unless EasyIO::Registry.key_exists?(key_path)
    # Read path from recommended Windows App Paths registry location
    # docs: https://msdn.microsoft.com/en-us/library/windows/desktop/ee872121
    EasyIO::Registry.read(key_path, 'Path')
  end

  # returns results of all files found in the array of files, including files found by wildcard, as relative paths.
  def flattened_paths(source_folder, files)
    return files if source_folder.nil? || source_folder.empty?
    result = []
    files.each do |entry|
      standardized_entry = "#{source_folder.tr('\\', '/')}/#{slice_source_folder(source_folder, entry)}"
      files_found = Dir.glob(standardized_entry)
      if files_found.empty?
        result.push(entry)
      else
        result += files_found.map { |e| slice_source_folder(source_folder, e) }
      end
    end
    result
  end

  def wildcard_to_regexp(entry)
    return entry if entry.is_a?(Regexp)
    escaped_entry = Regexp.escape(entry).gsub(/\\\*/, '.*') # Convert asterisks to .*
    /#{escaped_entry}/
  end

  def prepend_source_folder(source_folder, entry)
    return entry.tr('\\', '/') if source_folder.nil? || source_folder.empty? || entry.tr('\\', '/').start_with?(source_folder.tr('\\', '/'))
    "#{source_folder.tr('\\', '/')}/#{entry.tr('\\', '/')}"
  end

  def slice_source_folder(source_folder, entry)
    entry.tr('\\', '/').sub(source_folder.tr('\\', '/'), '').reverse.chomp('/').reverse
  end

  def checksums_folder
    "#{@cache_path}/zipr/archive_checksums"
  end
end
