module Diameter
  module Constants
    # Contains Vendor-ID constants
    module Vendors
      # The 3GPP/IMS Vendor-ID
      TGPP = 10_415
      ETSI = 13_019
    end

    # Represents the type of data a particular AVP should be interpreted
    # as.
    module AVPType
      # Represents an AVP of Grouped type
      Grouped = :Grouped
      
      # Represents an AVP of Unsigned32 type
      Unsigned32 = :Unsigned32
      Enumerated = Unsigned32

      Unsigned64 = :Unsigned64
      Integer32 = :Integer32
      Integer64 = :Integer64
      Float32 = :Float32
      Float64 = :Float64
      
      # Represents an AVP of OctetString type
      OctetString = :OctetString
      DiameterIdentity = OctetString
      DiameterURI = OctetString
      UTF8String = OctetString
      

      # Represents an AVP of IPAddress type
      IPAddress = :Address
    end
  end
end
