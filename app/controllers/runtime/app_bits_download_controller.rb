module VCAP::CloudController
  class AppBitsDownloadController < RestController::ModelController
    def self.dependencies
      [:blob_sender, :package_blobstore, :missing_blob_handler]
    end

    path_base 'apps'
    model_class_name :App

    get "#{path_guid}/download", :download
    def download(guid)
      app = find_guid_and_validate_access(:read, guid)

      if use_bits_service
        raise Errors::ApiError.new_from_details('AppPackageNotFound', guid) unless app.package_hash
        url = bits_client.download_url(:packages, app.package_hash)

        return [200, { 'X-Accel-Redirect' => "/bits_redirect/#{url}" }, nil] if @config[:nginx][:use_nginx]
        return [HTTP::FOUND, { 'Location' => url }, nil]
      end

      blob = @blobstore.blob(guid)

      if blob.nil?
        Loggregator.emit_error(guid, "Could not find package for #{guid}")
        logger.error "could not find package for #{guid}"
        raise Errors::ApiError.new_from_details('AppPackageNotFound', guid)
      end

      if @blobstore.local?
        @blob_sender.send_blob(guid, 'AppPackage', blob, self)
      else
        return [HTTP::FOUND, { 'Location' => blob.public_download_url }, nil]
      end
    end

    private

    def inject_dependencies(dependencies)
      @blob_sender = dependencies.fetch(:blob_sender)
      @blobstore = dependencies.fetch(:package_blobstore)
    end

    def bits_client
      @bits_client ||= CloudController::DependencyLocator.instance.bits_client
    end

    def use_bits_service
      !!bits_client
    end
  end
end
