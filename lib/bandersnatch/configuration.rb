module Bandersnatch
  class Configuration
    attr_accessor :logger, :config_file, :environment

    def environment
      @environment ||= ENV['RAILS_ENV'] || "development"
    end
  end
end
