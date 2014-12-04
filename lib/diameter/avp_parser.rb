require "diameter/u24"

module AVPParser
  def vendor_id_bit(flags)
    flags[0] == '1'
  end

  def mandatory_bit(flags)
    flags[1] == '1'
  end

  def parse_avps_int(bytes)
    avps = []
    position = 0
    while position < bytes.length
      # Consume the first 8 octets
      first_avp_header = bytes[position..position + 8]
      position += 8

      # Parse them
      code, avp_flags, alength_8, alength_16 = first_avp_header.unpack('NB8Cn')

      length = u8_and_u16_to_u24(alength_8, alength_16)

      # Default values in the case where this isn't vendor-specific
      avp_consumed = 8
      avp_vendor = 0

      # If this is vendor-specific, read the vendor ID
      if vendor_id_bit(avp_flags)
        avp_vendor_header = bytes[position..position + 4]
        position += 4
        avp_vendor, = avp_vendor_header.unpack('N')
        avp_consumed = 12
      end

      # Read the content, ensuring it aligns to a 32-byte boundary
      avp_content_length = length - avp_consumed
      avp_content = bytes[position..(position + avp_content_length) - 1]

      padding = 0
      padding += 1 until ((avp_content_length + padding) % 4) == 0

      position += avp_content_length + padding

      # Construct an AVP object from the parsed data
      parsed_avp =
        if vendor_id_bit(avp_flags)
          VendorSpecificAVP.new(code: code,
                                mandatory: mandatory_bit(avp_flags),
                                vendor_id: avp_vendor,
                                content: avp_content)
        else
          AVP.new(code: code,
                  mandatory: mandatory_bit(avp_flags),
                  content: avp_content)
        end
      avps.push parsed_avp
    end
    avps
  end
end
