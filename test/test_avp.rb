require 'minitest_helper'
require 'diameter/avp'

include Diameter

describe 'AVP', 'A simple example' do

  it 'can create an Unsigned32 AVP' do
    avp = AVP.create('Inband-Security-Id', 0)
    avp.code.must_equal 299
    avp.uint32.must_equal 0

    # Wire representation taken from Wireshark
    avp.to_wire.must_equal "\x00\x00\x01\x2b\x40\x00\x00\x0c\x00\x00\x00\x00"
  end

  it 'can create an unpadded string AVP' do
    avp = AVP.create('Origin-Host', 'abcde')
    avp.code.must_equal 264
    avp.octet_string.must_equal 'abcde'

    avp.to_wire.must_equal "\x00\x00\x01\x08\x40\x00\x00\rabcde\x00\x00\x00"
  end

  it 'can create a padded string AVP' do
    avp = AVP.create('Origin-Host', 'abcdefgh')
    avp.code.must_equal 264
    avp.octet_string.must_equal 'abcdefgh'

    avp.to_wire.must_equal "\x00\x00\x01\x08\x40\x00\x00\x10abcdefgh"
  end

  it 'can create an IPv4 address AVP' do
    avp = AVP.create('Host-IP-Address', IPAddr.new('172.24.67.24'))
    avp.code.must_equal 257
    avp.ip_address.must_equal IPAddr.new('172.24.67.24')

    # Wire representation taken from Wireshark
    avp.to_wire
      .must_equal "\x00\x00\x01\x01\x40\x00"\
    "\x00\x0e\x00\x01\xac\x18\x43\x18\x00\x00"
      .force_encoding('ASCII-8BIT')

    # Check that the string form includes the IP address
    avp.to_s.must_include '172.24.67.24'
  end

  it 'can create an IPv6 address AVP' do
    avp = AVP.create('Host-IP-Address', IPAddr.new('::1'))
    avp.code.must_equal 257
    avp.ip_address.must_equal IPAddr.new('::1')

    # Check that the string form includes the IP address
    avp.to_s.must_include '::1'
  end

  it 'can create a grouped AVP' do
    avp = AVP.create('Vendor-Specific-Application-Id',
                     [AVP.create('Auth-Application-Id', 16_777_216),
                      AVP.create('Vendor-Id', 10_415)])
    avp.code.must_equal 260

    avp.inner_avp('Vendor-Id').code.must_equal 266
    avp.inner_avp('Vendor-Id').uint32.must_equal 10_415

    # Wire representation taken from Wireshark
    avp.to_wire
      .must_equal "\x00\x00\x01\x04\x40\x00\x00"\
    "\x20\x00\x00\x01\x02\x40\x00\x00\x0c\x01\x00"\
    "\x00\x00\x00\x00\x01\x0a\x40\x00\x00\x0c\x00"\
    "\x00\x28\xaf".force_encoding('ASCII-8BIT')
  end

  it 'can create a vendor-specific AVP' do
    avp = AVP.create('SIP-Number-Auth-Items', 1)
    avp.code.must_equal 607
    avp.uint32.must_equal 1
    avp.vendor_id.must_equal 10_415

    # Check that the string form includes the Vendor-ID
    avp.to_s.must_include '10415'

    # Wire representation taken from Wireshark
    avp.to_wire.must_equal "\x00\x00\x02\x5f\xc0\x00\x00"\
    "\x10\x00\x00\x28\xaf\x00\x00\x00\x01".force_encoding('ASCII-8BIT')
  end

  it 'can create a non-mandatory AVP' do
    avp = AVP.create('Firmware-Revision', 10_200, mandatory: false)
    avp.code.must_equal 267
    avp.uint32.must_equal 10_200

    # Wire representation taken from Wireshark
    avp.to_wire.must_equal "\x00\x00\x01\x0b\x00\x00\x00"\
    "\x0c\x00\x00\x27\xd8".force_encoding('ASCII-8BIT')
  end

  it 'can get/set an Unsigned64 AVP' do
    avp = AVP.create('Inband-Security-Id', 0)

    avp.uint64 = 117

    avp.uint64.must_equal 117
    avp.octet_string.length.must_equal 8
  end

  it 'can get/set an Integer32 AVP' do
    avp = AVP.create('Inband-Security-Id', 0)

    avp.int32 = -117

    avp.int32.must_equal(-117)
    avp.octet_string.length.must_equal 4
  end

  it 'can get/set an Integer64 AVP' do
    avp = AVP.create('Inband-Security-Id', 0)

    avp.int64 = -117

    avp.int64.must_equal(-117)
    avp.octet_string.length.must_equal 8
  end

  it 'can get/set a Float32 AVP' do
    avp = AVP.create('Inband-Security-Id', 0)

    avp.float32 = 39.0625
    # 10000/256 - IEEE floating point won't
    # mangle this

    avp.float32.must_equal 39.0625
    avp.octet_string.length.must_equal 4
  end

  it 'can get/set a Float64 AVP' do
    avp = AVP.create('Inband-Security-Id', 0)

    avp.float64 = 39.0625
    # 10000/256 - IEEE floating point won't
    # mangle this

    avp.float64.must_equal 39.0625
    avp.octet_string.length.must_equal 8
  end

  it 'can handle user-defined AVP' do
    AVP.define('My-Own-Personal-AVP', 1004, AVPType::U32, 100)
    avp = AVP.create('My-Own-Personal-AVP', 0)

    avp.octet_string.length.must_equal 4
  end
end
