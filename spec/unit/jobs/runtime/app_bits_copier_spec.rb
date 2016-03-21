require 'spec_helper'

module VCAP::CloudController
  module Jobs::Runtime
    describe AppBitsCopier do
      let(:src_app) { VCAP::CloudController::AppFactory.make }
      let(:dest_app) { VCAP::CloudController::AppFactory.make }
      let(:compressed_path) { File.expand_path('../../../fixtures/good.zip', File.dirname(__FILE__)) }
      let(:local_tmp_dir) { Dir.mktmpdir }
      let(:blobstore_dir) { Dir.mktmpdir }
      let(:app_event_repository) { double(:app_event_repository, record_src_copy_bits: nil, record_dest_copy_bits: nil) }
      let(:package_blobstore) do
        CloudController::Blobstore::FogClient.new({ provider: 'Local', local_root: blobstore_dir }, 'package')
      end
      let(:user) { User.make }
      let(:email) { 'some-user@example.com' }

      subject(:job) do
        AppBitsCopier.new(src_app, dest_app, app_event_repository, user, email)
      end

      it { is_expected.to be_a_valid_job }

      before do
        Fog.unmock!
      end

      after do
        Fog.mock!
        FileUtils.remove_entry_secure local_tmp_dir
        FileUtils.remove_entry_secure blobstore_dir
      end

      describe '#perform' do
        before do
          package_blobstore.cp_to_blobstore(compressed_path, src_app.guid)
          allow(CloudController::DependencyLocator.instance).to receive(:package_blobstore).and_return(package_blobstore)
        end

        it 'creates blob stores' do
          expect(CloudController::DependencyLocator.instance).to receive(:package_blobstore).and_return(package_blobstore)
          job.perform
        end

        it 'copies the source package zip to the package blob store for the destination app' do
          job.perform
          expect(package_blobstore.exists?(dest_app.guid)).to be true
        end

        it 'uploads the package zip to the package blob store' do
          job.perform
          package_blobstore.download_from_blobstore(dest_app.guid, File.join(local_tmp_dir, 'package.zip'))
          expect(`unzip -l #{local_tmp_dir}/package.zip`).to include('bye')
        end

        it 'changes the package hash in the destination app' do
          expect {
            job.perform
          }.to change {
            dest_app.refresh.package_hash
          }
        end

        it 'creates a copy_bits audit event for source app' do
          job.perform
          expect(app_event_repository).to have_received(:record_src_copy_bits).with(dest_app, src_app, user.guid, email)
        end

        it 'creates a copy_bits audit event for destination app' do
          job.perform
          expect(app_event_repository).to have_received(:record_dest_copy_bits).with(dest_app, src_app, user.guid, email)
        end

        context 'when bits service is enabled' do
          let(:bits_client) { double(BitsClient) }
          let(:dest_package_guid) { 'some-guid' }
          let(:duplicate_response) { double(Net::HTTPCreated, body: { guid: dest_package_guid }.to_json) }

          before do
            allow_any_instance_of(CloudController::DependencyLocator).to receive(:use_bits_service).and_return(true)
            allow_any_instance_of(CloudController::DependencyLocator).to receive(:bits_client).and_return(bits_client)
          end

          context 'and duplicate succeeds' do
            before do
              allow(bits_client).to receive(:duplicate_package).and_return(duplicate_response)
            end

            it 'duplicates the package' do
              expect(bits_client).to receive(:duplicate_package).with(src_app.package_hash).and_return(duplicate_response)
              job.perform
            end

            it 'sets the package_hash on the destionation app' do
              job.perform
              expect(dest_app.package_hash).to eq(dest_package_guid)
            end

            it 'creates a copy_bits audit event for source app' do
              job.perform
              expect(app_event_repository).to have_received(:record_src_copy_bits).with(dest_app, src_app, user.guid, email)
            end

            it 'creates a copy_bits audit event for destination app' do
              job.perform
              expect(app_event_repository).to have_received(:record_dest_copy_bits).with(dest_app, src_app, user.guid, email)
            end
          end

          context 'and duplicate fails' do
            let(:not_found_error) { BitsClient::Errors::Error.new('something') }

            before do
              allow(bits_client).to receive(:duplicate_package).and_raise(not_found_error)
            end

            it 'raises error' do
              expect(bits_client).to receive(:duplicate_package).with(src_app.package_hash)
              expect { job.perform }.to raise_error(not_found_error)
            end
          end
        end
      end

      describe '#job_name_in_configuration' do
        it 'returns the correct name' do
          expect(job.job_name_in_configuration).to equal(:app_bits_copier)
        end
      end
    end
  end
end
