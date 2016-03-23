module VCAP::CloudController
  class SyslogDrainUrlsController < RestController::BaseController
    # Endpoint does its own basic auth
    allow_unauthenticated_access

    authenticate_basic_auth('/v2/syslog_drain_urls') do
      [VCAP::CloudController::Config.config[:bulk_api][:auth_user],
       VCAP::CloudController::Config.config[:bulk_api][:auth_password]]
    end


    get '/v2/syslog_drain_urls', :list
    def list
      id_for_next_token = last_id + batch_size

      query =
        v2_apps_with_syslog_drains_dataset.
          union(v3_apps_with_syslog_drains_dataset, from_self: false, all: true).
          order(:guid).
          limit(batch_size).
          offset(last_id)

      b = query.all

      drain_urls = {}
      b.each do |a|
        if a[:app_version] == 'v2'
          drain_urls[a[:guid]] = App.find(guid: a[:guid]).service_bindings.map(&:syslog_drain_url)
        else
          drain_urls[a[:guid]] = AppModel.find(guid: a[:guid]).service_bindings.map(&:syslog_drain_url)
        end
      end

      [HTTP::OK, {}, MultiJson.dump({ results: drain_urls, next_id: id_for_next_token }, pretty: true)]
    end

    private

    def v2_apps_with_syslog_drains_dataset
      App.db[App.table_name].
        join(ServiceBinding.table_name, app_id: :id).
          where('syslog_drain_url IS NOT NULL').
          where("syslog_drain_url != ''").
          distinct("#{App.table_name}__guid".to_sym).
        select(
          "#{App.table_name}__guid".to_sym,
          Sequel.cast('v2', :text).as(:app_version)
        )
    end

    def v3_apps_with_syslog_drains_dataset
      AppModel.db[AppModel.table_name].
        join(ServiceBindingModel.table_name, app_id: :id).
          where('syslog_drain_url IS NOT NULL').
          where("syslog_drain_url != ''").
          distinct("#{AppModel.table_name}__guid".to_sym).
      select(
          "#{AppModel.table_name}__guid".to_sym,
          Sequel.cast('v3', :text).as(:app_version)
        )
    end

    def last_id
      Integer(params.fetch('next_id', 0))
    end

    def batch_size
      Integer(params.fetch('batch_size', 50))
    end
  end
end


# query = App.db[App.table_name].
#   join(ServiceBinding.table_name, app_id: :id).
#     where('syslog_drain_url IS NOT NULL').
#     where("syslog_drain_url != ''").
#   select(
#     "#{App.table_name}__guid".to_sym,
#     "#{ServiceBinding.table_name}__syslog_drain_url".to_sym
#   ).
#   union(
#     AppModel.db[AppModel.table_name].
#       join(ServiceBindingModel.table_name, app_id: :id).
#         where('syslog_drain_url IS NOT NULL').
#         where("syslog_drain_url != ''").
#       select(
#         "#{AppModel.table_name}__guid".to_sym,
#         "#{ServiceBindingModel.table_name}__syslog_drain_url".to_sym
#       ),
#     from_self: false
#   )
