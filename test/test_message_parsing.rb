require "minitest_helper"
require "diameter/message"

def parse(filename)
  path = "#{File.dirname(__FILE__)}/test_messages/#{filename}"
  header = IO.binread(path, 4)
  # read the header
  length = DiameterMessage.length_from_header(header)
  bytes = IO.binread(path, length)
  [bytes, DiameterMessage.from_bytes(bytes)]
end

describe "Message parsing", "Parsing a CER" do

  it "can be parsed" do
    _bytes, msg = parse('cer.bin')
    
    msg.command_code.must_equal 257
    msg.request.must_equal true
    msg.avp_by_name("Firmware-Revision").uint32.must_equal 10200
    msg.all_avps_by_name("Host-IP-Address").length.must_equal 2
  end

  it "can generate a response" do
    _bytes, msg = parse('cer.bin')

    cea = msg.create_answer

    cea.command_code.must_equal msg.command_code
    cea.request.must_equal false
  end

  it "serialises back to its original form" do
    bytes, msg = parse('cer.bin')

    msg.to_wire.force_encoding("ASCII-8BIT").must_equal bytes.force_encoding("ASCII-8BIT")
  end

  it "should have a string representation showing its Command-Code and AVPs" do
    _bytes, msg = parse('cer.bin')

    msg.to_s.must_include "257"
    msg.to_s.must_include "172.24.68.104" # Host-IP-Address
  end

end

describe "Message parsing", "Parsing a MAR" do

  it "can be parsed" do
    _bytes, msg = parse('mar.bin')

    msg.command_code.must_equal 303
    msg.request.must_equal true
    msg.avp_by_name("SIP-Auth-Data-Item").inner_avp("SIP-Authentication-Scheme").octet_string.must_equal "Unknown"
  end

  it "serialises back to its original form" do
    bytes, msg = parse('mar.bin')

    msg.to_wire.length.must_equal bytes.length
    msg.to_wire.force_encoding("ASCII-8BIT").must_equal bytes.force_encoding("ASCII-8BIT")
  end

end
