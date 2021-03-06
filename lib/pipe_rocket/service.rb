require 'http'
require 'pipe_rocket/deal'
require 'pipe_rocket/deal_field'
require 'pipe_rocket/file'
require 'pipe_rocket/mail_message'
require 'pipe_rocket/note'
require 'pipe_rocket/organization'
require 'pipe_rocket/organization_field'
require 'pipe_rocket/person'
require 'pipe_rocket/person_field'
require 'pipe_rocket/pipeline'
require 'pipe_rocket/stage'
require 'pipe_rocket/user'
require 'pipe_rocket/error'

module PipeRocket
  class Service
    HOST = 'https://api.pipedrive.com/v1'
    RESOURCES_WITH_CUSTOM_FIELDS = %w(deal organization person)

    def initialize(resource_name)
      @resource_name = resource_name
      @has_custom_fields = RESOURCES_WITH_CUSTOM_FIELDS.include?(@resource_name)
    end

    # Build resource_name class object from hash
    def build_entity(raw, resource_name = nil)
      resource_name ||= @resource_name
      "PipeRocket::#{resource_name.titleize.delete(' ')}".constantize.new(raw)
    end

    # Build uri for request
    def build_uri(params = {}, specificator = nil, action = nil)
      params.merge!(api_token: ENV['pipedrive_api_token'])
      query_string = params.map{|k,v|"#{k}=#{v}"}.join('&')
      plural_resource_name = @resource_name == 'person' ? 'persons' : @resource_name.pluralize
      uri = URI("#{HOST}/#{[plural_resource_name, specificator, action].compact.join('/')}?#{query_string}")
    end

    # Getting all @resource_name object from Pipedrive
    def all
      uri = build_uri
      response = HTTP.get(uri)

      case response.code
      when 200
        json_array = ::JSON.parse(response)['data']
        json_array.map{|raw|build_entity(raw)}
      else
        raise PipeRocket::Error.new(response.code)
      end
    rescue HTTP::ConnectionError
      raise PipeRocket::Error.new(408)
    end

    # Create @resource_name in Pipedrive
    def create(params)
      uri = build_uri
      response = HTTP.post(uri, form: transform_custom_fields(params))

      case response.code
      when 201
        build_entity(JSON.parse(response.body)['data'])
      else
        raise PipeRocket::Error.new(response.code)
      end
    rescue HTTP::ConnectionError
      raise PipeRocket::Error.new(408)
    end

    # Find @resource_name object by id
    def find(id)
      uri = build_uri({}, id)
      response = HTTP.get(uri)

      case response.code
      when 200
        raw = ::JSON.parse(response)['data']
        build_entity(raw)
      else
        raise PipeRocket::Error.new(response.code)
      end
    rescue HTTP::ConnectionError
      raise PipeRocket::Error.new(408)
    end

    # Getting first @resource_name object
    def first
      self.all.first
    end

    # Update @resource_name object by id
    def update(id, params)
      uri = build_uri({}, id)
      response = HTTP.put(uri, form: transform_custom_fields(params))

      case response.code
      when 200
        build_entity(JSON.parse(response.body)['data'])
      else
        raise PipeRocket::Error.new(response.code)
      end
    rescue HTTP::ConnectionError
      raise PipeRocket::Error.new(408)
    end

    protected

    # Trasform custom fields from their names to keys
    def transform_custom_fields(params)
      return params unless @has_custom_fields

      @@name_key_hash = Pipedrive.send("#{@resource_name}_fields").name_key_hash
      @@name_key_hash.transform_keys!{|key|clear_key(key)}

      hash = ::CUSTOM_FIELD_NAMES
      if hash && hash[@resource_name.to_sym]
        @@name_key_hash = @@name_key_hash.merge(hash[@resource_name.to_sym].invert)
      end

      keys = @@name_key_hash.keys
      res = {}

      params.each do |name, value|
        if keys.include?(name.to_s) #Custom Field
          res[@@name_key_hash[name.to_s]] = value
        else
          res[name] = value
        end
      end
      res
    end

    # Clear string from forbidden symbols for ruby variables
    def clear_key(key)
      key = key.underscore.gsub(' ','_')
      key = key.gsub('%','percent').gsub(/[^a-zA-Z0-9_]/,'')
    end

  end
end
