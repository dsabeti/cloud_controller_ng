require 'spec_helper'

module VCAP::CloudController
  module Jobs::Runtime
    describe BlobstoreDelete do
      let(:key) { 'key' }

      let(:blobstore_type) { :droplet_blobstore }

      subject(:job) do
        BlobstoreDelete.new(key, blobstore_type)
      end

      let!(:blobstore) do
        CloudController::DependencyLocator.instance.droplet_blobstore
      end

      let(:tmpfile) { Tempfile.new('') }

      before do
        allow(CloudController::DependencyLocator.instance).to receive(blobstore_type).and_return(blobstore)
        blobstore.cp_to_blobstore(tmpfile.path, key)
      end

      after do
        tmpfile.delete
      end

      it { is_expected.to be_a_valid_job }

      context 'when no attributes defined' do
        it 'deletes the blob' do
          expect {
            job.perform
          }.to change {
            blobstore.exists?(key)
          }.from(true).to(false)
        end
      end

      context 'when attributes match' do
        it 'deletes the blob' do
          blob = blobstore.blob(key)
          job.attributes = blob.attributes

          expect {
            job.perform
          }.to change {
            blobstore.exists?(key)
          }.from(true).to(false)
        end
      end

      context 'when attributes do not match' do
        let(:job) do
          BlobstoreDelete.new(key, :droplet_blobstore, { 'mis' => 'match' })
        end

        it 'does not delete the blob' do
          expect {
            job.perform
          }.to_not change {
            blobstore.exists?(key)
          }
        end
      end

      context 'when the blob does not exist' do
        it 'does not invoke delete' do
          expect(blobstore).to receive(:blob).and_return(nil)
          job.perform
        end
      end

      it 'knows its job name' do
        expect(job.job_name_in_configuration).to equal(:blobstore_delete)
      end

      context 'when the bits service is being used' do
        let(:bits_client) { double(BitsClient, delete_buildpack: nil) }

        let(:blobstore_type) { :buildpack_blobstore }

        let(:bits_guid) { 'guid' }

        let(:buildpack) { double(Buildpack, key: key, bits_guid: bits_guid) }

        before(:each) do
          allow(CloudController::DependencyLocator.instance).to receive(:bits_client).and_return(bits_client)
          allow(Buildpack).to receive(:find).with(key: key).and_return(buildpack)
        end

        it 'deletes the blob from the regular blobstore' do
          expect {
            job.perform
          }.to change {
            blobstore.exists?(key)
          }.from(true).to(false)
        end

        it 'deletes the blob from the bits service' do
          expect(bits_client).to receive(:delete_buildpack).with(bits_guid)
          job.perform
        end

        context 'and the blobstore is not a buildpack blobstore' do
          let(:blobstore_type) { :droplet_blobstore }

          it 'does not attempt to delete a buildpack from the bits service' do
            expect(Buildpack).to_not receive(:find)
            expect(bits_client).to_not receive(:delete_buildpack)
            job.perform
          end
        end
      end
    end
  end
end
