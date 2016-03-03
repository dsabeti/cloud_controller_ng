require 'spec_helper'

module VCAP::CloudController
  module Jobs::Runtime
    describe ExternalPacker do
      let(:uploaded_path) { 'tmp/uploaded.zip' }
      let(:app) { App.make }
      let(:app_guid) { app.guid }
      let(:package_blobstore) { double(:package_blobstore) }
      let(:receipt) { [{ 'sha1' => '12345', 'fn' => 'app.rb' }] }
      let(:fingerprints) { [{ 'sha1' => 'abcde', 'fn' => 'lib.rb' }] }

      subject(:job) do
        ExternalPacker.new(app_guid, uploaded_path, fingerprints)
      end

      let(:bits_service_config) do
        {
          bits_service: {
            enabled: true,
            endpoint: 'https://bits-service.example.com'
          }
        }
      end

      before do
        TestConfig.override(bits_service_config)
      end

      it { is_expected.to be_a_valid_job }

      describe '#perform' do
        before do
          allow_any_instance_of(BitsClient).to receive(:upload_entries).
            and_return(double(:response, code: 201, body: receipt.to_json))
          allow_any_instance_of(BitsClient).to receive(:bundles).
            and_return(double(:response, code: 200, body: 'contents'))
          allow(CloudController::DependencyLocator.instance).to receive(:package_blobstore).
            and_return(package_blobstore)
          allow(package_blobstore).to receive(:cp_to_blobstore)
        end

        it 'uses the bits_client to upload the zip file' do
          expect_any_instance_of(BitsClient).to receive(:upload_entries).with(uploaded_path)
          job.perform
        end

        it 'merges the bits-service receipt with the cli resources to ask for the bundles' do
          merged_fingerprints = fingerprints + receipt
          expect_any_instance_of(BitsClient).to receive(:bundles).
            with(merged_fingerprints.to_json)
          job.perform
        end

        it 'stores the package received from bits-service in the blobstore' do
          expect(package_blobstore).to receive(:cp_to_blobstore) do |package_path, received_app_guid|
            expect(File.read(package_path)).to eq('contents')
            expect(received_app_guid).to eq(app_guid)
          end
          job.perform
        end

        it 'knows its job name' do
          expect(job.job_name_in_configuration).to equal(:external_packer)
        end

        it 'logs an error if the app cannot be found' do
          app.destroy

          logger = double(:logger, error: nil, info: nil)
          allow(job).to receive(:logger).and_return(logger)

          job.perform

          expect(logger).to have_received(:error).with("App not found: #{app_guid}")
        end

        shared_examples 'a packaging failure' do
          let(:expected_exception) { Errors::ApiError }

          before do
            allow(App).to receive(:find).and_return(app)
          end

          it 'marks the app as failed to stage' do
            expect(app).to receive(:mark_as_failed_to_stage)
            job.perform rescue expected_exception
          end

          it 'raises the exception' do
            expect {
              job.perform
            }.to raise_error(expected_exception)
          end
        end

        context 'when `upload_entries` fails' do
          before do
            allow_any_instance_of(BitsClient).to receive(:upload_entries).
              and_raise(BitsClient::Errors::UnexpectedResponseCode)
          end

          it_behaves_like 'a packaging failure'
        end

        context 'when `bundles` fails' do
          before do
            allow_any_instance_of(BitsClient).to receive(:bundles).
              and_raise(BitsClient::Errors::UnexpectedResponseCode)
          end

          it_behaves_like 'a packaging failure'
        end

        context 'when writing the package to a temp file fails' do
          let(:expected_exception) { StandardError.new('some error') }

          before do
            allow(Tempfile).to receive(:new).
              and_raise(expected_exception)
          end

          it_behaves_like 'a packaging failure'
        end

        context 'when copying the package to the blobstore fails' do
          let(:expected_exception) { StandardError.new('some error') }

          before do
            allow(package_blobstore).to receive(:cp_to_blobstore).
              and_raise(expected_exception)
          end

          it_behaves_like 'a packaging failure'
        end

        context 'when the bits service has an internal error on upload_entries' do
          before do
            allow_any_instance_of(BitsClient).to receive(:upload_entries).
              and_raise(BitsClient::Errors::UnexpectedResponseCode)
          end

          it_behaves_like 'a packaging failure'
        end

        context 'when the bits service has an internal error on bundles' do
          before do
            allow_any_instance_of(BitsClient).to receive(:bundles).
              and_raise(BitsClient::Errors::UnexpectedResponseCode)
          end

          it_behaves_like 'a packaging failure'
        end
      end
    end
  end
end
