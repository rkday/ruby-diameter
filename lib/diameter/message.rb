require 'diameter/avp_parser'
require 'diameter/u24'

# A Diameter message.
#
# @!attribute [r] version
#   The Diameter protocol version (currenmtly always 1)
class DiameterMessage
  attr_reader :version, :command_code, :app_id, :hbh, :ete, :request
  attr_accessor :avps

  def initialize(options = {})
    @version = options[:version] || 1
    @command_code = options[:command_code]
    @avps = options[:avps] || []
    @app_id = options[:app_id]
    @hbh = options[:hbh]
    @ete = options[:ete]

    @request = options.fetch(:request, true)
    @proxyable = options.fetch(:proxyable, false)
    @retransmitted = false
    @error = false
  end

  # Returns true if this message represents a Diameter answer (i.e.
  # has the 'Request' bit in the header cleared).
  #
  # Always the opposite of {DiameterMessage#request}.
  #
  # @return [true, false]
  def answer
    !@request
  end

  # Represents this message (and all its AVPs) in human-readable
  # string form.
  #
  # @see AVP::to_s for how the AVPs are represented.
  # @return [String]
  def to_s
    "#{@command_code}: #{@avps.collect(&:to_s)}"
  end

  # Serializes a Diameter message (header plus AVPs) into the series
  # of bytes representing it on the wire.
  #
  # @return [String] The byte-encoded form.
  def to_wire
    content = ''
    @avps.each { |a| content += a.to_wire }
    length_8, length_16 = UInt24.to_u8_and_u16(content.length + 20)
    code_8, code_16 = UInt24.to_u8_and_u16(@command_code)
    request_flag = @request ? '1' : '0'
    proxy_flag = @proxyable ? '1' : '0'
    flags_str = "#{request_flag}#{proxy_flag}000000"

    header = [@version, length_8, length_16, flags_str, code_8, code_16, @app_id, @hbh, @ete].pack('CCnB8CnNNN')
    header + content
  end

  # Returns the first AVP with the given name. Only covers "top-level"
  # AVPs - it won't look inside Grouped AVPs.
  #
  # @return [AVP] if there is an AVP with that name
  # @return [nil] if there is not an AVP with that name
  def avp_by_name(name)
    code, _type, vendor = AVPNames.get(name)
    avp_by_code(code, vendor)
  end

  # Returns all AVPs with the given name. Only covers "top-level"
  # AVPs - it won't look inside Grouped AVPs.
  #
  # @return [Array<AVP>]
  def all_avps_by_name(name)
    code, _type, vendor = AVPNames.get(name)
    all_avps_by_code(code, vendor)
  end

  # Returns the first AVP with the given code and vendor. Only covers "top-level"
  # AVPs - it won't look inside Grouped AVPs.
  #
  # @return [AVP] if there is an AVP with that code/vendor
  # @return [nil] if there is not an AVP with that code/vendor
  def avp_by_code(code, vendor = 0)
    avps = all_avps_by_code(code, vendor)
    if avps.empty?
      nil
    else
      avps[0]
    end
  end

  # Returns all AVPs with the given code and vendor. Only covers "top-level"
  # AVPs - it won't look inside Grouped AVPs.
  #
  # @return [Array<AVP>]
  def all_avps_by_code(code, vendor = 0)
    avps.select do |a|
      vendor_match =
        if a.vendor_specific?
          a.vendor_id == vendor
        else
          vendor == 0
        end
      (a.code == code) && vendor_match
    end
  end

  # Parses the first four bytes of the Diameter header to learn the
  # length. Callers should use this to work out how many more bytes
  # they need to read off a TCP connection to pass to self.from_bytes.
  #
  # @param header [String] A four-byte Diameter header
  # @return [Fixnum] The message length field from the header
  def self.length_from_header(header)
    _version, length_8, length_16 = header.unpack('CCn')
    UInt24.from_u8_and_u16(length_8, length_16)
  end

  # Parses a byte representation (a 20-byte header plus AVPs) into a
  # DiameterMessage object.
  #
  # @param bytes [String] The on-the-wire byte representation of a
  #   Diameter message.
  # @return [DiameterMessage] The parsed object form.
  def self.from_bytes(bytes)
    header = bytes[0..20]
    version, _length_8, _length_16, flags_str, code_8, code_16, app_id, hbh, ete = header.unpack('CCnB8CnNNN')
    command_code = UInt24.from_u8_and_u16(code_8, code_16)

    request = (flags_str[0] == '1')
    proxyable = (flags_str[1] == '1')

    avps = AVPParser.parse_avps_int(bytes[20..-1])
    DiameterMessage.new(version: version, command_code: command_code, app_id: app_id, hbh: hbh, ete: ete, request: request, proxyable: proxyable, retransmitted: false, error: false, avps: avps)
  end

  # Generates an answer to this request, filling in appropriate
  # fields per {http://tools.ietf.org/html/rfc6733#section-6.2}.
  #
  # @param origin_host [String] The Origin-Host to fill in on the
  #   response.
  # @return [DiameterMessage] The response created.
  def create_answer(response_code, opts={})
    avps = []
    avps << if opts[:experimental_result_vendor]
              fail
            else
              AVP.create("Result-Code", response_code)
            end
    
    avps += opts.fetch(:copying_avps, []).collect do |name|
      src_avp = avp_by_name(name)

      fail if src_avp.nil?
  
      src_avp.dup
    end

    # Is this a request?

    DiameterMessage.new(version: version, command_code: command_code, app_id: app_id, hbh: hbh, ete: ete, request: false, proxyable: @proxyable, retransmitted: false, error: false, avps: avps)
  end
end
