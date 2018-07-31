module Beetle
  module RC #:nodoc:all

    # message processing result return codes
    class ReturnCode
      def initialize(*args)
        @reject = args.delete :reject
        @failure = args.delete :failure
        @name = args.first
      end

      def inspect
        @name.blank? ? super : "Beetle::RC::#{@name}"
      end

      def reject?
        @reject
      end

      def failure?
        @failure
      end
    end

    def self.rc(name, *args)
      const_set name, ReturnCode.new(name, *args)
    end

    rc :OK
    rc :Ancient
    rc :AttemptsLimitReached, :failure
    rc :ExceptionsLimitReached, :failure
    rc :ExceptionNotAccepted, :failure
    rc :Delayed, :reject
    rc :HandlerCrash, :reject
    rc :HandlerNotYetTimedOut, :reject
    rc :MutexLocked, :reject
    rc :InternalError, :reject
    rc :DecodingError, :failure

  end
end
