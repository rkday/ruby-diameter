require 'diameter/diameter_logger'

module Diameter
  # A Diameter peer entry in the peer table.
  #
  # @!attribute [rw] identity
  #   [String] The DiameterIdentity of this peer
  # @!attribute [rw] realm
  #   [String] The Diameter realm of this peer
  # @!attribute [rw] static
  #   [true, false] Whether this peer was dynamically discovered (and so
  #   might expire) or statically configured.
  # @!attribute [rw] expiry_time
  #   [Time] For a dynamically discovered peer, the time when it stops
  #   being valid and dynamic discovery must happen again.
  # @!attribute [rw] last_message_seen
  #   [Time] The last time traffic was received from this peer. Used for
  #   determining when to send watchdog messages, or for triggering failover.
  # @!attribute [rw] cxn
  #   [Socket] The underlying network connection to this peer.
  # @!attribute [rw] state
  #   [Keyword] The current state of this peer - :UP, :WATING or :CLOSED.

  class Peer
    attr_accessor :identity, :static, :cxn, :realm, :expiry_time, :last_message_seen
    attr_reader :state

    def initialize(identity, realm)
      @identity = identity
      @realm = realm
      @state = :CLOSED
      @state_change_q = Queue.new
    end

    # Blocks until the state of this peer changes to the desired value.
    #
    # @param state [Keyword] The state to change to.
    def wait_for_state_change(state)
      cur_state = @state
      while (cur_state != state)
        cur_state = @state_change_q.pop
      end
    end

    # @todo Add further checking, making sure that the transition to
    # new_state is valid according to the RFC 6733 state machine. Maybe
    # use the micromachine gem?
    def state=(new_state)
      Diameter.logger.log(Logger::DEBUG, "State of peer #{identity} changed from #{@state} to #{new_state}")
      @state = new_state
      @state_change_q.push new_state
    end

    # Resets the last message seen time. Should be called when a message
    # is received from this peer.
    def reset_timer
      self.last_message_seen = Time.now
    end
  end
end
