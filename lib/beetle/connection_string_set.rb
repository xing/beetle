# frozen_string_literal: true

require 'beetle/connection_string'

module Beetle
  class ConnectionStringSet
    include Enumerable

    def initialize(connection_strings)
      @connection_strings = Array(connection_strings).map { |cs| ConnectionString.new(cs) }.uniq
    end

    delegate :each, :delete, :empty?, :[], :include?, :to_a, :sample, :size, :to_ary, to: :@connection_strings

    def []=(index, connection_string)
      @connection_strings[index] = ConnectionString.new(connection_string)
    end

    def <<(connection_string)
      (@connection_strings << ConnectionString.new(connection_string)).tap do
        @connection_strings.uniq!
      end
    end

    def next_after(connection_string)
      server = ConnectionString.new(connection_string)
      idx = ((@connection_strings.index(server) || 0)+1) % @connection_strings.size

      @connection_strings[idx]
    end

    def concat(connection_strings)
      (@connection_strings.concat(Array(connection_strings).map { |cs| ConnectionString.new(cs.to_s) })).tap do
        @connection_strings.uniq!
      end
    end
  end
end
