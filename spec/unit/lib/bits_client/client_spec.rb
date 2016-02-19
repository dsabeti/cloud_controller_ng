require 'spec_helper'
require 'bits_client/client'

require 'securerandom'

describe BitsClient do
  let(:endpoint) { 'http://bits-service.com/' }

  let(:guid) { SecureRandom.uuid }

  subject { BitsClient.new(endpoint: endpoint) }

  context 'Buildpacks' do
    describe '#upload_buildpack' do
      let(:file_path) { Tempfile.new('buildpack').path }
      let(:file_name) { 'my-buildpack.zip' }

      it 'makes the correct request to the bits endpoint' do
        request = stub_request(:post, 'http://bits-service.com/buildpacks').
          with(body: /.*buildpack".*/).
          to_return(status: 201)

        subject.upload_buildpack(file_path, file_name)
        expect(request).to have_been_requested
      end

      it 'returns the request response' do
        stub_request(:post, 'http://bits-service.com/buildpacks').
          to_return(status: 201)

        response = subject.upload_buildpack(file_path, file_name)
        expect(response.code).to eq('201')
      end

      context 'when invalid buildpack is given' do
        it 'raises the correct exception' do
          expect {
            subject.upload_buildpack('/not-here', file_name)
          }.to raise_error(BitsClient::Errors::FileDoesNotExist)
        end
      end
    end

    describe '#download_url' do
      it 'returns the bits-service download endpoint for the guid' do
        url = subject.download_url(:buildpacks, '1234')
        expect(url).to eq('http://bits-service.com/buildpacks/1234')
      end
    end

    describe '#download_buildpack' do
      it 'makes the correct request to the bits endpoint' do
        request = stub_request(:get, "http://bits-service.com/buildpacks/#{guid}").
          to_return(status: 200)

        subject.download_buildpack(guid)
        expect(request).to have_been_requested
      end

      it 'returns the request response' do
        stub_request(:get, "http://bits-service.com/buildpacks/#{guid}").
          to_return(status: 404)

        response = subject.download_buildpack(guid)
        expect(response.code).to eq('404')
      end
    end

    describe '#delete_buildpack' do
      it 'makes the correct request to the bits endpoint' do
        request = stub_request(:delete, "http://bits-service.com/buildpacks/#{guid}").
          to_return(status: 204)

        subject.delete_buildpack(guid)
        expect(request).to have_been_requested
      end

      it 'returns the request response' do
        stub_request(:delete, "http://bits-service.com/buildpacks/#{guid}").
          to_return(status: 404)

        response = subject.delete_buildpack(guid)
        expect(response.code).to eq('404')
      end
    end
  end
end
