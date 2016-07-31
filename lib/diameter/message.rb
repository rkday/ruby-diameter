require 'diameter/avp_parser'
require 'diameter/u24'

# The Diameter module
module Diameter
  # A Diameter message.
  #
  # @!attribute [r] version
  #   The Diameter protocol version (currently always 1)
  # @!attribute [r] command_code
  #   The Diameter Command-Code of this messsage.
  # @!attribute [r] app_id
  #   The Diameter application ID of this message, or 0 for base
  #   protocol messages.
  # @!attribute [r] hbh
  #   The hop-by-hop identifier of this message.
  # @!attribute [r] ete
  #   The end-to-end identifier of this message.
  # @!attribute [r] request
  #   Whether this message is a request.
  # @!attribute [r] answer
  #   Whether this message is an answer.
  class Message
    attr_reader :version, :command_code, :app_id, :hbh, :ete, :request, :answer
    include Internals

    # Creates a new Diameter message.
    #
    # @param [Hash] options The options
    # @option options [Fixnum] command_code
    #   The Diameter Command-Code of this messsage.
    # @option options [Fixnum] app_id
    #   The Diameter application ID of this message, or 0 for base
    #   protocol messages.
    # @option options [Fixnum] hbh
    #   The hop-by-hop identifier of this message.
    # @option options [Fixnum] ete
    #   The end-to-end identifier of this message.
    # @option options [true, false] request
    #   Whether this message is a request. Defaults to true.
    # @option options [true, false] proxyable
    #   Whether this message can be forwarded on. Defaults to true.
    # @option options [true, false] error
    #   Whether this message is a Diameter protocol error. Defaults to false.
    # @option options [Array<AVP>] avps
    #   The list of AVPs to include on this message.
    def initialize(options = {})
      @version = 1
      @command_code = options[:command_code]
      @app_id = options[:app_id]
      @hbh = options[:hbh] || Message.next_hbh
      @ete = options[:ete] || Message.next_ete

      @request = options.fetch(:request, true)
      @answer = !@request
      @proxyable = options.fetch(:proxyable, false)
      @retransmitted = false
      @error = false

      @avps = options[:avps] || []
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
      length_8, length_16 = Internals::UInt24.to_u8_and_u16(content.length + 20)
      code_8, code_16 = Internals::UInt24.to_u8_and_u16(@command_code)
      request_flag = @request ? '1' : '0'
      proxy_flag = @proxyable ? '1' : '0'
      flags_str = "#{request_flag}#{proxy_flag}000000"

      header = [@version, length_8, length_16, flags_str, code_8, code_16, @app_id, @hbh, @ete].pack('CCnB8CnNNN')
      header + content
    end

    # @!group AVP retrieval

    # Returns the first AVP with the given name. Only covers "top-level"
    # AVPs - it won't look inside Grouped AVPs.
    #
    # Also available as [], e.g. message['Result-Code']
    #
    # @param name [String] The AVP name, either one predefined in
    #   {Constants::AVAILABLE_AVPS} or user-defined with {AVP.define}
    #
    # @return [AVP] if there is an AVP with that name
    # @return [nil] if there is not an AVP with that name
    def avp_by_name(name)
      code, _type, vendor = Internals::AVPNames.get(name)
      avp_by_code(code, vendor)
    end

    # Returns all AVPs with the given name. Only covers "top-level"
    # AVPs - it won't look inside Grouped AVPs.
    #
    # @param name [String] The AVP name, either one predefined in
    #   {Constants::AVAILABLE_AVPS} or user-defined with {AVP.define}
    #
    # @return [Array<AVP>]
    def all_avps_by_name(name)
      code, _type, vendor = Internals::AVPNames.get(name)
      all_avps_by_code(code, vendor)
    end

    alias_method :avp, :avp_by_name
    alias_method :[], :avp_by_name
    alias_method :avps, :all_avps_by_name

    # @private
    # Prefer AVP.define and the by-name versions to this
    #
    # Returns the first AVP with the given code and vendor. Only covers "top-level"
    # AVPs - it won't look inside Grouped AVPs.
    #
    # @param code [Fixnum] The AVP Code
    # @param vendor [Fixnum] Optional vendor ID for a vendor-specific
    #   AVP.
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

    # @private
    # Prefer AVP.define and the by-name versions to this
    #
    # Returns all AVPs with the given code and vendor. Only covers "top-level"
    # AVPs - it won't look inside Grouped AVPs.
    #
    # @param code [Fixnum] The AVP Code
    # @param vendor [Fixnum] Optional vendor ID for a vendor-specific
    #   AVP.
    # @return [Array<AVP>]
    def all_avps_by_code(code, vendor = 0)
      @avps.select do |a|
        vendor_match =
          if a.vendor_specific?
            a.vendor_id == vendor
          else
            vendor == 0
          end
        (a.code == code) && vendor_match
      end
    end

    # Does this message contain a (top-level) AVP with this name?
    # @param name [String] The AVP name, either one predefined in
    #   {Constants::AVAILABLE_AVPS} or user-defined with {AVP.define}
    #
    # @return [true, false]  
    def has_avp?(name)
      !!avp(name)
    end

    # @private
    #
    # Not recommended for normal use - all AVPs should be given to the
    # constructor. Used to allow the stack to add appropriate
    # Origin-Host/Origin-Realm AVPs to outbound messages.
    #
    # @param host [String] The Diameter Identity for the stack.
    # @param realm [String] The Diameter realm for the stack.
    def add_origin_host_and_realm(host, realm)
      @avps << AVP.create("Origin-Host", host) unless has_avp? 'Origin-Host'
      @avps << AVP.create("Origin-Realm", realm) unless has_avp? 'Origin-Realm'
    end
    
    # @!endgroup

    # @!group Parsing
    
    # Parses the first four bytes of the Diameter header to learn the
    # length. Callers should use this to work out how many more bytes
    # they need to read off a TCP connection to pass to self.from_bytes.
    #
    # @param header [String] A four-byte Diameter header
    # @return [Fixnum] The message length field from the header
    def self.length_from_header(header)
      _version, length_8, length_16 = header.unpack('CCn')
      Internals::UInt24.from_u8_and_u16(length_8, length_16)
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
      command_code = Internals::UInt24.from_u8_and_u16(code_8, code_16)

      request = (flags_str[0] == '1')
      proxyable = (flags_str[1] == '1')

      avps = Internals::AVPParser.parse_avps_int(bytes[20..-1])
      Message.new(version: version, command_code: command_code, app_id: app_id, hbh: hbh, ete: ete, request: request, proxyable: proxyable, retransmitted: false, error: false, avps: avps)
    end
    
    # @!endgroup

    # Generates an answer to this request, filling in a Result-Code or
    # Experimental-Result AVP.
    #
    # @param result_code [Fixnum] The value for the Result-Code AVP
    # @option opts [Fixnum] experimental_result_vendor
    #   If given, creates an Experimental-Result AVP with this vendor
    #   instead of the Result-Code AVP. 
    # @option opts [Array<String>] copying_avps
    #   A list of AVP names to copy from the request to the answer.
    # @option opts [Array<Diameter::AVP>] avps
    #   A list of AVP objects to add on the answer.
    # @return [Diameter::Message] The response created.
    def create_answer(result_code, opts={})
      fail "Cannot answer an answer" if answer
      
      avps = []
      avps << avp_by_name("Session-Id") unless avp_by_name("Session-Id").nil?
      avps += opts.fetch(:avps, [])
      avps << if opts[:experimental_result_vendor]
                AVP.create("Experimental-Result",
                           [AVP.create("Experimental-Result-Code", result_code),
                            AVP.create("Vendor-Id", opts[:experimental_result_vendor])])
              else
                AVP.create("Result-Code", result_code)
              end
      
      avps += opts.fetch(:copying_avps, []).collect do |name|
        src_avp = avp_by_name(name)

        fail if src_avp.nil?
        
        src_avp.dup
      end

      Message.new(version: version, command_code: command_code, app_id: app_id, hbh: hbh, ete: ete, request: false, proxyable: @proxyable, retransmitted: false, error: false, avps: avps)
    end

    private
    def self.next_hbh
      @hbh ||= rand(10000)
      @hbh += 1
      @hbh
    end

    def self.next_ete
      @ete ||= (Time.now.to_i & 0x00000fff) + (rand(2**32) & 0xfffff000)
      @ete += 1
    end

  end
end
