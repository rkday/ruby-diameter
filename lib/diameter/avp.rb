require 'diameter/avp_parser'
require 'diameter/u24'
require 'ipaddr'

TGPP = 10_415

# Represents the type of data a particular AVP should be interpreted
# as. Valid values are:
# * GROUPED
# * U32
# * OCTETSTRING
# * IPADDR
class AVPType
end

GROUPED = AVPType.new
U32 = AVPType.new
OCTETSTRING = AVPType.new
IPADDR = AVPType.new

# Maps AVP names to their on-the-wire values and data definitions.
class AVPNames
  @names = {
    'Vendor-Specific-Application-Id' => [260, GROUPED],
    'Vendor-Id' => [266, U32],
    'Auth-Application-Id' => [258, U32],
    'Session-Id' => [263, OCTETSTRING],
    'Auth-Session-State' => [277, U32],
    'Inband-Security-Id' => [299, U32],
    'Origin-Host' => [264, OCTETSTRING],
    'Firmware-Revision' => [267, U32],
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

  # Converts an AVP name into its code number, data type, and (if
  # applicable) vendor ID.
  #
  # @param [String] name The AVP name
  # @return [Array(Fixnum, AVPType)] if this is not vendor-specific
  # @return [Array(Fixnum, AVPType, Fixnum)] if this is vendor-specific
  def self.get(name)
    code, type, vendor = @names[name]
    vendor ||= 0
    [code, type, vendor]
  end
end

# The AVP class is a sensible, coherent whole - it's just big,
# particularly because of all the various ways to interpret the
# content. Ignore the class length guidelines.

# rubocop:disable Metrics/ClassLength

# Represents a Diameter AVP. Use this for non-vendor-specific AVPs,
# and its subclass VendorSpecificAVP for ones defined for a particular vendor.
class AVP
  attr_reader :code, :mandatory

  include AVPParser

  def initialize(code, options = {})
    @code = code
    @content = options[:content] || ''
    @mandatory = options[:mandatory]
    @mandatory = true if @mandatory.nil?
  end

  # Creates an AVP by name, and assigns it a value.
  #
  # @param name The name of the AVP, e.g. "Origin-Host"
  # @param val The value of the AVP. Must be of the type defined for
  #   that AVP - e.g. a Fixnum for an AVP defined as Unsigned32, a
  #   String for an AVP defined as OctetString, or an IPAddr for an AVP
  #   defined as IPAddress.
  # @return [AVP] The AVP that was created.
  def self.create(name, val, options={})
    code, type, vendor = AVPNames.get(name)
    avp = if (vendor != 0)
            VendorSpecificAVP.new(code, vendor, options)
          else
            AVP.new(code, options)
          end

    avp.set_content(type, val)

    avp
  end

  # Returns this AVP encoded properly as bytes in network byte order,
  # suitable for sending over a TCP or SCTP connection.
  #
  # @return [String] The bytes representing this AVP
  def to_wire
    length_8, length_16 = u24_to_u8_and_u16(@content.length + 8)
    avp_flags = @mandatory ? '01000000' : '00000000'
    header = [@code, avp_flags, length_8, length_16].pack('NB8Cn')
    header + self.padded_content
  end

  def padded_content
    wire_content = @content
    while ((wire_content.length % 4) != 0)
      wire_content += "\x00"
    end
    wire_content
  end
  
  def to_s_first_line
    "AVP #{@code}, mandatory: #{@mandatory}"
  end

  # Guessing the type of an AVP and displaying it sensibly is complex,
  # so this is a complex method (but one that has a unity of purpose,
  # so can't easily be broken down). Disable several Rubocop
  # complexity metrics to reflect this.

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
  # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity

  # Returns a string representation of this AVP. Makes a best-effort
  # attempt to guess the type of the content (even for unknown AVPs)
  # and display it sensibly.
  #
  # @example
  #   avp.to_s => "AVP 267, mandatory: true, content as int32: 1"
  def to_s
    has_all_ascii_values =
      @content.bytes.reject { |c| (32 < c && c < 126) }.empty?

    could_be_32bit_num = (@content.length == 4)
    could_be_64bit_num = (@content.length == 8)

    could_be_ip = ((@content.length == 6 && @content[0..1] == "\x00\x01") ||
                   (@content.length == 18 && @content[0..1] == "\x00\x02"))

    maybe_grouped = !(has_all_ascii_values ||
                      could_be_64bit_num   ||
                      could_be_32bit_num   ||
                      could_be_ip)

    s = to_s_first_line
    s += ", content as string: #{@content}" if has_all_ascii_values
    s += ", content as int32: #{uint32}" if could_be_32bit_num
    s += ", content as int64: #{uint64}" if could_be_64bit_num
    s += ", content as ip: #{ip_address}" if could_be_ip
    s += ', grouped AVP' if maybe_grouped

    s
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity
  # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity

  # Is this AVP vendor-specific or not?
  #
  # @return [true, false]
  def vendor_specific?
    false
  end

  # Returns this AVP's byte data, interpreted as a Grouped AVP.
  #
  # @return [Array<AVP>] The contained AVPs.
  def grouped_value
    parse_avps_int(@content)
  end

  # Sets this AVP's byte data to a Grouped AVP.
  #
  # @param [Array<AVP>] avps The AVPs that should be contained within
  #   this AVP.
  # @return [void]
  def grouped_value=(avps)
    new_content = ''
    avps.each { |a| new_content += a.to_wire }
    @content = new_content
  end

  def inner_avp(name)
    avps = inner_avps(name)

    if avps.empty?
      nil
    else
      avps[0]
    end
  end

  def inner_avps(name)
    code, _type, _vendor = AVPNames.get(name)

    self.grouped_value.select { |a| a.code == code}
  end

  # Even though it is just "the raw bytes in the content",
  # octet_string is only one way of interpreting the AVP content and
  # shouldn't be treated differently to the others, so disable the
  # TrivialAccessors warning.

  # rubocop:disable Style/TrivialAccessors

  # Returns this AVP's byte data, interpreted as an OctetString.
  #
  # @return [String] The contained OctetString.
  def octet_string
    @content
  end

  def octet_string=(val)
    @content = val
  end

  # rubocop:enable Style/TrivialAccessors

  # Returns this AVP's byte data, interpreted as an Integer32.
  #
  # @return [Fixnum] The contained Integer32.
  def int32
    @content.unpack('l>')[0]
  end

  def int32=(val)
    @content = [val].pack('l>')
  end

  # Returns this AVP's byte data, interpreted as an Integer64.
  #
  # @return [Fixnum] The contained Integer64.
  def int64
    @content.unpack('q>')[0]
  end

  def int64=(val)
    @content = [val].pack('q>')
  end

  # Returns this AVP's byte data, interpreted as an Unsigned32.
  #
  # @return [Fixnum] The contained Unsigned32.
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

#  protected
  
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

end



# rubocop:enable Metrics/ClassLength

class VendorSpecificAVP < AVP
  attr_reader :vendor_id

  # @param code
  # @param vendor_id
  # @see AVP#initialize
  def initialize(code, vendor_id, options = {})
    @vendor_id = vendor_id
    super(code, options)
  end

  # @see AVP#vendor_specific?
  def vendor_specific?
    true
  end

  def to_wire
    length_8, length_16 = u24_to_u8_and_u16(@content.length + 12)
    avp_flags = @mandatory ? '11000000' : '10000000'
    header = [@code, avp_flags, length_8, length_16, @vendor_id].pack('NB8CnN')
    header + self.padded_content
  end

  def to_s_first_line
    "AVP #{@code}, Vendor-ID #{@vendor_id}, mandatory: #{@mandatory}"
  end
end
