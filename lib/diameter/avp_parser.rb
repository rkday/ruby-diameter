require 'diameter/u24'

module Diameter
  module Internals
    # @private
    # Parser mixin, sharing functionality common to:
    #  * parsing all the AVPs in a message
    #  * parsing the AVPs inside a Grouped AVP
    module AVPParser
      # Is the vendor-specific bit (the top bit) set?
      #
      # @param flags [String] A string of eight bits, e.g. "00000000"
      # @return [true, false]
      def self.vendor_id_bit(flags)
        flags[0] == '1'
      end

      # Is the mandatory bit (the second bit) set?
      #
      # @param flags [String] A string of eight bits, e.g. "00000000"
      # @return [true, false]
      def self.mandatory_bit(flags)
        flags[1] == '1'
      end

      # @return [Array(Fixnum, Fixnum, Bool, Fixnum, Fixnum)] The bytes consumed
      # (8 or 12), AVP code,
      # mandatory bit, length and vendor-ID (or 0 in the case of a
      # non-vendor-specific AVP).
      def self.parse_avp_header(bytes)
        first_avp_header = bytes[0..8]
        # Parse them
        code, avp_flags, alength_8, alength_16 =
          first_avp_header.unpack('NB8Cn')
        
        mandatory = mandatory_bit(avp_flags)
        length = UInt24.from_u8_and_u16(alength_8, alength_16)

        if vendor_id_bit(avp_flags)
          avp_vendor_header = bytes[8..12]
          avp_vendor, = avp_vendor_header.unpack('N')
          [12, code, mandatory, length, avp_vendor]
        else
          [8, code, mandatory, length, 0]
        end
      end
      
      # @api private
      #
      # @param bytes [String] A sequence of bytes representing a set of AVPs.
      # @return [Array<AVP>] The AVPs parsed out of the bytes.
      def self.parse_avps_int(bytes)
        avps = []
        position = 0
        while position < bytes.length
          # Consume the first 8 octets
          avp_consumed, code, mandatory, length, avp_vendor = parse_avp_header(bytes[position..-1])
          position += avp_consumed

          # Read the content, ensuring it aligns to a 32-byte boundary
          avp_content_length = length - avp_consumed
          avp_content = bytes[position..(position + avp_content_length) - 1]

          padding = 0
          padding += 1 until ((avp_content_length + padding) % 4) == 0

          position += avp_content_length + padding

          # Construct an AVP object from the parsed data
          parsed_avp =
            if avp_vendor != 0
              VendorSpecificAVP.new(code,
                                    avp_vendor,
                                    mandatory: mandatory,
                                    content: avp_content)
            else
              AVP.new(code,
                      mandatory: mandatory,
                      content: avp_content)
            end

          avps.push parsed_avp
        end
        avps
      end
    end
  end
end
