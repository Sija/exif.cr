module EXIF
  # :nodoc:
  #
  # Replaces files atomically, keeping their permissions, owner and group.
  module AtomicFile
    extend self

    # Replaces the file at *path* with the bytes returned by the block,
    # which is given its current contents (see `.write`).
    def update(path : Path | String, & : Bytes -> Bytes) : Nil
      # Resolved once, so that the same file is read and replaced
      path = resolve(path)
      replace(path, yield File.read(path).to_slice)
    end

    # Writes the *bytes* to *path*.
    #
    # The bytes are written to a temporary file first, which then replaces
    # *path* atomically, so that *path* is never left partially written.
    # The permissions, owner and group of the replaced file are kept, raising
    # `Error` (and leaving it intact) if they can't be. Symbolic links are followed.
    def write(path : Path | String, bytes : Bytes) : Nil
      replace(resolve(path), bytes)
    end

    # Maximum number of symbolic links followed by `#resolve`.
    MAX_SYMLINKS = 40

    # Follows symbolic links at *path*, including dangling ones (pointing to a file
    # yet to be created), unlike `File.realpath`.
    private def resolve(path : Path | String) : Path
      path = Path[path]
      MAX_SYMLINKS.times do
        return path unless File.symlink?(path)

        target = Path[File.readlink(path)]
        path = target.absolute? ? target : path.parent / target
      end
      raise File::Error.new("Too many levels of symbolic links", file: path.to_s)
    end

    private def replace(path : Path, bytes : Bytes) : Nil
      info = File.info?(path)
      # Readable only by the owner until it gets the owner, group and permissions
      # of the replaced file, which might not be readable by others (i.e. a private photo)
      perm = info ? File::Permissions.new(0o600) : File::DEFAULT_CREATE_PERMISSIONS
      tempfile, file = create_tempfile(path, perm)
      begin
        begin
          file.write(bytes)
          # Flushed to the disk before the rename, so that a crash can't leave an empty file behind
          file.fsync
        ensure
          file.close
        end
        if info
          keep_ownership(tempfile, path, info)
          File.chmod(tempfile, info.permissions)
        end
        File.rename(tempfile, path)
      ensure
        File.delete?(tempfile)
      end
    end

    # Creates a temporary file next to *path* with the given *perm* (minus the umask).
    #
    # NOTE: Created exclusively, so that no file or symbolic link
    # planted in its place (i.e. in a shared directory) gets written to.
    private def create_tempfile(path : Path, perm : File::Permissions) : {String, IO::FileDescriptor}
      flags = LibC::O_WRONLY | LibC::O_CREAT | LibC::O_EXCL | LibC::O_CLOEXEC
      # Shortened, so that the name doesn't exceed the length limit (255 bytes) for long file names
      prefix = ".#{path.basename[0, 32]}"
      100.times do
        tempfile = File.tempname(prefix, ".tmp", dir: path.dirname)
        fd = LibC.open(tempfile, flags, perm.value.to_i32)
        return {tempfile, IO::FileDescriptor.new(handle: fd)} unless fd < 0
        next if Errno.value.eexist?

        raise File::Error.from_errno("Error creating temporary file", file: tempfile)
      end
      raise File::Error.new("Cannot create a unique temporary file", file: path.to_s)
    end

    # Gives the *tempfile* the owner and group of the file at *path*, described by *info*.
    #
    # Raises `Error` if the owner can't be kept, or the group can't be kept
    # while it has any permissions (which would apply to another group otherwise).
    private def keep_ownership(tempfile : String, path : Path, info : File::Info) : Nil
      temp_info = File.info(tempfile)
      owner = info.owner_id unless temp_info.owner_id == info.owner_id
      group = info.group_id unless temp_info.group_id == info.group_id
      return unless owner || group

      begin
        File.chown(tempfile, (owner || -1).to_i, (group || -1).to_i)
      rescue ex : File::Error
        # Without any permissions for its group, the file is no more
        # accessible to the other group than it was to the original one
        unless owner.nil? && (info.permissions.value & 0o070).zero?
          raise Error.new("Cannot keep the owner and group of #{path}, leaving it intact", cause: ex)
        end
      end
    end
  end
end
