module Beetle
  class Configuration
    attr_accessor :logger, :config_file, :environment, :gc_threshold
    def initialize
      self.logger = Logger.new(STDOUT)
      self.environment = ENV['RAILS_ENV'] || "development"
      self.gc_threshold = 3.days
    end
  end
end
