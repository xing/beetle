require 'rubygems'
require 'active_support'

module Beetle
  module Commands
    def self.execute(command)
      if commands.include? command
        require File.expand_path("../commands/#{command}", __FILE__)        
        "Beetle::Commands::#{command.classify}".constantize.execute
      else
        # me no likez no frikin heredocs
        puts "\nCommand #{command} not known\n" if command
        puts "Available commands are:"
        puts
        commands.each {|c| puts "\t #{c}"}
        puts
        exit 1
      end
    end
    
    private
    def self.commands
      commands_dir = File.expand_path('../commands', __FILE__)
      Dir[commands_dir + '/*.rb'].map {|f| File.basename(f)[0..-4]}
    end
  end
end

Beetle::Commands.execute(ARGV.shift)