require "minitest_helper"
require "diameter/message"

describe "Message parsing", "Parsing a CER" do

  it "can be parsed" do
    header = IO.binread('test_messages/cer.bin', 20)
    # read the header
    msg = DiameterMessage.from_header(header)
    avps = IO.binread('test_messages/cer.bin', msg.length-20, 20)
    msg.parse_avps(avps)

    msg.command_code.must_equal 257
    msg.request.must_equal true
    msg.avp_by_name("Firmware-Revision").uint32.must_equal 10200
  end

  it "can generate a response" do
    header = IO.binread('test_messages/cer.bin', 20)
    # read the header
    msg = DiameterMessage.from_header(header)
    avps = IO.binread('test_messages/cer.bin', msg.length-20, 20)
    msg.parse_avps(avps)

    cea = msg.response

    cea.command_code.must_equal msg.command_code
    cea.request.must_equal false
  end

  it "serialises back to its original form" do
    bytes = IO.binread('test_messages/cer.bin')
    header = bytes[0..20]
    # read the header
    msg = DiameterMessage.from_header(header)
    avps = bytes[20..-1]
    msg.parse_avps(avps)

    msg.to_wire.force_encoding("ASCII-8BIT").must_equal bytes.force_encoding("ASCII-8BIT")
  end

  it "should have a string representation showing its Command-Code and AVPs" do
    bytes = IO.binread('test_messages/cer.bin')
    header = bytes[0..20]
    # read the header
    msg = DiameterMessage.from_header(header)
    avps = bytes[20..-1]
    msg.parse_avps(avps)

    msg.to_s.must_include "257"
    msg.to_s.must_include "172.24.68.104" # Host-IP-Address
  end

end

describe "Message parsing", "Parsing a MAR" do

  it "can be parsed" do
    header = IO.binread('test_messages/mar.bin', 20)
    # read the header
    msg = DiameterMessage.from_header(header)
    avps = IO.binread('test_messages/mar.bin', msg.length-20, 20)
    msg.parse_avps(avps)

    msg.command_code.must_equal 303
    msg.request.must_equal true
    msg.avp_by_name("SIP-Auth-Data-Item").inner_avp("SIP-Authentication-Scheme").octet_string.must_equal "Unknown"
  end

  it "serialises back to its original form" do
    bytes = IO.binread('test_messages/mar.bin')
    header = bytes[0..20]
    # read the header
    msg = DiameterMessage.from_header(header)
    avps = bytes[20..-1]
    msg.parse_avps(avps)

    msg.to_wire.length.must_equal bytes.length
    msg.to_wire[0..54].force_encoding("ASCII-8BIT").must_equal bytes[0..54].force_encoding("ASCII-8BIT")
  end

end
