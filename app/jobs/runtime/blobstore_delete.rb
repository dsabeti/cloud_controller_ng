module VCAP::CloudController
  module Jobs
    module Runtime
      class BlobstoreDelete < VCAP::CloudController::Jobs::CCJob
        attr_accessor :key, :blobstore_name, :attributes

        def initialize(key, blobstore_name, attributes=nil)
          @key = key
          @blobstore_name = blobstore_name
          @attributes = attributes
        end

        def perform
          logger = Steno.logger('cc.background')
          logger.info("Attempting delete of '#{key}' from blobstore '#{blobstore_name}'")

          if buildpack_blobstore? && bits_client
            buildpack = Buildpack.find(key: key)
            bits_client.delete_buildpack(buildpack.key)
            return
          end

          blobstore = CloudController::DependencyLocator.instance.public_send(blobstore_name)
          blob = blobstore.blob(key)
          if blob && same_blob(blob)
            logger.info("Deleting '#{key}' from blobstore '#{blobstore_name}'")
            blobstore.delete_blob(blob)
          end
        end

        def buildpack_blobstore?
          @blobstore_name == :buildpack_blobstore
        end

        def bits_client
          @bits_client ||= CloudController::DependencyLocator.instance.bits_client
        end

        def job_name_in_configuration
          :blobstore_delete
        end

        def max_attempts
          3
        end

        private

        def same_blob(blob)
          return true if attributes.nil?
          blob.attributes(*attributes.keys) == attributes
        end
      end
    end
  end
end
