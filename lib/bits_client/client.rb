require 'net/http/post/multipart'

class BitsClient
  require_relative 'errors'

  def initialize(endpoint:)
    @endpoint = URI.parse(endpoint)
  end

  def upload_buildpack(buildpack_path, filename)
    with_file_attachment!(buildpack_path, filename) do |file_attachment|
      body = { buildpack: file_attachment }
      multipart_post('/buildpacks', body).tap do |response|
        validate_response_code!(201, response)
      end
    end
  end

  def delete_buildpack(guid)
    delete("/buildpacks/#{guid}").tap do |response|
      validate_response_code!(204, response)
    end
  end

  def upload_droplet(droplet_path)
    with_file_attachment!(droplet_path, nil) do |file_attachment|
      body = { droplet: file_attachment }
      multipart_post('/droplets', body).tap do |response|
        validate_response_code!(201, response)
      end
    end
  end

  def delete_droplet(guid)
    delete("/droplets/#{guid}").tap do |response|
      validate_response_code!(204, response)
    end
  end

  def download_url(resource_type, guid)
    File.join(endpoint.to_s, resource_type.to_s, guid.to_s)
  end

  def matches(resources_json)
    post('/app_stash/matches', resources_json).tap do |response|
      validate_response_code!(200, response)
    end
  end

  def upload_entries(entries_path)
    with_file_attachment!(entries_path, 'entries.zip') do |file_attachment|
      body = { application: file_attachment }
      multipart_post('/app_stash/entries', body).tap do |response|
        validate_response_code!(201, response)
      end
    end
  end

  def bundles(resources_json)
    post('/app_stash/bundles', resources_json).tap do |response|
      validate_response_code!(200, response)
    end
  end

  private

  attr_reader :endpoint

  def validate_response_code!(expected, response)
    return if expected.to_i == response.code.to_i
    error = JSON.parse(response.body)
    fail Errors::UnexpectedResponseCode.new(error['description'])
  end

  def with_file_attachment!(file_path, filename, &block)
    validate_file! file_path

    File.open(file_path) do |file|
      attached_file = UploadIO.new(file, 'application/octet-stream', filename)
      yield attached_file
    end
  end

  def validate_file!(file_path)
    return if File.exist?(file_path)

    raise Errors::FileDoesNotExist.new("Could not find file: #{file_path}")
  end

  def get(path)
    request = Net::HTTP::Get.new(path)
    do_request(request)
  end

  def post(path, body, header={})
    request = Net::HTTP::Post.new(path, header)

    request.body = body
    do_request(request)
  end

  def multipart_post(path, body, header={})
    request = Net::HTTP::Post::Multipart.new(path, body, header)
    do_request(request)
  end

  def delete(path)
    request = Net::HTTP::Delete.new(path)
    do_request(request)
  end

  def do_request(request)
    request.add_field(VCAP::Request::HEADER_NAME, VCAP::Request.current_id)
    http_client.request(request)
  end

  def http_client
    @http_client ||= Net::HTTP.new(endpoint.host, endpoint.port)
  end
end
