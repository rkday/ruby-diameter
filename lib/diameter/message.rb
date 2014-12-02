require_relative './avp_parser.rb'

def b8_and_16_to_24(eightb, sixteenb)
  (eightb << 16) + sixteenb
end

def b24_to_8_and_16(twentyfourb)
  top_eight = twentyfourb >> 16
  bottom_sixteen = twentyfourb - (top_eight << 16)
  [top_eight, bottom_sixteen]
end

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
    @proxyable = false
    @retransmitted = false
    @error = false
  end

  def to_s
    "#{@command_code}: #{@avps.collect{|a| a.to_s }}"
  end

  def to_wire
    content = ""
    @avps.each {|a| content += a.to_wire}
    length_8, length_16 = b24_to_8_and_16(content.length + 20)
    code_8, code_16 = b24_to_8_and_16(@command_code)
    if @request
      flags_str = "10000000"
    else
      flags_str = "00000000"
    end
    
    header = [@version, length_8, length_16, flags_str, code_8, code_16, @app_id, @hbh, @ete].pack('CCnB8CnNNN')
    header + content
  end
  
  def length
    @length
  end

  def avp_by_name(name)
    code, type, vendor = AVPNames.get(name)
    avps.each {|a| return a if a.code == code}
  end

  def all_avps_by_name(name)
    code, type, vendor = AVPNames.get(name)
    avps.select {|a| a.code == code}
  end

  def avp_by_code(code)
    avps.each {|a| return a if a.code == code}
  end

  def all_avps_by_code(code)
    avps.select {|a| a.code == code}
  end

  def self.from_header(header)
    version, length_8, length_16, flags_str, code_8, code_16, app_id, hbh, ete = header.unpack('CCnB8CnNNN')
    length = b8_and_16_to_24(length_8, length_16)
    command_code = b8_and_16_to_24(code_8, code_16)

    request = (flags_str[0] == "1")
    DiameterMessage.new(version: version, length: length, command_code: command_code, app_id: app_id, hbh: hbh, ete: ete, request: request, proxyable: false, retransmitted: false, error: false)
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
