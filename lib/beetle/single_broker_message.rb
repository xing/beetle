module Beetle
  class SingleBrokerMessage < Message
    def set_timeout!; end
    def timed_out?(_t = nil) = false
    def timed_out!; end

    def redundant?
      false
    end

    def aquire_mutex!
      true
    end

    def delete_mutex!
      true
    end
  end
end
