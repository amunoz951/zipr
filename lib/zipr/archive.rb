module Zipr
  class Archive
    @cache_path = "#{Zipr.config['paths']['cache']}/zipr"
    attr_accessor :checksum_path, :options, :checksums, :mode

    #
    # Description:
    #   Create an instance of the class.
    #   Allows usage of block form.
    # Returns:
    #   When used without a block, returns the instance.
    # Parameters:
    #   options:
    #     :archive_type - The type of archive - :seven_zip or :zip - Can be omitted if the archive exists or using default. Default: :zip
    #     :exclude_files - Array of files to be excluded from archiving/extracting - Can be relative or exact paths.
    #     :exclude_unless_missing - Array of files to be excluded from archiving/extracting only if they already exist - Can be relative or exact paths.
    #     :exclude_unless_archive_changed - Array of files to be excluded from extracting only if the archive hasn't changed and they already exist - Use relative paths.
    #     :password - the archive password - currently :seven_zip is the only supported archive_type for encrypted archives.
    #     :silent - [true/false] No info messages if flagged
    #   checksums: A hash of checksums of the archived files. If you checked one of the determine_files methods for idempotency first, pass the result to this parameter to avoid duplicate processing.
    #   mode:
    #     :idempotent - Does not add/extract files to/from the archive if they already exist and are the exact same file, verified by checksum.
    #     :overwrite - Adds/Extracts all eligible files to/from the archive even if the checksums match.
    #     :if_missing - never overwrites any files, only adds/extracts to/from the archive if the relative path does not exist.
    #   checksum_file: (optional) The path to the initial checksum file. Usually only needed if the archive is not kept on the disk and we need to see if extracted files have changed.
    def self.open(path, options: {}, checksums: {}, mode: :idempotent, checksum_file: nil, &block)
      archive_instance = new(path, options: options, checksums: checksums, mode: mode, checksum_file: checksum_file)
      block.nil? ? archive_instance : yield(archive_instance)
    end

    #
    # Description:
    #   Add files to an existing archive or create one if it does not exist in a single line. No additional IO handling necessary.
    # Returns:
    #   Array of 2 objects: String path to the checksum file and the hash of known checksums for archive files.
    # Parameters:
    #   path: The full path to the archive being added to/created.
    #   see comment of method 'add' below for :source_folder and :files_to_add parameter information.
    #   see comment of method 'open' above for remaining parameter information.
    def self.add(path, source_folder, files_to_add: nil, options: {}, checksums: {}, mode: :idempotent, checksum_file: nil)
      archive = new(path, options: options, checksums: checksums, mode: mode, checksum_file: checksum_file)
      archive.add(source_folder, files_to_add: files_to_add)
    end

    #
    # Description:
    #   Extract files from an archive in a single line. No additional IO handling necessary.
    # Returns:
    #   Array of 2 objects: String path to the checksum file and the hash of known checksums for archive files.
    # Parameters:
    #   path: The full path to the archive being extracted.
    #   see comment of method 'extract' for :destination_folder and :files_to_extract parameter information.
    #   see comment of method 'self.open' for remaining parameter information.
    def self.extract(path, destination_folder, files_to_extract: nil, options: {}, checksums: nil, mode: :idempotent, checksum_file: nil)
      archive = new(path, options: options, checksums: checksums, mode: mode, checksum_file: checksum_file)
      archive.extract(destination_folder, files_to_extract: files_to_extract)
    end

    #
    # Description:
    #   Determines what files should be added to an archive based on the options and mode provided in a single line.
    #   Can be useful to perform actions on changing files before they are added or to determine idempotency state (like with Chef/Puppet)
    # Returns:
    #   Array of 2 objects: an array of files to be added (or the :all symbol) and a hash of the known file checksums in the archive
    # Parameters:
    #   path: The full path to the archive being created/examined.
    #   see comment of method 'determine_files_to_add' for :source_folder and :files_to_check
    #   see comment of method 'open' for remaining parameter information.
    def self.determine_files_to_add(path, source_folder, files_to_check: nil, options: {}, checksums: {}, mode: :idempotent, checksum_file: nil)
      archive = new(path, options: options, checksums: checksums, mode: mode, checksum_file: checksum_file)
      files_to_add = archive.determine_files_to_add(source_folder, files_to_check: files_to_check)
      [files_to_add, archive.checksums]
    end

    #
    # Description:
    #   Determines what files should be extracted based on the options and mode provided.
    #   Can be useful to perform actions on changing files before they are extracted or to determine idempotency state (like with Chef/Puppet).
    # Returns:
    #   Array of 2 objects: an array of files to be extracted (or the :all symbol) and a hash of the known file checksums in the archive.
    # Parameters:
    #   path: The full path to the archive being extracted/examined.
    #   see comment of method 'determine_files_to_extract' for :destination_folder and :files_to_check parameter information.
    #   see comment of method 'open' for remaining parameter information.
    def self.determine_files_to_extract(path, destination_folder, files_to_check: nil, options: {}, checksums: {}, mode: :idempotent, checksum_file: nil)
      archive = new(path, options: options, checksums: checksums, mode: mode, checksum_file: checksum_file)
      files_to_extract = archive.determine_files_to_extract(destination_folder, files_to_check: files_to_check)
      [files_to_extract, archive.checksums]
    end

    #
    # Description:
    #   Initializes the Archive.
    # Parameters:
    #   path: The path to the existing archive or where the archive will be created.
    #   see comment of method 'open' for remaining parameter information.
    def initialize(path, options: nil, checksums: nil, mode: nil, checksum_file: nil)
      @path = path
      archive_checksum = ::File.exist?(path) ? ::Digest::SHA256.file(path).hexdigest : 'does_not_exist'
      @checksum_path = checksum_file || "#{@cache_path}/checksums/#{::File.basename(path)}-#{archive_checksum}.txt"
      _assign_common_accessors(options: options, checksums: checksums, mode: mode)
      @options[:archive_type] ||= (::File.exist?(@path) ? detect_archive_type : :zip)
    end

    #
    # Description:
    #   Extract files from an archive
    # Returns:
    #   Array of 2 objects: String path to the checksum file and the hash of known checksums for archive files.
    # Parameters:
    #   path: The full path to the archive being extracted.
    #   destination_folder: The path where files will be extracted to.
    #   files_to_extract: An array of files to be extracted from the archive. Relative paths should be used. If omitted, extracts all contents of the archive.
    def extract(destination_folder, files_to_extract: nil)
      raise "Unable to extract #{@path}! The file does not exist!" unless ::File.file?(@path)
      @options[:overwrite] = @mode != :if_missing
      files_to_extract = determine_files_to_extract(destination_folder, files_to_check: files_to_extract)

      case @options[:archive_type]
      when :zip
        _extract_zip(destination_folder, files_to_extract)
      when :seven_zip
        _extract_seven_zip(destination_folder, files_to_extract)
      end

      EasyIO.logger.info "Extracting #{::File.basename(@path)} finished." unless @options[:silent]
      [@checksum_path, update_checksum_file]
    end

    #
    # Description:
    #   Add files to an existing archive or create one if it does not exist
    # Returns:
    #   Array of 2 objects: String path to the checksum file and the hash of known checksums for archive files.
    # Parameters:
    #   source_folder: The path from which relative archive paths will be derived.
    #   files_to_add: An array of files to be added to the archive. Relative or full paths accepted. If omitted, takes all files and folders in the source_folder.
    def add(source_folder, files_to_add: nil)
      files_to_add = determine_files_to_add(source_folder, files_to_check: files_to_add)
      FileUtils.mkdir_p(::File.dirname(@path)) unless ::File.directory?(::File.dirname(@path))

      case @options[:archive_type]
      when :zip
        _add_to_zip(source_folder, files_to_add)
      when :seven_zip
        _add_to_seven_zip(source_folder, files_to_add)
      else
        raise "':#{@options[:archive_type]}' is not a supported archive type!"
      end
      raise "Failed to create archive at #{@path}!" unless ::File.file?(@path)
      EasyIO.logger.info "Archiving to #{::File.basename(@path)} finished." unless @options[:silent]
      archive_checksums = @options[:sfx] ? @checksums : update_checksum_file # Don't update the checksum file yet if it's an SFX
      [@checksum_path, archive_checksums]
    end

    #
    # Description:
    #   Writes the archive's checksum file.
    # Returns:
    #   A hash of all known checksums for the archive.
    def update_checksum_file
      archive_path = @options[:sfx] ? @sfx_path : @path
      archive_checksum = ::Digest::SHA256.file(archive_path).hexdigest
      @checksums['archive_checksum'] = archive_checksum
      @checksum_path = "#{@cache_path}/checksums/#{::File.basename(archive_path)}-#{archive_checksum}.txt"
      FileUtils.mkdir_p(::File.dirname(checksum_path)) unless ::File.directory?(::File.dirname(checksum_path))
      ::File.write(checksum_path, @checksums.to_json)
      @checksums
    end

    # Description:
    #   Loads the known checksums for this archive from the checksum file.
    # Returns:
    #   A hash of all known checksums for the archive.
    def load_checksum_file
      @checksums = if ::File.exist?(@checksum_path) # Read the checksums file if it hasn't been read yet
                     file_content = ::File.read(@checksum_path)
                     JSON.parse(file_content)
                   else
                     {}
                   end
    end

    #
    # Description:
    #   Read a file inside a zip file without extracting it to the filesystem.
    #   Currently only supports :zip files
    # Returns:
    #   A string containing the file contents.
    # Parameters:
    #   relative_path: The path inside the archive for the file to view.
    def view_file(relative_path)
      raise 'Reading files inside a 7zip archive is not yet supported!' if @options[:archive_type] == :seven_zip
      EasyIO.logger.debug "Reading #{@path} // #{relative_path}..."
      ::Zip::File.open(@path).read(relative_path)
    end

    #
    # Description:
    #   Determines what files should be extracted based on the options and mode provided.
    # Returns:
    #   An array of files to be extracted (or the :all symbol).
    # Parameters:
    #   destination_folder: Where the files would be extracted to.
    #   files_to_check: Array of files intended to be extracted from an archive. Should be relative names/paths with or without asterisk wildcards or a regular expression.
    #     default: All files and folders in the archive.
    def determine_files_to_extract(destination_folder, files_to_check: nil)
      files_to_check ||= :all # defaults to :all files

      unless ::File.exist?(@path)
        # If the archive doesn't exist but checksums were provided, check for files to extract based off of checksums
        return @checksums.select { |entry_name, checksum| _extract_file?(entry_name, checksum == 'directory', destination_folder, files_to_check) }.keys unless @checksums.nil? || @checksums.empty?
        # If the archive doesn't exist and no checksums were found, extract all files_to_check
        return files_to_check
      end

      files_to_extract = case @options[:archive_type]
                         when :zip
                           _determine_zip_files_to_extract(destination_folder, files_to_check)
                         when :seven_zip
                           _determine_seven_zip_files_to_extract(destination_folder, files_to_check)
                         else
                           raise "':#{@options[:archive_type]}' is not a supported archive type!"
                         end

      EasyIO.logger.debug "Files to extract: #{files_to_extract.empty? ? 'none' : JSON.pretty_generate(files_to_extract)}"
      files_to_extract
    end

    #
    # Description:
    #   Determines what files should be added to an archive based on the options and mode provided.
    # Returns:
    #   An array of files to be added (or the :all symbol).
    # Parameters:
    #   source_folder: The filesystem directory where files are being added from.
    #   files_to_check: Array of files intended to be added to an archive. Can be exact names/paths or names/paths with wildcards (glob style).
    #     default: All files and folders under the source_folder.
    def determine_files_to_add(source_folder, files_to_check: nil)
      files_to_check ||= Dir.glob("#{source_folder}/**/*".tr('\\', '/')) if files_to_check.nil?
      files_to_add = []
      files_to_check.each do |target_search|
        files = Dir.glob(Zipr.prepend_source_folder(source_folder, target_search))
        files.each do |source_file|
          relative_path = Zipr.slice_source_folder(source_folder, source_file)
          exists_in_zip = !!@checksums[relative_path]
          next if @mode == :if_missing && exists_in_zip
          next if _excluded_file?(relative_path, exists_in_zip: exists_in_zip) || _excluded_file?(source_file, exists_in_zip: exists_in_zip)
          next if @mode == :idempotent && ::File.file?(source_file) && @checksums[relative_path] == Digest::SHA256.file(source_file).hexdigest
          next if ::File.directory?(source_file) && @checksums[relative_path] == 'directory'
          EasyIO.logger.debug "'#{relative_path}' would be added to archive..."
          files_to_add.push(source_file)
        end
      end
      files_to_add
    end

    #
    # Description:
    #   Detects what kind of archive the existing file is.
    # Returns:
    #   The type of archive detected.
    # Parameters:
    #   archive_types: (optional) The array of archive_types to try. Be default, tries all archive types.
    def detect_archive_type(archive_types = supported_archive_types)
      try_archive_type = archive_types.shift
      case try_archive_type
      when :zip
        ::Zip::File.open(@path) { |_archive_file| } # Test if the file can be opened as a zip file
      when :seven_zip
        SevenZipRuby::Reader.open_file(@path) { |_archive_file| } # Test if the file can be opened as a 7z file
      else
        raise "Archive type for #{try_archive_type} not implemented! Add it to Zipr::Archive.detect_archive_type definition."
      end
      @archive_type = try_archive_type
    rescue ::Zip::Error, StandardError
      remaining_message = archive_types.empty? ? 'No remaining types to attempt!' : "Attempting remaining types (#{archive_types.join(', ')})..."
      EasyIO.logger.debug "Archive does not appear to be a #{try_archive_type}. #{remaining_message}"
      return detect_archive_type(archive_types) unless archive_types.empty? # Try the remaining archive types unless none are left
      raise "Archive type for #{@path} could not be detected! Ensure it is in the list of supported types (#{supported_archive_types.join(', ')})."
    end

    #
    # Description:
    #   Defines all supported archive types.
    # Returns:
    #   Array of supported archive types.
    def supported_archive_types
      [:zip, :seven_zip]
    end

    #
    # Description:
    #   More readably access the archive_type option.
    # Returns:
    #   A symbol representing the archive type of the instance.
    def archive_type
      @options[:archive_type]
    end

    private

    def _extract_zip(destination_folder, files_to_extract)
      ::Zip::File.open(@path) do |archive_items|
        EasyIO.logger.info "Extracting to #{destination_folder}..." unless @options[:silent]
        archive_items.each do |archive_item|
          extract_item_lambda = ->(destination_path) { archive_item.extract(destination_path) { :overwrite } }
          _extract_item(destination_folder, files_to_extract, archive_item.name, archive_item.ftype == :directory, extract_item_lambda)
        end
      end
    end

    def _extract_seven_zip(destination_folder, files_to_extract)
      SevenZipRuby::Reader.open_file(@path, @options) do |seven_zip_archive|
        EasyIO.logger.info "Extracting to #{destination_folder}..." unless @options[:silent]
        seven_zip_archive.entries.each do |archive_item|
          extract_item_lambda = ->(_destination_path) { seven_zip_archive.extract(archive_item.index, destination_folder) }
          _extract_item(destination_folder, files_to_extract, archive_item.path, archive_item.directory?, extract_item_lambda)
        end
      end
    end

    def _extract_item(destination_folder, files_to_extract, archive_entry_name, is_directory, extract_item_lambda)
      destination_path = ::File.join(destination_folder.tr('\\', '/'), archive_entry_name)
      return unless files_to_extract.nil? || files_to_extract == :all || files_to_extract.include?(archive_entry_name)
      if ::File.exist?(destination_path)
        return unless @options[:overwrite] # skip extract if the file exists and overwrite is false
        FileUtils.rm(destination_path)
      end
      if is_directory
        FileUtils.mkdir_p(destination_path)
        @checksums[archive_entry_name.tr('\\', '/')] = 'directory'
        return
      end

      full_destination_folder = ::File.dirname(destination_path)
      FileUtils.mkdir_p(full_destination_folder) unless ::File.directory?(full_destination_folder)
      EasyIO.logger.info "Extracting #{archive_entry_name}..." unless @options[:silent]
      extract_item_lambda.call(destination_path)
      @checksums[archive_entry_name.tr('\\', '/')] = Digest::SHA256.file(destination_path).hexdigest
    end

    def _add_to_zip(source_folder, files_to_add)
      if files_to_add.empty?
        EasyIO.logger.info 'Skipping adding of files to archive. No files have changed.'
        return
      end
      ::Zip::File.open(@path, ::Zip::File::CREATE) do |zip_archive|
        EasyIO.logger.info "Adding to #{@path}..." unless @options[:silent]
        files_to_add.each do |source_file|
          add_directory_lambda = ->(relative_path) { zip_archive.mkdir(relative_path) }
          add_file_lambda = ->(relative_path) { zip_archive.add(relative_path, source_file) { :overwrite } }
          _add_item(source_file, add_directory_lambda, add_file_lambda, source_folder)
        end
      end
    end

    def _add_to_seven_zip(source_folder, files_to_add)
      if files_to_add.empty?
        EasyIO.logger.info 'Skipping adding of files to archive. No files have changed.'
        return
      end
      params = @options.reject { |k, _v| k == :sfx }
      SevenZipRuby::Writer.open_file("#{@path}.tmp", params) do |seven_zip_archive|
        EasyIO.logger.info "Adding to #{@path}..." unless @options[:silent]
        _keep_unchanged_seven_zip_files(seven_zip_archive, source_folder, files_to_add) unless @mode == :overwrite
        files_to_add.each do |source_file|
          add_directory_lambda = ->(relative_path) { seven_zip_archive.mkdir(relative_path) }
          add_file_lambda = ->(relative_path) { seven_zip_archive.add_file(source_file, as: relative_path) }
          _add_item(source_file, add_directory_lambda, add_file_lambda, source_folder)
        end
      end
      FileUtils.mv("#{@path}.tmp", @path, force: true)
    end

    def _keep_unchanged_seven_zip_files(seven_zip_archive, source_folder, files_to_add)
      existing_archive = @options[:sfx] ? @sfx_path : @path
      # TODO: Ensure it's not duplicating kept items
      if ::File.exist?(existing_archive) # If the archive already exists, save it's existing content first
        EasyIO.logger.debug "Reading existing 7z archive #{existing_archive}..."
        files_to_add_relative_paths = files_to_add.map { |file| Zipr.slice_source_folder(source_folder, file) }
        SevenZipRuby::Reader.open_file(existing_archive, @options) do |existing_seven_zip_archive|
          items_to_keep = existing_seven_zip_archive.entries.reject do |archive_item| # Don't keep (reject) entries that we'll be adding later
            reject_entry = files_to_add_relative_paths.include?(archive_item.path)
            @checksums.delete(archive_item.path) if reject_entry # Delete from @checksums if it's being rejected
            reject_entry
          end
          items_to_keep.each do |archive_item|
            EasyIO.logger.debug "Keeping #{archive_item.path}..."
            if archive_item.directory?
              seven_zip_archive.mkdir(archive_item.path)
              next
            end
            seven_zip_archive.add_data(existing_seven_zip_archive.extract_data(archive_item.index), archive_item.path)
          end
        end
      end
    end

    def _add_item(source_file, add_directory_lambda, add_file_lambda, source_folder)
      relative_path = source_file.tr('\\', '/')
      relative_path.slice!(source_folder.tr('\\', '/'))
      relative_path = relative_path.reverse.chomp('/').reverse
      EasyIO.logger.info "Adding #{relative_path}..." unless @options[:silent]
      if ::File.directory?(source_file)
        add_directory_lambda.call(relative_path)
        archive_item_checksum = 'directory'
      else
        add_file_lambda.call(relative_path)
        archive_item_checksum = Digest::SHA256.file(source_file).hexdigest
      end

      @checksums[relative_path] = archive_item_checksum
    end

    def _determine_zip_files_to_extract(destination_folder, files_to_check)
      files_to_extract = []
      ::Zip::File.open(@path) do |archive_items|
        files_to_extract = archive_items.select { |archive_item| _extract_file?(archive_item.name, archive_item.ftype == :directory, destination_folder, files_to_check) }.map(&:name)
      end
      files_to_extract
    end

    def _determine_seven_zip_files_to_extract(destination_folder, files_to_check)
      files_to_extract = []
      SevenZipRuby::Reader.open_file(@path, @options) do |seven_zip_archive|
        files_to_extract = seven_zip_archive.entries.select { |archive_item| _extract_file?(archive_item.path, archive_item.directory?, destination_folder, files_to_check) }.map(&:path)
      end
      files_to_extract
    end

    def _extract_file?(archive_entry_name, is_a_directory, destination_folder, files_to_check)
      destination_path = "#{destination_folder}/#{archive_entry_name}"
      return false unless files_to_check == :all || files_to_check.include?(archive_entry_name) # Make sure the file is in the whitelist if it was provided
      return false if ::File.directory?(destination_path) && is_a_directory # Archive item is a directory and the destination directory exists
      return false if @mode == :if_missing && ::File.exist?(destination_path) # File exists and we're not overwriting existing files due to the mode
      return false if _excluded_file?(archive_entry_name, destination_path: destination_path) # File is excluded in :options
      return false if @mode == :idempotent && ::File.file?(destination_path) && ::Digest::SHA256.file(destination_path).hexdigest == @checksums[archive_entry_name] # Checksum of destination file matches checksum in archive
      true
    end

    def _excluded_file?(file_path, destination_path: '', exists_in_zip: false)
      @options[:exclude_files] ||= []
      @options[:exclude_unless_missing] ||= []
      @options[:exclude_unless_archive_changed] ||= []
      return true if @options[:exclude_files].any? { |e| file_path.tr('\\', '/') =~ _convert_backslashes_and_cast_to_regexp(e) }
      return true if ::File.exist?(destination_path) && @options[:exclude_unless_missing].any? { |e| file_path.tr('\\', '/') =~ _convert_backslashes_and_cast_to_regexp(e) }
      return true if exists_in_zip && @options[:exclude_unless_missing].any? { |e| file_path.tr('\\', '/') =~ _convert_backslashes_and_cast_to_regexp(e) }
      return true if !@archive_changed && ::File.exist?(destination_path) && @options[:exclude_unless_archive_changed].any? { |e| file_path.tr('\\', '/') =~ _convert_backslashes_and_cast_to_regexp(e) }
      false
    end

    def _convert_backslashes_and_cast_to_regexp(path)
      return path if path.is_a?(Regexp) # If it's already a regexp, leave it alone
      path = path.tr('\\', '/')
      /^#{Zipr.wildcard_to_regexp(path)}$/i
    end

    def _assign_common_accessors(options: nil, checksums: nil, mode: nil)
      _assign_checksums(checksums)
      @options = options || @options || {}
      @mode = mode || @mode || :idempotent
      @archive_changed = ::File.exist?(@path) && @checksums['archive_checksum'] != Digest::SHA256.file(@path).hexdigest
    end

    def _assign_checksums(checksums)
      return load_checksum_file if checksums.nil? || checksums.empty? # Read the checksums file if it hasn't been read yet
      @checksums = checksums || {}
    end

    # TODO: Add delete method to remove something from an archive
  end
end
