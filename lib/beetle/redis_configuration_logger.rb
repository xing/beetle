module Beetle
  module RedisConfigurationLogger
    def logger
      return @logger if @logger
      @logger = Logger.new(STDOUT)
      @logger.formatter = Logger::Formatter.new
      @logger.level = Logger::DEBUG
      @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      @logger
    end
  end
end
