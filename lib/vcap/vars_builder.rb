module VCAP
  class VarsBuilder
    def initialize(app,
                   memory_limit: nil,
                   disk_limit: nil,
                   space: nil,
                   file_descriptors: nil,
                   v3_app_name: nil
                  )
      @app = app
      @disk_limit = disk_limit
      @memory_limit = memory_limit
      @space = space
      @file_descriptors = file_descriptors
      @v3_app_name = v3_app_name
    end

    def vcap_application
      if @app.class == VCAP::CloudController::AppModel
        app_name = @app.name
        version = SecureRandom.uuid
        uris    = @app.routes.map(&:fqdn)
      else
        app_name = @app.app_guid.nil? ? @app.name : @app.app.name
        @disk_limit = @app.disk_quota if @disk_limit.nil?
        @memory_limit = @app.memory if @memory_limit.nil?
        @file_descriptors = @app.file_descriptors if @file_descriptors.nil?
        version = @app.version
        uris = @app.uris
      end

      @space = @app.space if @space.nil?

      {
        'limits'=> {
          'mem'=> @memory_limit,
          'disk'=> @disk_limit,
          'fds'=> @file_descriptors
        },
        'application_id'=> @app.guid,
        'application_version'=> version,
        'application_name'=> app_name,
        'application_uris'=> uris,
        'version'=> version,
        'name'=> @app.name,
        'space_name'=> @space.name,
        'space_id'=> @space.guid,
        'uris'=> uris,
        'users'=> nil
      }
    end
  end
end
