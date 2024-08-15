# frozen_string_literal: true

module ActiveRecord
  # Returns the version of the currently loaded Active Record as a <tt>Gem::Version</tt>
  def self.gem_version
    Gem::Version.new VERSION::STRING
  end

  module VERSION
    MAJOR = 5
    MINOR = 2
    TINY  = 8
    PRE   = "1"

    STRING = [MAJOR, MINOR, TINY, PRE].compact.join(".")
  end
end
