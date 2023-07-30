# frozen_string_literal: true

require "faraday"

class Nomad
  attr_reader :endpoint, :version

  def initialize(endpoint:, version: "v1", token: nil, logger:)
    @endpoint = endpoint
    @version = version
    @token = token

    @logger = logger
  end

  def services
    _get("services")
  end

  def service(name, **params)
    _get("service/#{name}", **params)
  end

  def delete_service(name, id)
    _delete("service/#{name}/#{id}")
  end

  def allocation(id)
    _get("allocation/#{id}")
  end

  def token?
    !(@token.nil? || @token.empty?)
  end

  class ResponseError < StandardError; end
  class NotAuthorizedError < ResponseError; end

  private

  def _get(path, **params)
    response = connection.get uri(path), **params

    handle_response(response)
  end

  def _delete(path, **params)
    response = connection.delete uri(path), params
    response.status == 200
  end

  def handle_response(response)
    # @logger.debug "response status: #{response.status}, headers: #{response.headers}, body: #{response.body}, url: #{response.env.url}"

    case response.status
    when 200
      response.body
    when 403
      raise NotAuthorizedError, response.body
    else
      raise ResponseError, response.body
    end
  end

  def uri(path)
    "#{@endpoint}/#{@version}/#{path}"
  end

  def connection
    @connection ||= Faraday.new(url: @endpoint) do |f|
      f.request :authorization, 'Bearer', @token if token?
      f.response :json
      f.response :logger, nil, { bodies: true, log_level: :debug } if ENV["VERBOSE_MODE"] == "true"
    end
  end
end
