require 'cloud_controller/dependency_locator'

module VCAP::CloudController
  module Jobs
    module Runtime
      class ExternalPacker < VCAP::CloudController::Jobs::CCJob
        attr_accessor :app_guid, :uploaded_compressed_path, :fingerprints

        def initialize(app_guid, uploaded_compressed_path, fingerprints)
          @app_guid = app_guid
          @uploaded_compressed_path = uploaded_compressed_path
          @fingerprints = fingerprints
        end

        def perform
          logger.info("Packing the app bits for app '#{app_guid}' - Using BITS SERVICE")

          app = VCAP::CloudController::App.find(guid: app_guid)

          if app.nil?
            logger.error("App not found: #{app_guid}")
            return
          end

          package_blobstore     = CloudController::DependencyLocator.instance.package_blobstore
          bits_client           = CloudController::DependencyLocator.instance.bits_client

          entries_response = bits_client.upload_entries(uploaded_compressed_path)
          receipt = JSON.parse(entries_response.body)
          fingerprints.concat(receipt)

          package_response = bits_client.bundles(fingerprints.to_json)
          package = Tempfile.new('package.zip')
          package.binmode
          package.write(package_response.body)
          package.close
          package_blobstore.cp_to_blobstore(package.path, app_guid)
        rescue => e
          app.mark_as_failed_to_stage
          raise Errors::ApiError.new_from_details('BitsServiceError', e.message) if e.is_a?(BitsClient::Errors::Error)
          raise
        end

        def job_name_in_configuration
          :external_packer
        end

        def max_attempts
          1
        end

        def logger
          @logger ||= Steno.logger('cc.background')
        end
      end
    end
  end
end
