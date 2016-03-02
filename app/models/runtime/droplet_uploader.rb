module CloudController
  class DropletUploader
    def initialize(app, blobstore)
      @app = app
      @blobstore = blobstore
    end

    def upload(source_path, droplets_to_keep=2)
      if use_bits_service?
        digest = upload_to_bits_service(source_path)
      else
        digest = Digester.new.digest_path(source_path)
        blobstore.cp_to_blobstore(
          source_path,
          VCAP::CloudController::Droplet.droplet_key(app.guid, digest)
        )
      end
      app.add_new_droplet(digest)

      current_droplet_size = app.droplets_dataset.count

      if current_droplet_size > droplets_to_keep
        app.droplets_dataset.
          order_by(Sequel.asc(:created_at)).
          limit(current_droplet_size - droplets_to_keep).destroy
      end

      app.save
    end

    private

    def upload_to_bits_service(file_path)
      response = bits_client.upload_droplet(file_path)
      JSON.parse(response.body)['guid']
    rescue BitsClient::Errors::Error => e
      raise VCAP::Errors::ApiError.new_from_details('BitsServiceError', e.message)
    end

    def use_bits_service?
      !!bits_client
    end

    def bits_client
      CloudController::DependencyLocator.instance.bits_client
    end

    attr_reader :blobstore, :app
  end
end
