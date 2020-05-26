module Zipr
  class SFX < Zipr::Archive
    attr_accessor :info_file
    attr_reader :sfx_path
    attr_reader :sfx_cache_path

    #
    # Description:
    #   Create an SFX archive in one line. No additional IO handling necessary.
    # Returns:
    #   Array of 2 objects: String path to the checksum file and the hash of known checksums for archive files.
    # Parameters:
    #   path: The full path to the SFX archive being created.
    #   see comment of method 'create' for :source_folder, :files_to_add, and :info_hash parameter information.
    #   see comment of method 'initialize' for :temp_subfolder parameter information.
    #   see comment of Zipr::Archive.open for remaining parameter information.
    def self.create(path, source_folder, files_to_add: nil, info_hash: nil, temp_subfolder: nil, options: nil, checksums: nil, mode: nil)
      sfx_archive = new(path, temp_subfolder: temp_subfolder, options: options, checksums: checksums, mode: mode) # Create new SFX instance
      sfx_archive.create(source_folder, files_to_add: files_to_add, info_hash: info_hash)
    end

    #
    # Description:
    #   Initializes the Archive.
    # Parameters:
    #   path: The path to the existing archive or where the archive will be created.
    #   see comment of method 'open' for remaining parameter information.
    def initialize(path, temp_subfolder: nil, checksum_file: nil, options: nil, checksums: nil, mode: nil)
      basename = ::File.basename(path).sub(/\.[^\.]+$/, '')
      mode ||= :overwrite
      temp_subfolder ||= basename
      invalid_basename = basename.empty? || ::File.directory?(path)
      if temp_subfolder.empty? || invalid_basename
        @skip_cleanup = true
        raise "SFX path was not complete! Ensure the path includes a filename.\n  path: #{path}" if invalid_basename
        raise 'Subfolder provided to initialize Zipr::SFX archive was empty!'
      end

      @sfx_path = path
      @sfx_cache_path = "#{Zipr.config['paths']['cache']}/zipr/SFX/#{temp_subfolder}"
      @path = "#{@sfx_cache_path}/#{basename}.sfx.7z" # Inherited class uses @path for the 7z file
      path_checksum = ::File.exist?(path) ? ::Digest::SHA256.file(path).hexdigest : 'does_not_exist'
      @checksum_path = checksum_file || "#{@cache_path}/checksums/#{::File.basename(path)}-#{path_checksum}.txt"
      _assign_common_accessors(options: options, checksums: checksums, mode: mode)
      @options[:sfx] = true
      @options[:archive_type] = :seven_zip
    end

    # Description:
    #   Generate an info file for the SFX used for executing a command/file after extraction
    # Parameters:
    #   info_hash: (optional)
    #     Title: Title for messages
    #     BeginPrompt: Message to prompt user before launching RunProgram or ExecuteFile
    #     Progress: Value can be "yes" or "no". Default value is "yes".
    #     RunProgram: Command for executing. Default value is "setup.exe". Use double backslashes for directories.
    #     InstallPath: Directory where files will be extracted and run from. Default value is ".\\" - Ensure the directory ends with a double slash.
    #     Delete: Directory to delete after launched executable exits. Use double backslashes.
    #     ExecuteFile: Name of file for executing
    #     ExecuteParameters: Parameters for "ExecuteFile"
    def generate_info_file(info_hash = nil)
      info_hash ||= {}
      @info_file = <<-EOS.strip
        ;!@Install@!UTF-8!
        #{info_hash.map { |k, v| "#{k}=\"#{v}\"" }.join("\n")}
        ;!@InstallEnd@!
      EOS
      ::File.open("#{sfx_cache_path}/sfx_info.txt", 'wb:UTF-8') { |file| file.write(@info_file) }
    end

    #
    # Description:
    #   Create the SFX package
    # Returns:
    #   Array of 2 objects: String path to the checksum file and the hash of known checksums for archive files.
    # Parameters:
    #   source_folder: The path from which relative archive paths will be derived.
    #   files_to_add: An array of files to be added to the SFX archive. Relative or full paths accepted. Wildcards accepted. If omitted, takes all files and folders in the source_folder.
    #   info_hash: (optional) A hash containing the installer config info file. See comments for method 'generate_info_file' for more information.
    def create(source_folder, files_to_add: nil, info_hash: nil)
      changed_files = determine_files_to_add(source_folder, files_to_check: files_to_add)
      if changed_files.empty? && ::File.exist?(@sfx_path)
        EasyIO.logger.info 'No files in the SFX have changed. Skipping SFX creation.'
        return [@checksum_path, @checksums]
      end
      EasyIO.logger.info "Creating SFX archive: #{sfx_path}"
      add(source_folder, files_to_add: files_to_add)
      use_info_file = !(info_hash.nil? || info_hash.empty?)
      generate_info_file(info_hash) if use_info_file
      sfx_module = "#{__dir__}/#{use_info_file ? '7zsd_All.sfx' : '7zS2.sfx'}"
      sfx_components = [sfx_module] # Start with the module
      sfx_components.push("#{sfx_cache_path}/sfx_info.txt") if ::File.exist?("#{sfx_cache_path}/sfx_info.txt") # Add the info file if it exists
      sfx_components.push(@path) # Add the temporary .7z archive
      ::File.open(sfx_path, 'wb') do |sfx_archive|
        sfx_components.each do |file|
          EasyIO.logger.debug "Adding #{file} to SFX"
          sfx_archive.write(::File.open(file, 'rb').read)
        end
      end
      EasyIO.logger.info 'SFX created successfully.'
      [@checksum_path, update_checksum_file]
    ensure
      cleanup unless @skip_cleanup
    end

    #
    # Description:
    #   Deletes temporary files/folders used while creating this SFX
    def cleanup
      FileUtils.rm_rf(sfx_cache_path)
    end
  end
end
