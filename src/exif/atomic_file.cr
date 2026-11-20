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

    private def resolve(path : Path | String) : Path
      Path[File.symlink?(path) ? File.realpath(path) : path]
    end

    private def replace(path : Path, bytes : Bytes) : Nil
      tempfile = File.tempname(".#{path.basename}", ".tmp", dir: path.dirname)
      begin
        if info = File.info?(path)
          # Readable only by the owner until it gets the owner, group and permissions
          # of the replaced file, which might not be readable by others (i.e. a private photo)
          File.write(tempfile, bytes, perm: File::Permissions.new(0o600))
          keep_ownership(tempfile, path, info)
          File.chmod(tempfile, info.permissions)
        else
          File.write(tempfile, bytes)
        end
        File.rename(tempfile, path)
      ensure
        File.delete?(tempfile)
      end
    end

    # Gives the *tempfile* the owner and group of the file at *path*, described by *info*.
    private def keep_ownership(tempfile : String, path : Path, info : File::Info) : Nil
      temp_info = File.info(tempfile)
      return if temp_info.owner_id == info.owner_id && temp_info.group_id == info.group_id

      File.chown(tempfile, info.owner_id.to_i, info.group_id.to_i)
    rescue ex : File::Error
      # Otherwise its permissions would apply to another owner or group
      raise Error.new("Cannot keep the owner and group of #{path}, leaving it intact", cause: ex)
    end
  end
end
