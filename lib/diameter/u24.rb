def u8_and_u16_to_u24(eightb, sixteenb)
  (eightb << 16) + sixteenb
end

def u24_to_u8_and_u16(twentyfourb)
  top_eight = twentyfourb >> 16
  bottom_sixteen = twentyfourb - (top_eight << 16)
  [top_eight, bottom_sixteen]
end

