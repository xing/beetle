# frozen_string_literal: true
module Arel
  module Visitors
    class Visitor
      def initialize
        @dispatch = get_dispatch_cache
      end

      def accept object
        visit object
      end

      private

      def self.dispatch_cache
        Hash.new do |hash, klass|
          hash[klass] = "visit_#{(klass.name || '').gsub('::', '_')}"
        end
      end

      def get_dispatch_cache
        self.class.dispatch_cache
      end

      def dispatch
        @dispatch
      end

      def visit object
        dispatch_method = dispatch[object.class]
        send dispatch_method, object
      rescue NoMethodError => e
        raise e if respond_to?(dispatch_method, true)
        superklass = object.class.ancestors.find { |klass|
          respond_to?(dispatch[klass], true)
        }
        raise(TypeError, "Cannot visit #{object.class}") unless superklass
        dispatch[object.class] = dispatch[superklass]
        retry
      end
    end
  end
end
