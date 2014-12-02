require_relative './avp_parser.rb'

def b24_to_8_and_16(twentyfourb)
  top_eight = twentyfourb >> 16
  bottom_sixteen = twentyfourb - (top_eight << 16)
  [top_eight, bottom_sixteen]
end

GROUPED = 0
I32 = 1
OCTETSTRING = 2

class AVPNames
  def self.get(name)
    names = {"Vendor-Specific-Application-Id" => [260, GROUPED],
      "Vendor-Id" => [266, I32],
      "Auth-Application-Id" => [258, I32],
      "Session-Id" => [263, OCTETSTRING],
      "Auth-Session-State" => [277, I32],
      "Inband-Security-Id" => [299, I32],
      "Origin-Host" => [264, OCTETSTRING],
      "Result-Code" => [268, I32],
      "Origin-Realm" => [296, OCTETSTRING],
      "Destination-Host" => [293, OCTETSTRING],
      "Destination-Realm" => [283, OCTETSTRING],
      "User-Name" => [1, OCTETSTRING],
      "Public-Identity" => [601, OCTETSTRING, 10415],
      "Server-Name" => [602, OCTETSTRING, 10415],
      "SIP-Number-Auth-Items" => [607, I32, 10415],
      "SIP-Auth-Data-Item" => [612, GROUPED, 10415],
      "SIP-Item-Number" => [613, I32, 10415],
      "SIP-Authentication-Scheme" => [608, OCTETSTRING, 10415],
    }
    names[name]
  end
end
  
  

class AVP
  attr_reader :code, :mandatory

  include AVPParser
  
  def initialize(options = {})
    @code = options[:code] || 0
    @content = options[:content] || ""
    @mandatory = options[:mandatory] || true
  end

  def self.create(name, val)
    code, type, vendor = AVPNames.get(name)
    avp = if vendor
            VendorSpecificAVP.new(code: code, vendor_id: vendor)
          else
            AVP.new(code: code)
          end
    if type == GROUPED
      avp.setGroupedAVP(val)
    elsif type == I32
      avp.setInteger32(val)
    elsif type == OCTETSTRING
      avp.setOctetString(val)
    end
    avp
  end

  def to_wire
    length = @content.length + 8
    alength_8, alength_16 = b24_to_8_and_16(length)
    avp_flags = "01000000"
    header = [@code, avp_flags, alength_8, alength_16].pack('NB8Cn')
    wire_content = @content
    while ((wire_content.length % 4) != 0)
      puts "padding"
      wire_content += "\x00"
    end
    header + wire_content
  end  

  def to_s
    has_all_ascii_values = @content.bytes.reject{ |c| (32 < c and c < 126)}.empty?
    
    could_be_32bit_num = (@content.length == 4)
    could_be_64bit_num = (@content.length == 8)

    maybe_grouped = !(has_all_ascii_values or could_be_64bit_num or could_be_32bit_num)
    
    s = "AVP #{@code}, mandatory: #{@mandatory}"
    s += ", content as string: #{@content}" if has_all_ascii_values
    s += ", content as int32: #{getInteger32}" if could_be_32bit_num
    s += ", content as int64: #{getInteger64}" if could_be_64bit_num

    s += ", grouped AVP" if maybe_grouped
    s
  end

  def vendor_specific
    false
  end

  def getGroupedAVP
    return parse_avps_int(@content)
  end

  def setGroupedAVP(avps)
    newContent = ""
    avps.each {|a| newContent += a.to_wire}
    @content = newContent
  end

  def getOctetString
    return @content
  end

  def setOctetString(val)
    @content = val
  end

  def getInteger32
    return @content.unpack('N')[0]
  end

  def setInteger32(val)
    @content = [val].pack('N')
  end

  def getInteger64
    return @content.unpack('Q>')[0]
  end

  def getUnsigned32
    return @content.unpack('N')
  end

  def setUnsigned32
    return @content.unpack('N')
  end

  def getUnsigned64
    return @content.unpack('N')
  end

  def setUnsigned64(val)
    @content = [val].pack('N')
  end

  def getFloat32
    return @content.unpack('N')
  end

  def getFloat64
    return @content.unpack('N')
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
    length = content.length + 12
    avp_flags = "11000000"
    header = [code, avp_flags, alength_8, alength_16, @vendor_id].pack('NB8CnN')
    header + content
  end  

  def to_s
      "AVP #{@code}, Vendor-ID #{@vendor_id}, mandatory: #{@mandatory}"
  end
end
