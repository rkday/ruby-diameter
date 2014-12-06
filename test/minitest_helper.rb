require 'simplecov'

SimpleCov.start do
  add_filter "/test/"

  # Untestable code - encapsulates the network interactions
  add_filter "/stack_transport_helpers.rb"
end

require "minitest/autorun"
require "diameter/diameter_logger"

stdout_logger = Logger.new(STDOUT, 10, (1024^3))

Diameter::set_logger(stdout_logger)
if ENV['DEBUG_LOGS']
  puts 'debug'
  Diameter::logger.level = Logger::DEBUG
else
  Diameter::logger.level = Logger::UNKNOWN
end
