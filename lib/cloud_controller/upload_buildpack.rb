module VCAP::CloudController
  class UploadBuildpack
    attr_reader :buildpack_blobstore

    def initialize(blobstore)
      @buildpack_blobstore = blobstore
    end

    def upload_buildpack(buildpack, bits_file_path, new_filename)
      return false if buildpack.locked

      new_key = nil
      if use_bits_service?
        new_key = upload_to_bits_service(buildpack, bits_file_path, new_filename)
      else
        sha1 = Digester.new.digest_path(bits_file_path)
        new_key = "#{buildpack.guid}_#{sha1}"
        missing_bits = buildpack.key && !buildpack_blobstore.exists?(buildpack.key)

        return false if !new_bits?(buildpack, new_key) && !new_filename?(buildpack, new_filename) && !missing_bits

        # replace blob if new
        if missing_bits || new_bits?(buildpack, new_key)
          buildpack_blobstore.cp_to_blobstore(bits_file_path, new_key)
        end
      end

      begin
        process_bits(buildpack, new_key, new_filename, missing_bits)
      rescue Sequel::Error
        BuildpackBitsDelete.delete_when_safe(new_key, 0)
        return false
      end

      true
    end

    private

    def delete_bits?(missing_bits, old_buildpack_key, buildpack)
      !missing_bits && old_buildpack_key && new_bits?(buildpack, old_buildpack_key)
    end

    def process_bits(buildpack, new_key, new_filename, missing_bits)
      old_buildpack_key = nil

      Buildpack.db.transaction do
        buildpack.lock!
        old_buildpack_key = buildpack.key
        buildpack.update_from_hash(key: new_key, filename: new_filename)
      end

      if delete_bits?(missing_bits, old_buildpack_key, buildpack)
        staging_timeout = VCAP::CloudController::Config.config[:staging][:timeout_in_seconds]
        BuildpackBitsDelete.delete_when_safe(old_buildpack_key, staging_timeout)
      end
    end

    def upload_to_bits_service(buildpack, file_path, file_name)
      response = bits_client.upload_buildpack(file_path, file_name)
      raise Errors::ApiError.new_from_details('BitsServiceInvalidResponse', 'failed to upload buildpack') if response.code.to_i != 201
      JSON.parse(response.body)['guid']
    end

    def use_bits_service?
      !!bits_client
    end

    def bits_client
      CloudController::DependencyLocator.instance.bits_client
    end

    def new_bits?(buildpack, key)
      buildpack.key != key
    end

    def new_filename?(buildpack, filename)
      buildpack.filename != filename
    end
  end
end
