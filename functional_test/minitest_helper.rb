require 'simplecov'

SimpleCov.start do
  add_filter '/functional_test/'
  command_name "Live Tests"
end

require 'minitest/autorun'
require 'minitest-spec-context'
require 'diameter/diameter_logger'
require 'concurrent'


stdout_logger = Logger.new(STDOUT, 10, (1024 ^ 3))

Diameter.set_logger(stdout_logger)
if ENV['DEBUG_LOGS']
  puts 'debug'
  Diameter.logger.level = Logger::DEBUG
else
  Diameter.logger.level = Logger::UNKNOWN
end

# Compatability with minitest/autorun
Concurrent.configuration.auto_terminate = false

Concurrent.configuration.logger = Proc.new { |level, progname, message = nil, &block| Diameter.logger.debug(message) }

