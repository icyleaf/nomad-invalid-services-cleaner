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

  def jobs(**params)
    _get("jobs", **params)
  end

  def job(name, **params)
    _get("job/#{name}", **params)
  end

  def job_allocations(name, **params)
    _get("job/#{name}/allocations", **params)
  end

  def job_services(name, **params)
    _get("job/#{name}/services", **params)
  end

  def services(**params)
    _get("services", **params)
  end

  def service(name, **params)
    _get("service/#{name}", **params)
  end

  def delete_service(name, id, **params)
    _delete("service/#{name}/#{id}", **params)
  end

  def allocation(id, **params)
    _get("allocation/#{id}", **params)
  end

  def restart_allocation(id, **params)
    _post("client/allocation/#{id}/restart", **params)
  end

  def token?
    !(@token.nil? || @token.empty?)
  end

  class ResponseError < StandardError
    attr_reader :response

    def initialize(response)
      super(response.body)

      @response = response
    end
  end

  class NotAuthorizedError < ResponseError; end

  private

  def _get(path, **params)
    response = connection.get uri(path), **params

    handle_response(response)
  end

  def _post(path, **params)
    headers = params.delete(:headers) || { content_type: "application/json" }
    params = params.to_json
    response = connection.post uri(path), params, headers

    handle_response(response)
  end

  def _delete(path, **params)
    response = connection.delete uri(path), params
    response.status == 200
  end

  def handle_response(response)
    # @logger.debug "response status: #{response.status}, headers: #{response.headers}, body: #{response.body}, url: #{response.env.url}"

    case response.status
    when 200, 204
      response.body
    when 403
      raise NotAuthorizedError, response
    else
      raise ResponseError, response
    end
  end

  def uri(path)
    "#{@endpoint}/#{@version}/#{path}"
  end

  def connection
    @connection ||= Faraday.new(url: @endpoint, request: request_options) do |f|
      f.request :authorization, 'Bearer', @token if token?
      f.response :json
      f.response :logger, nil, { bodies: true, log_level: :debug } if ENV["VERBOSE_MODE"] == "true"
    end
  end

  def request_options
    timeout = (ENV["NOMAD_API_TIMEOUT"] || 30).to_i

    @request_options ||= {
      open_timeout: timeout,
      read_timeout: timeout,
      write_timeout: timeout
    }
  end
end
