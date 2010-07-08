module Beetle
  module RedisMasterFile
    private
    def master_file_exists?
      File.exist?(master_file)
    end

    def redis_master_from_master_file
      server = read_redis_master_file
      redis_instances.find{|r| r.server == server }
    end

    def clear_redis_master_file
      logger.warn "Clearing redis master file '#{master_file}'"
      write_redis_master_file("")
    end

    def read_redis_master_file
      File.read(master_file).chomp
    end

    def write_redis_master_file(redis_server_string)
      logger.warn "Writing '#{redis_server_string}' to redis master file '#{master_file}'"
      File.open(master_file, "w"){|f| f.puts redis_server_string }
    end

    def master_file
      config.redis_server
    end
  end
end
