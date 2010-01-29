module Bandersnatch
  class Configuration
    attr_accessor :logger, :config_file, :environment
    def initialize
      self.logger = Logger.new(STDOUT)
      self.environment = ENV['RAILS_ENV'] || "development"
    end
  end
end
