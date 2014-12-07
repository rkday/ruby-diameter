require 'logger'

# The Diameter namespace
module Diameter
  @int_DiameterLogger = nil

  # Returns the logger to be used by the Diameter stack and associated
  # objects. If no logger has been set with {Diameter.set_logger},
  # defaults to writing to ./diameterstack.log
  #
  # @return [Logger]
  def self.logger
    @int_DiameterLogger ||= Logger.new('./diameterstack.log', 10, (1024^3))
    @int_DiameterLogger
  end

  # Sets the logger to be used by the Diameter stack and associated
  # objects.
  #
  # @param value [Logger]
  def self.set_logger(value)
    @int_DiameterLogger = value
  end
end
