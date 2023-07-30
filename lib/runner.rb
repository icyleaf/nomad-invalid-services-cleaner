# frozen_string_literal: true

require_relative "nomad"
require "logger"
require "uri"

class Runner
  def self.run
    new.run
  end

  def run
    interval = ENV.fetch("NOMAD_RUNNER_INTERVAL", "60").to_i

    logger.info "Starting nomad invalid services runner ..."
    logger.debug "endpoint: #{client.endpoint}, version: #{client.version}, token: #{client.token?}"

    run_loop(interval) do
      invalid_services = []
      nomad_services = client.services
      nomad_services.each do |namespace|
        namespace_name = namespace["Namespace"]
        services = namespace["Services"]

        logger.info "Found #{services.size} services in namespace: #{namespace_name}"
        inview_services(services, invalid_services, namespace_name)

        if invalid_services.empty?
          logger.info "All services is good!"
        else
          logger.info "Found #{invalid_services.size} invalid services to clean up: #{invalid_services.join(", ")}"
        end
      end
    end
  rescue Nomad::NotAuthorizedError => e
    if client.token?
      logger.error "Invalid nomad token or missing ACL policies: namespace:read-job and namespace:submit-job"
    else
      logger.error "Nomad enabled ACL, but nomad token is not set with environment variable NOMAD_TOKEN"
    end

    exit
  rescue Nomad::ResponseError => e
    logger.error "Unknown response error: #{e.message}"
    exit
  rescue URI::BadURIError => e
    logger.error "Invalid nomad endpoint: #{client.endpoint}. it must be a valid URI: http(s)://nomad.example.com or http(s)://127.0.0.1:4646"
    exit
  rescue SignalException => e
    logger.error "Received signal #{e.class}: #{e.signo}, exiting runner..."
    exit
  end

  private

  def inview_services(services, invalid_services, namespace)
    services.each do |service|
      name = service["ServiceName"]
      published_services = client.service(service["ServiceName"], **{ namespace: namespace })
      published_service_count = published_services.size

      logger.debug "#{name} published #{published_service_count} services"
      published_services.each_with_index do |service_info, service_index|
        service_id = service_info["ID"]
        allocation_id = service_info["AllocID"]
        namespace_name = service_info["Namespace"]
        address = service_info["Address"]
        port = service_info["Port"]
        data_center = service_info["Datacenter"]

        logger.debug "service: #{name}, index: #{service_index}, allocation_id: #{allocation_id}, data_center: #{data_center}, namespace: #{namespace_name}, address: #{address}, port: #{port}"

        begin
          client.allocation(allocation_id)
        rescue
          logger.debug "Found invalid service #{name} (#{service_id}), allocation was not exists with id: #{allocation_id}"
          invalid_services << name

          deleted_success = client.delete_service(name, service_id)
          if deleted_success
            logger.info "Deleted invalid service #{name} (#{service_id})"
          else
            logger.error "Failed to delete invalid service #{name} (#{service_id})"
          end
        end
      end
    end
  end

  def run_loop(interval, &block)
    count = 0
    loop do
      block.call

      break if ENV["ONESHOT"] == "true"

      logger.info "Waiting next loop ... (#{interval} seconds)"
      sleep(interval)
      count += 1
    end
  end

  def logger
    @logger ||= Logger.new(STDOUT, 'daily', level: ENV.fetch('LOGGER_LEVEL', "info").to_sym)
  end

  def client
    @client ||= -> {
      endpoint = ENV.fetch("NOMAD_ENDPOINT") do
        logger.error "Missing envoriment variable: NOMAD_ENPOINT"
        exit
      end

      version = ENV.fetch("NOMAD_VERSION", "v1")
      token = ENV["NOMAD_TOKEN"]

      Nomad.new(endpoint: endpoint, token: token, version: version, logger: logger)
    }.call
  end
end
