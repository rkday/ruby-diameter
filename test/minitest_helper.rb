require 'simplecov'

SimpleCov.start do
  add_filter "/test/"

  # Untestable code - encapsulates the network interactions
  add_filter "/stack_transport_helpers.rb"
end

require "minitest/autorun"
