module Beetle
  module RC

    # message processing result return codes
    class ReturnCode
      def initialize(*args)
        @recover = args.delete :recover
        @failure = args.delete :failure
        @name = args.first
      end

      def inspect
        @name.blank? ? super : "Beetle::RC::#{@name}"
      end

      def recover?
        @recover
      end

      def failure?
        @failure
      end
    end

    def self.rc(name, *args)
      const_set name, ReturnCode.new(name, *args)
    end

    rc :OK
    rc :Ancient, :failure
    rc :AttemptsLimitReached, :failure
    rc :ExceptionsLimitReached, :failure
    rc :Delayed, :recover
    rc :HandlerCrash, :recover
    rc :HandlerNotYetTimedOut, :recover
    rc :MutexLocked, :recover
    rc :InternalError, :recover

  end
end
