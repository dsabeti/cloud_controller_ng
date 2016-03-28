require 'spec_helper'

describe 'Droplets' do
  let(:space) { VCAP::CloudController::Space.make }
  let(:app_model) { VCAP::CloudController::AppModel.make(space_guid: space.guid) }
  let(:developer) { make_developer_for_space(space) }
  let(:developer_headers) { headers_for(developer) }

  describe 'POST /v3/packages/:guid/droplets' do
    let(:diego_staging_response)  do
      {
        execution_metadata:     'String',
        detected_start_command: {},
        lifecycle_data:         {
          buildpack_key:      'String',
          detected_buildpack: 'String',
        }
      }
    end

    before do
      allow_any_instance_of(CloudController::Blobstore::UrlGenerator).to receive(:v3_app_buildpack_cache_download_url).and_return('some-string')
      allow_any_instance_of(CloudController::Blobstore::UrlGenerator).to receive(:v3_app_buildpack_cache_upload_url).and_return('some-string')
      allow_any_instance_of(CloudController::Blobstore::UrlGenerator).to receive(:package_download_url).and_return('some-string')
      allow_any_instance_of(CloudController::Blobstore::UrlGenerator).to receive(:package_droplet_upload_url).and_return('some-string')
      stub_request(:put, "#{TestConfig.config[:diego_stager_url]}/v1/staging/whatuuid").
        to_return(status: 202, body: diego_staging_response.to_json)
    end

    it 'creates a droplet' do
      stub_const('SecureRandom', double(:sr, uuid: 'whatuuid', hex: '8-octetx'))

      package = VCAP::CloudController::PackageModel.make(
        app_guid: app_model.guid,
        state:    VCAP::CloudController::PackageModel::READY_STATE,
        type:     VCAP::CloudController::PackageModel::BITS_TYPE,
        url: 'hello.com'
      )

      create_request = {
        environment_variables: { 'CUSTOMENV' => 'env value' },
        memory_limit:          1024,
        disk_limit:            4096,
        lifecycle:             {
          type: 'buildpack',
          data: {
            stack:     'cflinuxfs2',
            buildpack: 'http://github.com/myorg/awesome-buildpack'
          }
        },
      }

      post "/v3/packages/#{package.guid}/droplets", create_request.to_json, json_headers(developer_headers)

      expect(last_response.status).to eq(201)

      droplet = VCAP::CloudController::DropletModel.last

      expected_response = {
        'guid'                  => droplet.guid,
        'state'                 => 'PENDING',
        'error'                 => nil,
        'lifecycle'             => {
          'type' => 'buildpack',
          'data' => {
            'stack'     => 'cflinuxfs2',
            'buildpack' => 'http://github.com/myorg/awesome-buildpack'
          }
        },
        'environment_variables' => {
          'CF_STACK'         => 'cflinuxfs2',
          'CUSTOMENV'        => 'env value',
          'MEMORY_LIMIT'     => '1024m',
          'VCAP_SERVICES'    => {},
          'VCAP_APPLICATION' => {
            'limits'              => { 'mem' => 1024, 'disk' => 4096, 'fds' => 16384 },
            'application_id'      => app_model.guid,
            'application_version' => 'whatuuid',
            'application_name'    => app_model.name, 'application_uris' => [],
            'version'             => 'whatuuid',
            'name'                => app_model.name,
            'space_name'          => space.name,
            'space_id'            => space.guid,
            'uris'                => [],
            'users'               => nil
          }
        },
        'memory_limit'          => 1024,
        'disk_limit'            => 4096,
        'result'                => nil,
        'created_at'            => iso8601,
        'updated_at'            => nil,
        'links'                 => {
          'self'                   => { 'href' => "/v3/droplets/#{droplet.guid}" },
          'package'                => { 'href' => "/v3/packages/#{package.guid}" },
          'app'                    => { 'href' => "/v3/apps/#{app_model.guid}" },
          'assign_current_droplet' => {
            'href'   => "/v3/apps/#{app_model.guid}/current_droplet",
            'method' => 'PUT'
          }
        }
      }

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response.status).to eq(201)
      expect(parsed_response['environment_variables']).to be_a_response_like(expected_response['environment_variables'])
    end
  end

  describe 'GET /v3/droplets/:guid' do
    let(:guid) { droplet_model.guid }
    let(:buildpack_git_url) { 'http://buildpack.git.url.com' }
    let(:package_model) { VCAP::CloudController::PackageModel.make(app_guid: app_model.guid) }
    let!(:droplet_model) do
      VCAP::CloudController::DropletModel.make(
        :buildpack,
        state:                       VCAP::CloudController::DropletModel::STAGED_STATE,
        app_guid:                    app_model.guid,
        package_guid:                package_model.guid,
        buildpack_receipt_buildpack: buildpack_git_url,
        error:                       'example error',
        environment_variables:       { 'cloud' => 'foundry' },
      )
    end

    let(:app_guid) { droplet_model.app_guid }

    it 'gets a droplet' do
      expected_response = {
        'guid'                   => droplet_model.guid,
        'state'                  => droplet_model.state,
        'error'                  => droplet_model.error,
        'lifecycle'              => {
          'type' => 'buildpack',
          'data' => {
            'buildpack' => droplet_model.lifecycle_data.buildpack,
            'stack' => droplet_model.lifecycle_data.stack,
          }
        },
        'result' => {
          'hash'                 => { 'type' => 'sha1', 'value' => droplet_model.droplet_hash },
          'stack'                => droplet_model.buildpack_receipt_stack_name,
          'process_types'        => droplet_model.process_types,
          'execution_metadata'   => droplet_model.execution_metadata,
          'buildpack'            => droplet_model.buildpack_receipt_buildpack
        },
        'memory_limit'           => droplet_model.memory_limit,
        'disk_limit'             => droplet_model.disk_limit,
        'detected_start_command' => droplet_model.detected_start_command,
        'environment_variables'  => droplet_model.environment_variables,
        'created_at'             => iso8601,
        'updated_at'             => iso8601,
        'links'                 => {
          'self'    => { 'href' => "/v3/droplets/#{guid}" },
          'package' => { 'href' => "/v3/packages/#{package_model.guid}" },
          'app'     => { 'href' => "/v3/apps/#{app_guid}" },
          'assign_current_droplet' => {
            'href' => "/v3/apps/#{app_guid}/current_droplet",
            'method' => 'PUT'
          }
        }
      }

      get "/v3/droplets/#{droplet_model.guid}", nil, developer_headers

      parsed_response = MultiJson.load(last_response.body)
      expect(last_response.status).to eq(200)
      expect(parsed_response).to be_a_response_like(expected_response)
    end
  end
end
