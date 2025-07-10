# frozen_string_literal: true

require 'eventmachine'

module Beetle
  include EM::Deferrable

  class AwaitLatch
    def initialize(expected_count, timeout = nil)
      @expected_count = expected_count
      @timeout = timeout
      @completed_count = 0
      @results = []

      return unless timeout

      EM.add_timer(timeout) do
        self.fail(:timeout) unless completed?
      end
    end

    def succeed_one(result)
      return if @completed >= @expected

      @results << result
      @completed += 1

      succeed(@results) if completed?
    end

    def fail_one(_error)
      @results << nil
      @completed += 1

      succeed(@results) if completed?
    end

    def completed?
      @completed_count >= @expected_count
    end
  end
end
