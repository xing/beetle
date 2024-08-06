# frozen_string_literal: true

require 'beetle/connection_string'

module Beetle
  class ConnectionStringSet
    def initialize(*connection_strings)
      @connection_strings = Array(connection_strings).map { |cs| ConnectionString.new(cs.to_s) }.uniq
    end

    delegate :include?, :to_a, :sample, :to_ary, to: :@connection_strings

    def []=(index, connection_string)
      @connection_strings[index] = ConnectionString.new(connection_string.to_s)
    end

    def [](index)
      @connection_strings[index]
    end

    def <<(connection_string)
      (@connection_strings << ConnectionString.new(connection_string.to_s)).tap do
        @connection_strings.uniq!
      end
    end
  end
end
