module Beetle
  module RedisConfigurationLogger
    def logger
      @logger ||= begin
        logger = Logger.new(STDOUT)
        logger.formatter = Logger::Formatter.new
        logger.level = Logger::DEBUG
        logger.datetime_format = "%Y-%m-%d %H:%M:%S"
        logger
      end
    end

    def disable_logging
      @logger = DisabledLogger.new(STDOUT)
    end

    private

    class DisabledLogger < Logger
      def add(*args, &blk); end
    end
  end
end
