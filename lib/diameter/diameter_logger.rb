require 'logger'

module Diameter
  @int_DiameterLogger = nil

  def self.logger
    @int_DiameterLogger ||= Logger.new('./diameterstack.log', 10, (1024^3))
    @int_DiameterLogger
  end

  def self.set_logger(value)
    @int_DiameterLogger = value
  end
end
