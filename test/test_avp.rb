require "minitest/autorun"
require_relative "../lib/diameter/avp.rb"

describe "AVP", "A simple example" do

  it "can create an Unsigned32 AVP" do
    avp = AVP.create("Inband-Security-Id", 0)
    avp.code.must_equal 299
    avp.uint32.must_equal 0

    # Wire representation taken from Wireshark
    avp.to_wire.must_equal "\x00\x00\x01\x2b\x40\x00\x00\x0c\x00\x00\x00\x00"
  end

  it "can create an unpadded string AVP" do
    avp = AVP.create("Origin-Host", "abcde")
    avp.code.must_equal 264
    avp.octet_string.must_equal "abcde"

    avp.to_wire.must_equal "\x00\x00\x01\x08\x40\x00\x00\rabcde\x00\x00\x00"
  end

  it "can create a padded string AVP" do
    avp = AVP.create("Origin-Host", "abcdefgh")
    avp.code.must_equal 264
    avp.octet_string.must_equal "abcdefgh"

    avp.to_wire.must_equal "\x00\x00\x01\x08\x40\x00\x00\x10abcdefgh"
  end

  it "can create an IPv4 address AVP" do
    avp = AVP.create("Host-IP-Address", IPAddr.new("172.24.67.24"))
    avp.code.must_equal 257
    avp.ip_address.must_equal IPAddr.new("172.24.67.24")

    # Wire representation taken from Wireshark
    avp.to_wire.must_equal "\x00\x00\x01\x01\x40\x00\x00\x0e\x00\x01\xac\x18\x43\x18\x00\x00".force_encoding("ASCII-8BIT")
  end

  it "can create a grouped AVP" do
    avp = AVP.create("Vendor-Specific-Application-Id",
                     [AVP.create("Auth-Application-Id", 16777216),
                     AVP.create("Vendor-Id", 10415)])
    avp.code.must_equal 260

    avp.inner_avp("Vendor-Id").code.must_equal 266
    avp.inner_avp("Vendor-Id").uint32.must_equal 10415

    # Wire representation taken from Wireshark
    avp.to_wire.must_equal "\x00\x00\x01\x04\x40\x00\x00\x20\x00\x00\x01\x02\x40\x00\x00\x0c\x01\x00\x00\x00\x00\x00\x01\x0a\x40\x00\x00\x0c\x00\x00\x28\xaf".force_encoding("ASCII-8BIT")
  end

  it "can create a vendor-specific AVP" do
    avp = AVP.create("SIP-Number-Auth-Items", 1)
    avp.code.must_equal 607
    avp.uint32.must_equal 1
    avp.vendor_id.must_equal 10415

    # Wire representation taken from Wireshark
    avp.to_wire.must_equal "\x00\x00\x02\x5f\xc0\x00\x00\x10\x00\x00\x28\xaf\x00\x00\x00\x01".force_encoding("ASCII-8BIT")
  end

end
