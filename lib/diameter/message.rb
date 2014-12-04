require 'diameter/avp_parser'
require 'diameter/u24'

class DiameterMessage
  include AVPParser
  
  attr_reader :version, :command_code, :app_id, :hbh, :ete, :request
  attr_accessor :avps
  
  def initialize(options={})
    @version = options[:version] || 1
    @command_code = options[:command_code]
    @avps = options[:avps] || []
    @length = options[:length] || nil
    @app_id = options[:app_id]
    @hbh = options[:hbh]
    @ete = options[:ete]

    @request = options[:request] || false
    @proxyable = options[:proxyable] || false
    @retransmitted = false
    @error = false
  end

  def to_s
    "#{@command_code}: #{@avps.collect{|a| a.to_s }}"
  end

  def to_wire
    content = ""
    @avps.each {|a| content += a.to_wire}
    length_8, length_16 = u24_to_u8_and_u16(content.length + 20)
    code_8, code_16 = u24_to_u8_and_u16(@command_code)
    request_flag = @request ? "1" : "0"
    proxy_flag = @proxyable? "1" : "0"
    flags_str = "#{request_flag}#{proxy_flag}000000"
    
    header = [@version, length_8, length_16, flags_str, code_8, code_16, @app_id, @hbh, @ete].pack('CCnB8CnNNN')
    header + content
  end
  
  def length
    @length
  end

  def avp_by_name(name)
    code, _type, vendor = AVPNames.get(name)
    avp_by_code(code, vendor)
  end

  def all_avps_by_name(name)
    code, _type, vendor = AVPNames.get(name)
    all_avps_by_code(code, vendor)
  end

  def avp_by_code(code, vendor=0)
    avps = all_avps_by_code(code, vendor)
    if avps.empty?
      nil
    else
      avps[0]
    end
  end

  def all_avps_by_code(code, vendor=0)
    avps.select do |a|
      vendor_match =
        if a.vendor_specific?
          a.vendor_id == vendor
        else
          vendor == 0
        end
      (a.code == code) and vendor_match
    end
  end

  def self.from_header(header)
    version, length_8, length_16, flags_str, code_8, code_16, app_id, hbh, ete = header.unpack('CCnB8CnNNN')
    length = u8_and_u16_to_u24(length_8, length_16)
    command_code = u8_and_u16_to_u24(code_8, code_16)

    request = (flags_str[0] == "1")
    proxyable = (flags_str[1] == "1")
    DiameterMessage.new(version: version, length: length, command_code: command_code, app_id: app_id, hbh: hbh, ete: ete, request: request, proxyable: proxyable, retransmitted: false, error: false)
  end

  def response(origin_host=nil)
    # Is this a request?

    # Copy the Session-Id and Proxy-Info

    # Insert Origin-Host (should the stack do this?)

    # Don't require or insert a Result-Code - we might want
    # Experimental-Result-Code instead

    DiameterMessage.new(version: version, command_code: command_code, app_id: app_id, hbh: hbh, ete: ete, request: false, proxyable: @proxyable, retransmitted: false, error: false)
  end

  def parse_avps(bytes)
    @avps = parse_avps_int(bytes)
  end
end
