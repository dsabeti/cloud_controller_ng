require 'spec_helper'

module CloudController
  module Blobstore
    describe ClientProvider do
      let(:options) { { blobstore_type: blobstore_type } }
      let(:blobstore_type) { nil }

      context 'when no type is requested' do
        before do
          options.merge!(fog_connection: {})
        end

        it 'provides a fog client' do
          allow(FogClient).to receive(:new).and_call_original
          ClientProvider.provide(options: options, directory_key: 'key')
          expect(FogClient).to have_received(:new)
        end
      end

      context 'when fog is requested' do
        let(:blobstore_type) { 'fog' }

        before do
          options.merge!(fog_connection: {})
        end

        it 'provides a fog client' do
          allow(FogClient).to receive(:new).and_call_original
          ClientProvider.provide(options: options, directory_key: 'key')
          expect(FogClient).to have_received(:new)
        end

        context 'when a cdn is requested in the options' do
          before do
            options.merge!(cdn: { uri: 'http://cdn.com' })
          end

          it 'sets up a cdn for the fog client' do
            allow(FogClient).to receive(:new).and_call_original
            ClientProvider.provide(options: options, directory_key: 'key')
            expect(FogClient).to have_received(:new).with(anything, anything, an_instance_of(Cdn), anything, anything, anything)
          end
        end

        context 'when fog_connection is not provided' do
          before do
            options.delete(:fog_connection)
          end

          it 'raises an error' do
            expect { ClientProvider.provide(options: options, directory_key: 'key') }.to raise_error(KeyError)
          end
        end
      end

      context 'when webdav is requested' do
        let(:blobstore_type) { 'webdav' }

        before do
          options.merge!(webdav_config: { private_endpoint: 'http://private.example.com', public_endpoint: 'http://public.example.com' })
        end

        it 'provides a webdav client' do
          allow(DavClient).to receive(:new).and_call_original
          ClientProvider.provide(options: options, directory_key: 'key')
          expect(DavClient).to have_received(:new)
        end
      end

      context 'when a bits client is being passed' do
        let(:bits_client) { double(BitsClient) }

        it 'provides a bits service client' do
          expect(BitsServiceClient).to receive(:new).with(bits_client: bits_client, resource_type: 'foo').and_call_original
          ClientProvider.provide(options: options, directory_key: 'key', bits_client: bits_client, resource_type: 'foo')
        end
      end
    end
  end
end
