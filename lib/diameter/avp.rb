require_relative './avp_parser.rb'
require 'ipaddr'

def b24_to_8_and_16(twentyfourb)
  top_eight = twentyfourb >> 16
  bottom_sixteen = twentyfourb - (top_eight << 16)
  [top_eight, bottom_sixteen]
end

TGPP = 10_415

GROUPED = 0
U32 = 1
OCTETSTRING = 2
IPADDR = 3

class AVPNames
  @names = {
    'Vendor-Specific-Application-Id' => [260, GROUPED],
    'Vendor-Id' => [266, U32],
    'Auth-Application-Id' => [258, U32],
    'Session-Id' => [263, OCTETSTRING],
    'Auth-Session-State' => [277, U32],
    'Inband-Security-Id' => [299, U32],
    'Origin-Host' => [264, OCTETSTRING],
    'Result-Code' => [268, U32],
    'Origin-Realm' => [296, OCTETSTRING],
    'Destination-Host' => [293, OCTETSTRING],
    'Destination-Realm' => [283, OCTETSTRING],
    'User-Name' => [1, OCTETSTRING],
    'Host-IP-Address' => [257, IPADDR],
    'Public-Identity' => [601, OCTETSTRING, TGPP],
    'Server-Name' => [602, OCTETSTRING, TGPP],
    'SIP-Number-Auth-Items' => [607, U32, TGPP],
    'SIP-Auth-Data-Item' => [612, GROUPED, TGPP],
    'SIP-Item-Number' => [613, U32, TGPP],
    'SIP-Authentication-Scheme' => [608, OCTETSTRING, TGPP] }

  def self.get(name)
    @names[name]
  end
end

class AVP
  attr_reader :code, :mandatory

  include AVPParser

  def initialize(options = {})
    @code = options[:code] || 0
    @content = options[:content] || ''
    @mandatory = options[:mandatory] || true
  end

  def self.create(name, val)
    code, type, vendor = AVPNames.get(name)
    avp = if vendor
            VendorSpecificAVP.new(code: code, vendor_id: vendor)
          else
            AVP.new(code: code)
          end

    avp.set_content(type, val)

    avp
  end

  def set_content(type, val)
    case type
    when GROUPED
      self.grouped_value = val
    when U32
      self.uint32 = val
    when OCTETSTRING
      self.octet_string = val
    when IPADDR
      self.ip_address = val
    end
  end

  def to_wire
    length = @content.length + 8
    alength_8, alength_16 = b24_to_8_and_16(length)
    avp_flags = '01000000'
    header = [@code, avp_flags, alength_8, alength_16].pack('NB8Cn')
    wire_content = @content
    while ((wire_content.length % 4) != 0)
      wire_content += "\x00"
    end
    header + wire_content
  end

  def to_s
    has_all_ascii_values =
      @content.bytes.reject { |c| (32 < c && c < 126) }.empty?

    could_be_32bit_num = (@content.length == 4)
    could_be_64bit_num = (@content.length == 8)

    could_be_ip = (@content.length == 6 && @content[0..1] == "\x00\x01") ||
      (@content.length == 18 && @content[0..1] == "\x00\x02")

    maybe_grouped = !(has_all_ascii_values ||
                      could_be_64bit_num ||
                      could_be_32bit_num ||
                      could_be_ip)

    s = "AVP #{@code}, mandatory: #{@mandatory}"
    s += ", content as string: #{@content}" if has_all_ascii_values
    s += ", content as int32: #{uint32}" if could_be_32bit_num
    s += ", content as int64: #{uint64}" if could_be_64bit_num
    s += ", content as ip: #{ip_address}" if could_be_ip
    s += ', grouped AVP' if maybe_grouped

    s
  end

  def vendor_specific
    false
  end

  def grouped_value
    parse_avps_int(@content)
  end

  def grouped_value=(avps)
    new_content = ''
    avps.each { |a| new_content += a.to_wire }
    @content = new_content
  end

  def octet_string
    @content
  end

  def octet_string=(val)
    @content = val
  end

  def int32
    @content.unpack('l>')[0]
  end

  def int32=(val)
    @content = [val].pack('l>')
  end

  def int64
    @content.unpack('q>')[0]
  end

  def int64=(val)
    @content = [val].pack('q>')
  end

  def uint32
    @content.unpack('N')[0]
  end

  def uint32=(val)
    @content = [val].pack('N')
  end

  def uint64
    @content.unpack('Q>')[0]
  end

  def uint64=(val)
    @content = [val].pack('Q>')
  end

  def float32
    @content.unpack('g')[0]
  end

  def float32=(val)
    @content = [val].pack('g')
  end

  def float64
    @content.unpack('G')[0]
  end

  def float64=(val)
    @content = [val].pack('G')
  end

  def ip_address
    IPAddr.new_ntoh(@content[2..-1])
  end

  def ip_address=(val)
    bytes = if val.ipv4?
              [1].pack('n')
            else
              [2].pack('n')
            end

    bytes += val.hton
    @content = bytes
  end
end

class VendorSpecificAVP < AVP
  attr_reader :vendor_id

  def initialize(options = {})
    @vendor_id = options[:vendor_id]
    super(options)
  end

  def vendor_specific
    true
  end

  def to_wire
    length = @content.length + 8
    alength_8, alength_16 = b24_to_8_and_16(length)
    avp_flags = '11000000'
    header = [code, avp_flags, alength_8, alength_16, @vendor_id].pack('NB8CnN')
    wire_content = @content
    while ((wire_content.length % 4) != 0)
      wire_content += "\x00"
    end
    header + wire_content
  end

  def to_s
    "AVP #{@code}, Vendor-ID #{@vendor_id}, mandatory: #{@mandatory}"
  end
end
