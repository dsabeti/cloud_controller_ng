require 'messages/base_message'

module VCAP::CloudController
  class TasksListMessage < BaseMessage
    ALLOWED_KEYS = [:names, :states, :guids, :app_guids, :organization_guids, :space_guids, :page, :per_page].freeze

    attr_accessor(*ALLOWED_KEYS)

    validates_with NoAdditionalParamsValidator

    validates :names, array: true, allow_nil: true
    validates :states, array: true, allow_nil: true
    validates :guids, array: true, allow_nil: true
    validates :app_guids, array: true, allow_nil: true
    validates :organization_guids, array: true, allow_nil: true
    validates :space_guids, array: true, allow_nil: true
    validates_numericality_of :page, greater_than: 0, allow_nil: true, only_integer: true
    validates_numericality_of :per_page, greater_than: 0, allow_nil: true, only_integer: true

    def initialize(params={})
      super(params.symbolize_keys)
    end

    def to_param_hash
      super(exclude: [:page, :per_page, :order_by])
    end

    def self.from_params(params)
      opts = params.dup
      to_array!(opts, 'names')
      to_array!(opts, 'states')
      to_array!(opts, 'guids')
      to_array!(opts, 'app_guids')
      to_array!(opts, 'organization_guids')
      to_array!(opts, 'space_guids')
      new(opts.symbolize_keys)
    end

    private

    def allowed_keys
      ALLOWED_KEYS
    end
  end
end