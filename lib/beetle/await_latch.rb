# frozen_string_literal: true

require 'eventmachine'

module Beetle
  class AwaitLatch
    include EM::Deferrable

    def initialize(expected_count, timeout: nil)
      @expected = expected_count
      @timeout = timeout
      @completed = 0
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
      @completed >= @expected
    end
  end
end
