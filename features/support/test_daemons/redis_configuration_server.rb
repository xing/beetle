require 'daemon_controller'
require 'net/http'

module TestDaemons
  class RedisConfigurationServer

    # At the moment, we need only one, so we implement the methods
    # as class methods

    @@redis_servers = ""
    @@redis_configuration_clients = ""
    @@confidence_level = 100

    def self.start(redis_servers, redis_configuration_clients, confidence_level)
      stop
      @@redis_servers = redis_servers
      @@redis_configuration_clients = redis_configuration_clients
      @@confidence_level = confidence_level
      daemon_controller.start
    end

    def self.stop
      daemon_controller.stop
    end

    def self.daemon_controller
      clients_parameter_string = @@redis_configuration_clients.blank? ? "" : "--client-ids #{@@redis_configuration_clients}"
      DaemonController.new(
         :identifier    => "Redis configuration test server",
         :start_command => "./beetle configuration_server -v -d --redis-master-file #{redis_master_file} --redis-servers #{@@redis_servers} #{clients_parameter_string} --redis-master-retry-interval 1 --pid-file #{pid_file} --log-file #{log_file} --redis-failover-confidence-level #{@@confidence_level}",
         :ping_command  => lambda{ answers_text_requests? },
         :pid_file      => pid_file,
         :log_file      => log_file,
         :start_timeout => 10,
         :stop_timeout => 10,
      )
    end

    def self.redis_master_file
      "#{tmp_path}/redis-master-rc-server"
    end

    def self.pid_file
      "#{tmp_path}/redis_configuration_server.pid"
    end

    def self.log_file
      "#{tmp_path}/redis_configuration_server.output"
    end

    def self.tmp_path
      File.expand_path(File.dirname(__FILE__) + "/../../../tmp")
    end

    def self.answers_text_requests?
      response = get_status("/.txt", "text/plain")
      response.code == '200' &&
        response.content_type == "text/plain"
    rescue
      false
    end

    def self.answers_json_requests?
      response = get_status("/.json", "application/json")
      response.code == '200' &&
        response.content_type == "application/json"
    rescue
      false
    end

    def self.answers_html_requests?
      response1 = get_status("/", "text/html")
      response2 = get_status("/.html", "text/html")
      response1.code == '200' && response2.code == '200' &&
        response1.content_type == "text/html" && response2.content_type == "text/html"
    rescue
      false
    end

    def self.get_status(path, content_type)
      uri = URI.parse("http://127.0.0.1:9650#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new(uri.request_uri)
      request['Accept'] = content_type
      response = http.request(request)
      response
    end

    def self.initiate_master_switch
      http = Net::HTTP.new('127.0.0.1', 9650)
      response = http.post '/initiate_master_switch', ''
      response
    end

  end
end
