require 'securerandom'

module Beetle
  # Provides a thread-local storage for channels which must not be shared between threads.
  # The current implementation claims the :beetle_publisher_channels key in the current thread
  # and maintains a hash that indexes object_ids to their channels.
  # This way channels are thread scoped and instance scoped. (Multiple publishers can have distinct channels)
  #
  # Performance: Normally you'd want to have fast access to local variables, and an ideal implementation uses an array, instead
  # of a hash as the underlying store (see also concurrent-ruby ThreadLocalVar). For our case however, this is good enough.
  #
  # Caution:
  #
  # Currently, there is the potential to create a space leak in the internal storage.
  # If you create Channels instances, and you don't call #cleanup explicitely, the internal storage will not be garbage collected.
  # Usually you have one Channels instance per publisher, so that should be fine.
  #
  # We can't use finalizers for that since they run on a different thread.
  # Best practice would be use `ensure` to cleanup the Channels instance once it's no longer needed.
  class Channels
    def initialize
      @uuid = SecureRandom.uuid
      Thread.current[:beetle_publisher_channels] ||= {}
      Thread.current[:beetle_publisher_channels][@uuid] = {}
    end

    def []=(server, channel)
      Thread.current[:beetle_publisher_channels][@uuid][server] = channel
    end

    def [](server)
      Thread.current[:beetle_publisher_channels][@uuid][server]
    end

    def cleanup!
      Thread.current[:beetle_publisher_channels][@uuid] = {}
    end
  end
end
