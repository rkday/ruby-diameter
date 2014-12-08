require 'uri'
require 'socket'
require 'diameter/message'
require 'diameter/avp'

# @private
class StackHelper
  def initialize(stack)
    @all_connections = []
    @data = {}
    @stack = stack
    @loop_thread = nil
  end

  def start_main_loop
    @loop_thread = Thread.new do
      loop do
        main_loop
      end
    end
  end

  def wakeup
    @loop_thread.raise
  end

  def main_loop
    begin
      rs, _ws, es = IO.select(@all_connections, [], @all_connections)
    rescue RuntimeError
      return
    end

    es.each do |e|
      Diameter.logger.log(Logger::WARN, "Exception on connection #{e}")
    end

    rs.each do |r|

      existing_data = @data[r]
      if existing_data.length < 4
        msg, _src = r.recvfrom_nonblock(4 - existing_data.length)
        if msg == ''
          Diameter.logger.warn('Received 0 bytes on read, closing connection')
          r.close
          @all_connections.delete r
          @data.delete r
        else
          existing_data += msg
        end
      end

      expected_len = -1
      if existing_data.length >= 4
        expected_len = DiameterMessage.length_from_header(existing_data[0..4])
        Diameter.logger.debug("Read 4 bytes #{existing_data[0..4].inspect}, " \
                              "reading full message of length #{expected_len}")
        msg, _src = r.recvfrom_nonblock(expected_len - existing_data.length)
        existing_data += msg
        if msg == ''
          # Connection closed
          Diameter.logger.warn('Received 0 bytes on read, closing connection')
          close(r)
        end
      end

      if existing_data.length == expected_len
        @stack.handle_message(existing_data, r)
        @data[r] = ''
      else
        @data[r] = existing_data
      end
    end
  end

  def send(bytes, connection)
    connection.sendmsg(bytes)
  end
end

# @private
class TCPStackHelper < StackHelper
  def setup_new_connection(host, port)
    sd = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    sd.connect(Socket.pack_sockaddr_in(port, host))
    @all_connections.push sd
    @data[sd] = ''
    wakeup
    sd
  end

  def close(connection)
    r.close
    @all_connections.delete r
    @data.delete r
  end
  
  def setup_new_listen_connection(_host, _port)
  end

  def accept_loop
    rs, _ws, es = IO.select(@listen_connections, [], @listen_connections)
    es.each do |e|
      Diameter.logger.log(Logger::WARN, "Exception on connection #{e}")
    end

    rs.each do |r|
      @all_connections.push r.accept_nonblock
    end
  end
end

# @private
class SCTPStackHelper
  def setup_new_connection(host, port)
    sd = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    sd.connect(Socket.pack_sockaddr_in(port, host))
  end

  def setup_new_listen_connection(_host, _port)
  end

  def send(_bytes, _connection)
  end
end
