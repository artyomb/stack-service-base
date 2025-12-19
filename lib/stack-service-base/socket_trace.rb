module StackServiceBase
  module SocketTrace
    def bind(local_sockaddr)
      LOGGER.info "Socket Bind: http://#{local_address.ip_address}:#{local_address.ip_port}"
      super
    end
    def setsockopt(level, optname, optval)
      LOGGER.info "Socket setsockopt: #{level}, #{optname}, #{optval}"
      super
    end
  end

  Socket.prepend SocketTrace
end