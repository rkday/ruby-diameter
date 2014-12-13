module Diameter
  module Internals

    # @private
    # Methods for handling 24-bit unsigned integers, used for length and
    # Command-Codes but not representable by String#unpack or Array#pack.
    module UInt24
      # @api private
      #
      # Generates an unsigned integer from two other unsigned integers
      # (one representing the top 8 bits, one representing the bottom 16
      # bits).
      #
      # @param eightb [Fixnum] The top 8 bits (max 255)
      # @param sixteenb [Fixnum] The low 16 bits (max 2^16-1)
      # @return [Fixnum]  (max 2^24-1)
      def self.from_u8_and_u16(eightb, sixteenb)
        (eightb << 16) + sixteenb
      end

      # @api private
      #
      # Converts an unsigned integer to two other unsigned integers (one
      # representing the top 8 bits, one representing the bottom 16 bits).
      #
      # @param twentyfourb [Fixnum] The original number (max 2^24-1)
      # @return [[Fixnum, Fixnum]]  Separate integers representing the
      #   top 8 and low 16 bits.
      def self.to_u8_and_u16(twentyfourb)
        top_eight = twentyfourb >> 16
        bottom_sixteen = twentyfourb - (top_eight << 16)
        [top_eight, bottom_sixteen]
      end
    end
  end
end
