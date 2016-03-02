require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::ResourceMatchesController do
    include_context 'resource pool'

    before do
      @resource_pool.add_directory(@tmpdir)
    end

    def resource_match_request(verb, path, matches, non_matches)
      user = User.make(admin: false, active: true)
      req = MultiJson.dump(matches + non_matches)
      send(verb, path, req, json_headers(headers_for(user)))
      expect(last_response.status).to eq(200)
      resp = MultiJson.load(last_response.body)
      expect(resp).to eq(matches)
    end

    describe 'when the app_bits_upload feature flag is enabed' do
      before do
        FeatureFlag.make(name: 'app_bits_upload', enabled: true)
      end

      describe 'PUT /v2/resource_match' do
        it 'should return an empty list when no resources match' do
          resource_match_request(:put, '/v2/resource_match', [], [@dummy_descriptor])
        end

        it 'should return a resource that matches' do
          resource_match_request(:put, '/v2/resource_match', [@descriptors.first], [@dummy_descriptor])
        end

        it 'should return many resources that match' do
          resource_match_request(:put, '/v2/resource_match', @descriptors, [@dummy_descriptor])
        end

        context 'invalid json' do
          it 'returns an error' do
            put '/v2/resource_match', 'invalid json', json_headers(headers_for(User.make))

            expect(last_response.status).to eq(400)
            expect(last_response.body).to match(/MessageParseError/)
          end
        end

        context 'non-array json' do
          it 'returns an error' do
            put '/v2/resource_match', 'null', json_headers(headers_for(User.make))

            expect(last_response.status).to eq(422)
            expect(last_response.body).to match(/UnprocessableEntity/)
            expect(last_response.body).to match(/must be an array./)
          end
        end
      end
    end

    describe 'when the app_bits_upload feature flag is disabled' do
      before do
        FeatureFlag.make(name: 'app_bits_upload', enabled: false)
      end

      it 'allows the upload if the user is an admin' do
        send(:put, '/v2/resource_match', '[]', admin_headers)
        expect(last_response.status).to eq(200)
      end

      it 'returns FeatureDisabled unless the user is an admin' do
        user = User.make(admin: false, active: true)
        send(:put, '/v2/resource_match', '[]', json_headers(headers_for(user)))
        expect(last_response.status).to eq(403)
        expect(decoded_response['error_code']).to match(/FeatureDisabled/)
        expect(decoded_response['description']).to match(/Feature Disabled/)
      end
    end

    describe 'when bits-service flag is enabled' do
      let(:bits_service_config) do
        {
          bits_service: {
            enabled: true,
            endpoint: 'https://bits-service.example.com'
          }
        }
      end
      let(:resources) { [{ 'sha1': '12345' }, { 'sha1': '56789' }] }

      before do
        TestConfig.override(bits_service_config)
      end

      it 'forwards the request using the bits_service client' do
        expect_any_instance_of(BitsClient).to receive(:matches).with(resources.to_json)
        send(:put, '/v2/resource_match', resources.to_json, admin_headers)
      end

      it 'returns back the matches' do
        allow_any_instance_of(BitsClient).to receive(:matches).
          and_return(double(:response, code: 200, body: resources.to_json))

        send(:put, '/v2/resource_match', resources.to_json, admin_headers)
        expect(last_response.body).to eq(resources.to_json)
      end

      context 'when the bits_client response is not 200' do
        before do
          allow_any_instance_of(BitsClient).to receive(:matches).
            and_raise(BitsClient::Errors::Error, 'Failed in bits-service')
        end

        it 'retuns HTTP status 500' do
          put '/v2/resource_match', '[]', admin_headers
          expect(last_response.status).to eq(500)
        end

        it 'returns an error description' do
          put '/v2/resource_match', '[]', admin_headers
          error = JSON.parse(last_response.body)
          expect(error['description']).to match(/Failed in bits-service/)
        end
      end
    end
  end
end
