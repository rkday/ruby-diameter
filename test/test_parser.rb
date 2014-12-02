require "minitest/autorun"
require_relative "../lib/diameter/avp.rb"

describe "AVP", "A simple example" do

  it "can create a integer AVP" do
    avp = AVP.create("Inband-Security-Id", 0)
    avp.code.must_equal 299
    avp.uint32.must_equal 0

    # Wire representation taken from Wireshark
    avp.to_wire.must_equal "\x00\x00\x01\x2b\x40\x00\x00\x0c\x00\x00\x00\x00"
  end

end
