require 'nats'
require 'nats/io/websocket'

# TODO PATCH https://github.com/nats-io/nats-pure.rb/issues/171
module NATS
  module IO
    class WebSocket
      def initialize(options = {})
        super
        @options = options
      end

      def connect
        super

        setup_tls! if @uri.scheme == "wss" # WebSocket connection must be made over TLS from the beginning

        @handshake = ::WebSocket::Handshake::Client.new url: @uri.to_s, **@options
        @frame = ::WebSocket::Frame::Incoming::Client.new
        @handshaked = false

        @socket.write @handshake.to_s

        until @handshaked
          @handshake << method(:read).super_method.call(MAX_SOCKET_READ_BYTES)
          if @handshake.finished?
            @handshaked = true
          end
        end
      end
    end
  end

  class Client
    def create_socket
      socket_class = case @uri.scheme
                     when "nats", "tls"
                       NATS::IO::Socket
                     when "ws", "wss"
                       # require_relative "websocket"
                       # TODO Local patch
                       require 'nats/io/websocket'
                       NATS::IO::WebSocket
                     else
                       raise NotImplementedError, "#{@uri.scheme} protocol is not supported, check NATS cluster URL spelling"
                     end

      socket_class.new(
        uri: @uri,
        tls: {context: tls_context, hostname: @hostname},
        connect_timeout: NATS::IO::DEFAULT_CONNECT_TIMEOUT,
        **@initial_options # TODO PATCH https://github.com/nats-io/nats-pure.rb/issues/171
      )
    end
  end
end