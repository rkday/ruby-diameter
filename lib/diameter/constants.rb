module Diameter
  module Constants
    # Contains Vendor-ID constants
    module Vendors
      # The 3GPP/IMS Vendor-ID
      TGPP = 10_415
    end

    # Represents the type of data a particular AVP should be interpreted
    # as.
    module AVPType
      # Represents an AVP of Grouped type
      GROUPED = :Grouped
      
      # Represents an AVP of Unsigned32 type
      U32 = :Unsigned32

      # Represents an AVP of OctetString type
      OCTETSTRING = :OctetString

      # Represents an AVP of IPAddress type
      IPADDR = :Address
    end

    include AVPType
    include Vendors

    # The AVPs that can be looked up by name.
    AVAILABLE_AVPS = {
      'Vendor-Specific-Application-Id' => [260, GROUPED],
      'Vendor-Id' => [266, U32],
      'Auth-Application-Id' => [258, U32],
      'Acct-Application-Id' => [259, U32],
      'Session-Id' => [263, OCTETSTRING],
      'Product-Name' => [269, OCTETSTRING],
      'Auth-Session-State' => [277, U32],
      'Inband-Security-Id' => [299, U32],
      'Origin-Host' => [264, OCTETSTRING],
      'Firmware-Revision' => [267, U32],
      'Result-Code' => [268, U32],
      'Origin-Realm' => [296, OCTETSTRING],
      'Destination-Host' => [293, OCTETSTRING],
      'Destination-Realm' => [283, OCTETSTRING],
      'User-Name' => [1, OCTETSTRING],
      'Host-IP-Address' => [257, IPADDR],
      'Public-Identity' => [601, OCTETSTRING, TGPP],
      'Server-Name' => [602, OCTETSTRING, TGPP],
      'SIP-Number-Auth-Items' => [607, U32, TGPP],
      'SIP-Auth-Data-Item' => [612, GROUPED, TGPP],
      'SIP-Item-Number' => [613, U32, TGPP],
      'SIP-Authentication-Scheme' => [608, OCTETSTRING, TGPP] }

  end
end
