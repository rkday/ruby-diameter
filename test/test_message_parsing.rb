require "minitest_helper"
require "diameter/message"

describe "Message parsing", "Parsing a CER" do

  it "can be parsed" do
    header = IO.binread('test_messages/cer.bin', 20)
    # read the header
    msg = DiameterMessage.from_header(header)
    avps = IO.binread('diameter.bin', msg.length-20, 20)
    msg.parse_avps(avps)
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

end
