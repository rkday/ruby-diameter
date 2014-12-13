require 'diameter/avp_parser'
require 'diameter/u24'
require 'ipaddr'

module Diameter
  # Contains Vendor-ID constants
  module Vendor
    # The 3GPP/IMS Vendor-ID
    TGPP = 10_415
  end

  # Represents the type of data a particular AVP should be interpreted
  # as.
  module AVPType
    # Represents an AVP of Grouped type
    GROUPED = :Grouped

    # Represents an AVP of Unsigned32 type
    U32 = :Unsigned32

    # Represents an AVP of OctetString type
    OCTETSTRING = :OctetString

    # Represents an AVP of IPAddress type
    IPADDR = :Address
  end

  include AVPType

  # The AVPs that can be looked up by name.
  AVAILABLE_AVPS = {
    'Vendor-Specific-Application-Id' => [260, GROUPED],
    'Vendor-Id' => [266, U32],
    'Auth-Application-Id' => [258, U32],
    'Acct-Application-Id' => [259, U32],
    'Session-Id' => [263, OCTETSTRING],
    'Product-Name' => [269, OCTETSTRING],
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
    'Public-Identity' => [601, OCTETSTRING, Vendor::TGPP],
    'Server-Name' => [602, OCTETSTRING, Vendor::TGPP],
    'SIP-Number-Auth-Items' => [607, U32, Vendor::TGPP],
    'SIP-Auth-Data-Item' => [612, GROUPED, Vendor::TGPP],
    'SIP-Item-Number' => [613, U32, Vendor::TGPP],
    'SIP-Authentication-Scheme' => [608, OCTETSTRING, Vendor::TGPP] }

  module Internals
    # Maps AVP names to their on-the-wire values and data definitions.
    class AVPNames
      include AVPType

      @custom_avps = {}
    
      # Converts an AVP name into its code number, data type, and (if
      # applicable) vendor ID.
      #
      # @param [String] name The AVP name
      # @return [Array(Fixnum, AVPType)] if this is not vendor-specific
      # @return [Array(Fixnum, AVPType, Vendor)] if this is vendor-specific
      def self.get(name)
        code, type, vendor = @custom_avps.merge(AVAILABLE_AVPS)[name]
        vendor ||= 0
        fail "AVP name #{name} not recognised" unless code
        [code, type, vendor]
      end

      # @see {AVP.define}
      def self.add(name, code, type, vendor=nil)
        @custom_avps[name] = vendor.nil? ? [code, type] : [code, type, vendor]
      end
    end
  end
  
  # The AVP class is a sensible, coherent whole - it's just big,
  # particularly because of all the various ways to interpret the
  # content. Ignore the class length guidelines.

  # rubocop:disable Metrics/ClassLength

  # Represents a Diameter AVP. Use this for non-vendor-specific AVPs,
  # and its subclass VendorSpecificAVP for ones defined for a particular
  # vendor.
  # @!attribute [r] code
  #   @return [Fixnum] The AVP Code
  # @!attribute [r] mandatory
  #   @return [true, false] Whether this AVP is mandatory (i.e. its M flag is set)
  class AVP
    include Internals
    include AVPType
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
    def self.create(name, val, options = {})
      code, type, vendor = AVPNames.get(name)
      avp = if (vendor != 0)
              VendorSpecificAVP.new(code, vendor, options)
            else
              AVP.new(code, options)
            end

      set_content(avp, type, val)

      avp
    end

    # Defines a new AVP that can subsequently be created/retrieved by
    # name.
    #
    # @param name [String] The AVP name
    # @param code [Fixnum] The AVP Code
    # @param type [AVPType] The type of this AVP's value
    # @param vendor [Fixnum] Optional vendor ID for a vendor-specific
    #   AVP.
    # @return [void]
    def self.define(name, code, type, vendor=nil)
      AVPNames.add(name, code, type, vendor)
    end

    # Returns this AVP encoded properly as bytes in network byte order,
    # suitable for sending over a TCP or SCTP connection. See
    # {http://tools.ietf.org/html/rfc6733#section-4.1} for the
    # format.
    #
    # @return [String] The bytes representing this AVP
    def to_wire
      length_8, length_16 = UInt24.to_u8_and_u16(@content.length + 8)
      avp_flags = @mandatory ? '01000000' : '00000000'
      header = [@code, avp_flags, length_8, length_16].pack('NB8Cn')
      header + padded_content
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
      s += ", grouped AVP, #{grouped_value.collect(&:to_s)}" if maybe_grouped

      s
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity

    # @!attribute [r] vendor_specific?
    #   @return [true, false] Whether this AVP is mandatory
    #   (i.e. its M flag is set)
    def vendor_specific?
      false
    end

    # @!group Data getters/setters for different AVP types

    # Returns this AVP's byte data, interpreted as a
    # {http://tools.ietf.org/html/rfc6733#section-4.4 Grouped AVP}.
    #
    # @return [Array<AVP>] The contained AVPs.
    def grouped_value
      AVPParser.parse_avps_int(@content)
    end

    # Sets this AVP's byte data to a
    # {http://tools.ietf.org/html/rfc6733#section-4.4 Grouped AVP}.
    #
    # @param [Array<AVP>] avps The AVPs that should be contained within
    #   this AVP.
    # @return [void]
    def grouped_value=(avps)
      new_content = ''
      avps.each { |a| new_content += a.to_wire }
      @content = new_content
    end

    # For a grouped AVP, returns the first AVP with this name it
    # contains.
    #
    # @param [String] name The AVP name
    # @return [AVP] if this AVP is found inside the Grouped AVP
    # @return [nil] if this AVP is not found inside the Grouped AVP
    def inner_avp(name)
      avps = inner_avps(name)

      if avps.empty?
        nil
      else
        avps[0]
      end
    end

    # For a grouped AVP, returns all AVPs it contains with this name.
    #
    # @param [String] name The AVP name
    # @return [Array<AVP>]
    def inner_avps(name)
      code, _type, _vendor = AVPNames.get(name)

      grouped_value.select { |a| a.code == code }
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

    # Sets this AVP's byte data to an OctetString.
    #
    # @param [String] value The octets to use as the value.
    # @return [void]
    def octet_string=(value)
      @content = value
    end

    # rubocop:enable Style/TrivialAccessors

    # Returns this AVP's byte data, interpreted as an Integer32.
    #
    # @return [Fixnum] The contained Integer32.
    def int32
      @content.unpack('l>')[0]
    end

    # Sets this AVP's byte data to an Integer32.
    #
    # @param [Fixnum] value
    # @return [void]
    def int32=(value)
      @content = [value].pack('l>')
    end

    # Returns this AVP's byte data, interpreted as an Integer64.
    #
    # @return [Fixnum] The contained Integer64.
    def int64
      @content.unpack('q>')[0]
    end

    # Sets this AVP's byte data to an Integer64.
    #
    # @param [Fixnum] value
    # @return [void]
    def int64=(value)
      @content = [value].pack('q>')
    end

    # Returns this AVP's byte data, interpreted as an Unsigned32.
    #
    # @return [Fixnum] The contained Unsigned32.
    def uint32
      @content.unpack('N')[0]
    end

    # Sets this AVP's byte data to an Unsigned32.
    #
    # @param [Fixnum] value
    # @return [void]
    def uint32=(value)
      @content = [value].pack('N')
    end

    # Returns this AVP's byte data, interpreted as an Unsigned64.
    #
    # @return [Fixnum] The contained Unsigned64.
    def uint64
      @content.unpack('Q>')[0]
    end

    # Sets this AVP's byte data to an Unsigned64.
    #
    # @param [Fixnum] value
    # @return [void]
    def uint64=(value)
      @content = [value].pack('Q>')
    end

    # Returns this AVP's byte data, interpreted as a Float32.
    #
    # @return [Float] The contained Float32.
    def float32
      @content.unpack('g')[0]
    end

    # Sets this AVP's byte data to a Float32.
    #
    # @param [Float] value
    # @return [void]
    def float32=(value)
      @content = [value].pack('g')
    end

    # Returns this AVP's byte data, interpreted as a Float64.
    #
    # @return [Float] The contained Float64.
    def float64
      @content.unpack('G')[0]
    end

    # Sets this AVP's byte data to a Float64.
    #
    # @param [Float] value
    # @return [void]
    def float64=(value)
      @content = [value].pack('G')
    end

    # Returns this AVP's byte data, interpreted as an
    # {http://tools.ietf.org/html/rfc6733#section-4.3.1 Address}.
    #
    # @return [IPAddr] The contained
    #   {http://tools.ietf.org/html/rfc6733#section-4.3.1 Address}.
    def ip_address
      IPAddr.new_ntoh(@content[2..-1])
    end

    # Sets this AVP's byte data to an Address.
    #
    # @param [IPAddr] value
    # @return [void]
    def ip_address=(value)
      bytes = if value.ipv4?
                [1].pack('n')
              else
                [2].pack('n')
              end

      bytes += value.hton
      @content = bytes
    end

    # @!endgroup

    private

    def self.set_content(avp, type, val)
      case type
      when GROUPED
        avp.grouped_value = val
      when U32
        avp.uint32 = val
      when OCTETSTRING
        avp.octet_string = val
      when IPADDR
        avp.ip_address = val
      end
    end

    def to_s_first_line
      "AVP #{@code}, mandatory: #{@mandatory}"
    end

    protected

    def padded_content
      wire_content = @content
      wire_content += "\x00" while ((wire_content.length % 4) != 0)
      wire_content
    end
  end

  # rubocop:enable Metrics/ClassLength

  # A vendor-specific AVP.
  class VendorSpecificAVP < AVP
    attr_reader :vendor_id

    # @param code The AVP Code of this AVP
    # @param vendor_id  The Vendor-ID of this AVP
    # {AVP#initialize}
    def initialize(code, vendor_id, options = {})
      @vendor_id = vendor_id
      super(code, options)
    end

    # {AVP#vendor_specific?}
    def vendor_specific?
      true
    end

    # {AVP#to_wire}
    def to_wire
      length_8, length_16 = UInt24.to_u8_and_u16(@content.length + 12)
      avp_flags = @mandatory ? '11000000' : '10000000'
      header = [@code, avp_flags, length_8, length_16, @vendor_id].pack('NB8CnN')
      header + padded_content
    end

    private

    def to_s_first_line
      "AVP #{@code}, Vendor-ID #{@vendor_id}, mandatory: #{@mandatory}"
    end
  end
end
