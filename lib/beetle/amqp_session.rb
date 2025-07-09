# frozen_string_literal: true

require 'amqp'

module Beetle
  # Our subclass of AMQP::Session which fixes a bug in the ruby AMQP gem
  class AMQPSession < ::AMQP::Session
    # we have to fix a bug in ruby AMQP which mistakes the heartbeat timeout for the heartbeat interval
    def heartbeat_interval
      return 0 if @heartbeat_interval.nil? || @heartbeat_interval <= 0

      [(@heartbeat_interval / 2) - 1, 1].max
    end

  end
end
