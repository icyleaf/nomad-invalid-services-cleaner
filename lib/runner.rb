# frozen_string_literal: true

require_relative "nomad"
require "logger"
require "uri"

class Runner
  def self.run
    new.run
  end

  def run
    interval = (ENV["NOMAD_RUNNER_INTERVAL"] || 60).to_i

    logger.info "Starting nomad invalid services runner ..."
    logger.debug "Configuation with endpoint: #{client.endpoint}, version: #{client.version}, token: #{client.token?}"

    run_loop(interval) do
      remove_invaild_services

      ignore_restart_empty_services = ENV.fetch("NOMAD_IGNORE_RESTART_EMPTY_SERVICES", nil)
      restart_empty_services if ignore_restart_empty_services.nil? || ENV["NOMAD_IGNORE_RESTAT_EMPTY_SERVICES"] != "true"
    end
  rescue Nomad::NotAuthorizedError
    if client.token?
      logger.error "Invalid nomad token or missing ACL policies: namespace:read-job and namespace:submit-job"
    else
      logger.error "Nomad enabled ACL, but nomad token is not set with environment variable NOMAD_TOKEN"
    end

    exit
  rescue Nomad::ResponseError => e
    logger.error "Unknown response error: #{e.message} in #{e.response.env.url}"
    exit
  rescue URI::BadURIError => e
    logger.error "Invalid nomad endpoint: #{client.endpoint}. it must be a valid URI: http(s)://nomad.example.com or http(s)://127.0.0.1:4646"
    exit
  rescue SignalException => e
    logger.error "Received signal #{e.class}: #{e.signo}, exiting runner..."
    exit
  end

  private

  def remove_invaild_services
    logger.info "Checking invaild service on published services ..."
    invalid_services = []
    nomad_services = client.services(namespace: "*")
    nomad_services.each do |namespace|
      namespace_name = namespace["Namespace"]
      services = namespace["Services"]

      logger.debug "Found #{services.size} services in namespace: #{namespace_name}"
      inview_services(services, invalid_services, namespace_name)
    end

    if invalid_services.empty?
      logger.info "Not found any invaild service, GOOD!"
    else
      logger.info "Found #{invalid_services.size} invalid services to clean up: #{invalid_services.join(", ")}"
    end
  end

  def restart_empty_services
    logger.info "Checking empty service on running jobs ..."
    restart_job_allocations = []
    jobs = client.jobs(namespace: "*")
    jobs.each do |job_entry|
      next if (job_type = job_entry["Type"]) && job_type != "service"
      next if (job_status = job_entry["Status"]) && job_status != "running"

      job_id = job_entry["ID"]
      namespace = job_entry["Namespace"]

      job_allocations = client.job_allocations(job_id, namespace: namespace)
      job_allocations.each do |allocation_entry|
        allocation_id = allocation_entry["ID"]
        allocation = client.allocation(allocation_id, namespace: namespace)

        # allocation trigger stop operation, but not stop yet. try to force stop it.
        if allocation["DesiredStatus"] == "stop"
          r = client.stop_allocation(allocation_id)
          next
        end

        task_groups = allocation["Job"]["TaskGroups"]
        task_groups.each do |task_group|
          # services may define in task group or task
          task_services = task_group["Services"] || task_group["Tasks"].reject { |task| task["Services"].nil? }.map { |task| task["Services"] }

          logger.debug "Job #{job_id} in allocation #{allocation_id} found #{task_services.size} services in namespace: #{namespace}"
          next if task_services.empty? # job not define any service, such like csi plugin.

          job_services = client.job_services(job_id, namespace: namespace)
          job_services_count = job_services.size
          next unless job_services_count.zero?

          logger.info "Job #{job_id} in allocation #{allocation_id} services not found in facts, restart allocation"
          client.restart_allocation(allocation_id, AllTasks: true)

          restart_job_allocations << "#{job_id}:#{allocation_id}"
          break
        end
      end
    end

    if restart_job_allocations.empty?
      logger.info "Not found any empty service, GOOD!"
    else
      logger.info "Found #{restart_job_allocations.size} has empty services to restart allocation: #{restart_job_allocations.join(", ")}"
    end
  end

  def inview_services(services, invalid_services, namespace)
    services.each do |service|
      name = service["ServiceName"]
      published_services = client.service(service["ServiceName"], namespace: namespace)
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
          client.allocation(allocation_id, namespace: namespace)
        rescue
          logger.debug "Found invalid service #{name} (#{service_id}), allocation was not exists with id: #{allocation_id}"
          invalid_services << name

          deleted_success = client.delete_service(name, service_id, namespace: namespace)
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
    @logger ||= Logger.new($stdout, "daily", level: ENV.fetch("LOGGER_LEVEL", "info").to_sym)
  end

  def client
    @client ||= lambda {
      endpoint = ENV.fetch("NOMAD_ENDPOINT") do
        logger.error "Missing envoriment variable: NOMAD_ENPOINT"
        exit
      end

      version = ENV.fetch("NOMAD_VERSION", "v1")
      token = ENV.fetch("NOMAD_TOKEN", nil)

      Nomad.new(endpoint: endpoint, token: token, version: version, logger: logger)
    }.call
  end
end
