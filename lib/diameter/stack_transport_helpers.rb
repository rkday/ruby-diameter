require 'uri'
require 'socket'
require 'diameter/message'
require 'diameter/avp'

if RUBY_ENGINE != 'jruby'
  ServerSocket = Socket
end

module Diameter
  module Internals
    # @private
    class StackHelper
      def initialize(stack)
        @all_connections = []
        @listen_connections = []
        @data = {}
        @stack = stack
        @loop_thread = nil
        @accept_loop_thread = nil
        @connection_lock = Mutex.new
        @wakeup_pipe_rd, @wakeup_pipe_wr = IO.pipe
      end

      def start_main_loop
        @loop_thread = Thread.new do
          loop do
            main_loop
          end
        end
        @loop_thread.abort_on_exception = true
      end

      def wakeup
        @wakeup_pipe_wr.puts "wakeup"
      end

      def main_loop
          rs, _ws, es = IO.select(@all_connections + [@wakeup_pipe_rd], [], @all_connections)

        es.each do |e|
          Diameter.logger.log(Logger::WARN, "Exception on connection #{e}")
        end

        rs.each do |r|
          if r == @wakeup_pipe_rd
            r.gets
            next
          end

          existing_data = @data[r]
          if existing_data.length < 4
            msg, _src = r.recv_nonblock(4 - existing_data.length)
            if msg == ''
              Diameter.logger.warn('Received 0 bytes on read, closing connection')
              close(r)
            else
              existing_data += msg
            end
          end

          expected_len = -1
          if existing_data.length >= 4
            expected_len = Message.length_from_header(existing_data[0..4])
            Diameter.logger.debug("Read 4 bytes #{existing_data[0..4].inspect}, " \
                                  "reading full message of length #{expected_len}")
            msg, _src = r.recv_nonblock(expected_len - existing_data.length)
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
        connection.send(bytes, 0)
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

      def shutdown
        @accept_loop_thread.kill if @accept_loop_thread
        @loop_thread.kill if @loop_thread

        @all_connections.each { |c| close(c) }
        @listen_connections.each { |c| close(c) }
        @all_connections = []
        @listen_connections = []
      end

      def close(connection)
        connection.close
        @all_connections.delete connection
        @listen_connections.delete connection
        @data.delete connection
      rescue IOError
        # It's OK if this is already closed
      end
      
      def setup_new_listen_connection(host, port)
        sd = ServerSocket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
        # reuse = [1,0].pack('ii')
        sd.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
        sd.bind(Socket.pack_sockaddr_in(port, host))
        sd.listen(100)
        @listen_connections.push sd
        @accept_loop_thread = Thread.new do
          loop do
            accept_loop
          end
        end
        @accept_loop_thread.abort_on_exception = true
      end

      def accept_loop
        rs, _ws, es = IO.select(@listen_connections, [], @listen_connections)
        es.each do |e|
          Diameter.logger.log(Logger::WARN, "Exception on connection #{e}")
        end

        rs.each do |r|
          sock, addr = r.accept
          Diameter.logger.debug("Accepting connection from #{addr}")
          @data[sock] = ''
          @all_connections.push sock 
          wakeup
        end
      end
    end

=begin
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
=end
  end
end
