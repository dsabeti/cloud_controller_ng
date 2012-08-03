# Copyright (c) 2009-2011 VMware, Inc.

module VCAP::CloudController
  rest_controller :AppBits do
    disable_default_routes
    path_base "apps"
    model_class_name :App

    permissions_required do
      full Permissions::CFAdmin
      full Permissions::SpaceDeveloper
    end

    def upload(id)
      app = find_id_and_validate_access(:update, id)

      ["application", "resources"].each do |k|
        raise AppBitsUploadInvalid.new("missing :#{k}") unless params[k]
      end

      resources = json_param("resources")
      unless resources.kind_of?(Array)
        raise AppBitsUploadInvalid.new("resources is not an Array")
      end

      # TODO: nginx support
      application = params["application"]
      unless application.kind_of?(Hash) && application[:tempfile]
        raise AppBitsUploadInvalid.new("bad :application")
      end
      uploaded_file = application[:tempfile]

      AppPackage.to_zip(app.guid, uploaded_file, resources)
      HTTP::CREATED
    end


    def json_param(name)
      raw = params[name]
      Yajl::Parser.parse(raw)
    rescue Yajl::ParseError => e
      raise AppBitsUploadInvalid.new("invalid :#{name}")
    end

    put "#{path_id}/bits", :upload
  end
end
