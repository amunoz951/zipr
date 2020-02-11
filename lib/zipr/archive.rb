module Zipr
  @cache_path = (Zipr.config['common']['paths']['cache'] || Dir.tmpdir()) + '/zipr'

  module Archive
    module_function

    # options: { exclude_files: [], exclude_unless_missing: [], archive_type: :zip, password: nil }
    # archive_type values: :zip, :seven_zip
    # mode values:
    #   :idempotent - overwrites only when a file does not have the same content as the file in the zip file
    #   :overwrite - always overwrites all files
    #   :if_missing - never overwrites any files, only extracts if the file does not exist in the destination
    def extract(archive_path, destination_folder, changed_files: nil, options: nil, archive_checksums: nil, mode: :idempotent)
      options ||= {}
      options[:archive_type] ||= :zip
      options[:overwrite] = mode != :if_missing
      checksum_path = "#{@cache_path}/checksums/#{File.basename(archive_path)}.txt"
      if mode == :idempotent
        calculated_changed_files, calculated_archive_checksums = changed_files_for_extract(archive_path, checksum_path, destination_folder, options)
        changed_files ||= calculated_changed_files
        archive_checksums ||= calculated_archive_checksums
      elsif changed_files.nil? || archive_checksums.nil?
        changed_files = nil
        archive_checksums = {}
      end

      archive_checksums = case options[:archive_type]
                          when :zip
                            extract_zip(archive_path, destination_folder, changed_files, options, archive_checksums: archive_checksums)
                          when :seven_zip
                            extract_seven_zip(archive_path, destination_folder, changed_files, options, archive_checksums: archive_checksums)
                          else
                            raise "':#{options[:archive_type]}' is not a supported archive type!"
                          end

      FileUtils.mkdir_p(::File.dirname(checksum_path))
      ::File.write(checksum_path, archive_checksums.to_json)
    end

    # options: { archive_type: :seven_zip }
    # archive_type values: :zip, :seven_zip
    def add(archive_path, source_folder, source_files, options: nil, archive_checksums: nil)
      options ||= {}
      options[:archive_type] ||= :zip
      return nil if source_files.nil?
      FileUtils.mkdir_p(::File.dirname(archive_path))
      calculated_checksums = case options[:archive_type]
                            when :zip
                              add_to_zip(archive_path, source_folder, source_files, archive_checksums: archive_checksums)
                            when :seven_zip
                              add_to_seven_zip(archive_path, source_folder, source_files, archive_checksums: archive_checksums)
                            else
                              raise "':#{options[:archive_type]}' is not a supported archive type!"
                            end
      raise "Failed to create archive at #{archive_path}!" unless ::File.file?(archive_path)
      calculated_checksums['archive_checksum'] = ::Digest::SHA256.file(archive_path).hexdigest
      calculated_checksums
    end

    # Read a file inside a zip file without extracting it
    def read_file(archive_path, relative_path, options: nil)
      options ||= {}
      options[:archive_type] ||= :zip
      raise 'Reading files inside a 7zip archive is not yet supported!' if options[:archive_type] == :seven_zip
      EasyIO.logger.debug "Reading #{archive_path} // #{relative_path}..."
      Zip::File.open(archive_path).read(relative_path)
    end

    private

    # options: { exclude_files: [], exclude_unless_missing: [], overwrite: true }
    def extract_zip(archive_path, destination_folder, changed_files, options, archive_checksums: nil)
      archive_checksums ||= {}
      archive_checksums['archive_checksum'] = Digest::SHA256.file(archive_path).hexdigest
      Zip::File.open(archive_path) do |archive_items|
        EasyIO.logger.info "Extracting to #{destination_folder}..."
        archive_items.each do |archive_item|
          destination_path = ::File.join(destination_folder.tr('\\', '/'), archive_item.name)
          next unless changed_files.nil? || changed_files.include?(archive_item.name)
          next if Zipr.excluded_file?(archive_item.name, options, destination_path: destination_path)
          if archive_item.ftype == :directory
            FileUtils.mkdir_p(destination_path)
            archive_checksums[archive_item.name.tr('\\', '/')] = 'directory'
            next
          end
          next if ::File.file?(destination_path) && !options[:overwrite] # skip extract if the file exists and overwrite is false
          FileUtils.mkdir_p(::File.dirname(destination_path))
          EasyIO.logger.info "Extracting #{archive_item.name}..."
          archive_item.extract(destination_path) { :overwrite }
          archive_checksums[archive_item.name.tr('\\', '/')] = Digest::SHA256.file(destination_path).hexdigest
        end
      end
      archive_checksums
    end

    # options: { exclude_files: [], exclude_unless_missing: [], overwrite: true, password: nil }
    def extract_seven_zip(archive_path, destination_folder, changed_files, options, archive_checksums: nil)
      archive_checksums ||= {}
      archive_checksums['archive_checksum'] = Digest::SHA256.file(archive_path).hexdigest
      ::File.open(archive_path, 'rb') do |archive_file|
        SevenZipRuby::Reader.open(archive_file, options) do |seven_zip_archive|
          EasyIO.logger.info "Extracting to #{destination_folder}..."
          seven_zip_archive.entries.each do |archive_item|
            destination_path = ::File.join(destination_folder.tr('\\', '/'), archive_item.path)
            next unless changed_files.nil? || changed_files.include?(archive_item.path)
            next if Zipr.excluded_file?(archive_item.path, options, destination_path: destination_path)
            if archive_item.directory?
              FileUtils.mkdir_p(destination_path)
              archive_checksums[archive_item.path.tr('\\', '/')] = 'directory'
              next
            end
            if ::File.file?(destination_path)
              options['overwrite'] ? FileUtils.rm(destination_path) : next # skip extract if the file exists and overwrite is false
            end
            FileUtils.mkdir_p(::File.dirname(destination_path))
            EasyIO.logger.info "Extracting #{archive_item.path}..."
            seven_zip_archive.extract(archive_item.index, destination_folder)
            archive_checksums[archive_item.path.tr('\\', '/')] = Digest::SHA256.file(destination_path).hexdigest
          end
        end
      end
      archive_checksums
    end

    # options: { exclude_files: [], exclude_unless_missing: [] }
    def changed_files_for_extract(archive_path, checksum_file, destination_folder, options)
      changed_files = nil # changed_files must be nil if the checksum file does not yet exist
      archive_checksums = {}
      if ::File.exist?(checksum_file)
        changed_files = []
        file_content = ::File.read(checksum_file)
        archive_checksums = JSON.parse(file_content)
        return [nil, {}] if ::File.exist?(archive_path) && archive_checksums['archive_checksum'] != Digest::SHA256.file(archive_path).hexdigest # If the archive has changed, return and extract again
        archive_checksums.each do |compressed_file, compressed_file_checksum|
          next if compressed_file == 'archive_checksum'
          destination_path = "#{destination_folder}/#{compressed_file}"
          next if Zipr.excluded_file?(compressed_file, options, destination_path: destination_path)
          next if ::File.file?(destination_path) && ::Digest::SHA256.file(destination_path).hexdigest == compressed_file_checksum
          next if ::File.directory?(destination_path) && compressed_file_checksum == 'directory'
          changed_files.push(compressed_file)
        end
      end
      [changed_files, archive_checksums]
    end

    def add_to_zip(archive_path, source_folder, source_files, archive_checksums: nil)
      archive_checksums ||= {}
      Zip::File.open(archive_path, Zip::File::CREATE) do |zip_archive|
        EasyIO.logger.info "Compressing to #{archive_path}..."
        source_files.each do |source_file|
          relative_path = source_file.tr('\\', '/')
          relative_path.slice!(source_folder.tr('\\', '/'))
          relative_path = relative_path.reverse.chomp('/').reverse
          EasyIO.logger.info "Compressing #{relative_path}..."
          if ::File.directory?(source_file)
            zip_archive.mkdir(relative_path) unless zip_archive.find_entry(relative_path)
            archive_item_checksum = 'directory'
          else
            zip_archive.add(relative_path, source_file) { :overwrite }
            archive_item_checksum = Digest::SHA256.file(source_file).hexdigest
          end
          archive_checksums[relative_path] = archive_item_checksum
        end
      end
      archive_checksums
    end

    def add_to_seven_zip(archive_path, source_folder, source_files, archive_checksums: nil)
      archive_checksums ||= {}
      ::File.open(archive_path, 'wb') do |archive_file|
        SevenZipRuby::Writer.open(archive_file) do |seven_zip_archive|
          EasyIO.logger.info "Compressing to #{archive_path}..."
          source_files.each do |source_file|
            relative_path = source_file.tr('\\', '/')
            relative_path.slice!(source_folder.tr('\\', '/'))
            relative_path = relative_path.reverse.chomp('/').reverse
            seven_zip_options = { as: relative_path }
            EasyIO.logger.info "Compressing #{relative_path}..."
            if ::File.directory?(source_file)
              seven_zip_archive.mkdir(relative_path)
              archive_item_checksum = 'directory'
            else
              seven_zip_archive.add_file(source_file, seven_zip_options)
              archive_item_checksum = Digest::SHA256.file(source_file).hexdigest
            end
            archive_checksums[relative_path] = archive_item_checksum
          end
        end
      end
      archive_checksums
    end

    # options: { exclude_files: [], exclude_unless_missing: [] }
    def changed_files_for_add_to_archive(archive_path, checksum_file, source_folder, target_files, options = {})
      checksum_file ||= Zipr.create_action_checksum_file(archive_path, target_files)
      FileUtils.rm(checksum_file) if ::File.file?(checksum_file) && !::File.file?(archive_path) # Start over if the archive is missing

      archive_checksums = {}
      changed_files = []
      if ::File.exist?(checksum_file)
        file_content = ::File.read(checksum_file)
        archive_checksums = JSON.parse(file_content)
      end
      target_files.each do |target_search|
        source_files = Dir.glob(Zipr.prepend_source_folder(source_folder, target_search))
        source_files.each do |source_file|
          relative_path = Zipr.slice_source_folder(source_folder, source_file)
          exists_in_zip = !!archive_checksums[relative_path]
          next if Zipr.excluded_file?(relative_path, options, exists_in_zip: exists_in_zip) || Zipr.excluded_file?(source_file, options, exists_in_zip: exists_in_zip)
          next if ::File.file?(source_file) && archive_checksums[relative_path] == Digest::SHA256.file(source_file).hexdigest
          next if ::File.directory?(source_file) && archive_checksums[relative_path] == 'directory'
          changed_files.push(source_file)
        end
      end
      [changed_files, archive_checksums]
    end
  end
end
