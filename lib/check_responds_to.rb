require "check_responds_to/version"
require "set"
require "parser/current"
require "socket"

module CheckRespondsTo
  class Checker
    def initialize(config)
      @config = config
      @processor = ASTProcessor.new(config)
    end

    def check_interfaces(code)
      ast = Parser::CurrentRuby.parse(code)
      @processor.process(ast)
      @processor.result
    end
  end

  class Result
    attr_reader :errors

    def initialize(errors)
      @errors = errors
    end
  end

  class ASTProcessor
    include AST::Processor::Mixin

    def initialize(config)
      @config = config
      @errors = []
    end

    def result
      Result.new(@errors)
    end

    def handler_missing(node)
      process_all(node.children.select { |maybe_node| maybe_node.is_a? AST::Node })
    end

    def on_send(node)
      receiver, method_name, *args = node.children
      if recognize_variable?(receiver)
        if !method_exists?(receiver, method_name)
          @errors << [:no_method, node, receiver, method_name]
        elsif arity_mismatch?(receiver, method_name, args)
          @errors << [:arity_mismatch, node, receiver, method_name, args]
        end
      end
    end

    def recognize_variable?(receiver_node)
      return false unless receiver_node.is_a?(AST::Node)
      var_name = variable_name_from_receiver_node(receiver_node)
      var_name && @config.can_map_variable?(var_name)
    end

    def method_exists?(receiver_node, method_name)
      return false unless receiver_node.is_a?(AST::Node)
      var_name = variable_name_from_receiver_node(receiver_node)
      @config.variable_responds_to?(var_name, method_name)
    end

    def arity_mismatch?(receiver_node, method_name, args_nodes)
      return false unless receiver_node.is_a?(AST::Node)
      var_name = variable_name_from_receiver_node(receiver_node)
      !@config.variable_method_supports_arity?(var_name, method_name, args_nodes.size)
    end

    def variable_name_from_receiver_node(receiver_node)
      case receiver_node.type
      when :ivar
        receiver_node.children[0].to_s[1..-1]
      when :lvar
        receiver_node.children[0].to_s
      when :str, :send, :const
        # TODO: @jbodah 2019-02-21: string literal
        nil
      else
        raise "Unexpected receiver type: #{receiver_node.inspect}"
      end
    end
  end

  class Config
    def initialize(hash)
      @variable_to_class = hash.fetch(:variable_to_class)
      @method_map = hash.fetch(:method_map)
    end

    def can_map_variable?(var_name)
      @variable_to_class.key?(var_name)
    end

    def variable_responds_to?(var_name, method_name)
      klass = @variable_to_class[var_name]
      return false if klass.nil?
      klass_spec = @method_map[klass]
      return false if klass_spec.nil?
      klass_spec.include?(method_name.to_s)
    end

    def variable_method_supports_arity?(var_name, method_name, num_received)
      klass = @variable_to_class[var_name]
      return false if klass.nil?
      klass_spec = @method_map[klass]
      return false if klass_spec.nil?
      method_spec = klass_spec[method_name.to_s]
      return false if method_spec.nil?

      actual_arity = method_spec[:arity]
      Arity.supports?(arity: actual_arity, received: num_received)
    end
  end

  module Arity
    def self.supports?(arity: , received: )
      return true if arity == -1
      if arity < -1
        received >= -1 * (arity + 1)
      else
        received == arity
      end
    end
  end

  class ServerBackedConfig
    def initialize(host, port)
      @host = host
      @port = port
    end

    def can_map_variable?(var_name)
      resp = ask(__method__, var_name)
      resp == ["YES"]
    end

    def variable_responds_to?(var_name, method_name)
      resp = ask(__method__, var_name, method_name)
      resp == ["YES"]
    end

    def variable_method_supports_arity?(var_name, method_name, num_received)
      resp = ask(__method__, var_name, method_name, num_received)
      resp == ["YES"]
    end

    private

    def ask(*args)
      connect do |socket|
        req = args.join("\t")
        puts "> " + req.inspect
        socket.sendmsg(args.join("\t"))
        puts "waiting for resp"
        resp = socket.recvmsg[0].split("\t")
        puts "< " + resp.inspect
        resp
      end
    end

    def connect
      socket = TCPSocket.new(@host, @port)
      yield socket
    ensure
      socket.close
    end
  end

  class Server
    CUSTOM_MAP = {
      "user" => "SemUser"
    }

    def initialize(port)
      @server = TCPServer.new(port)
    end

    def start
      puts "starting server"
      loop do
        puts "waiting for client"
        client = @server.accept
        puts "waiting for req"
        req = client.recvmsg[0].split("\t")
        puts "> " + req.inspect
        resp = handle_req(req)
        puts "< " + resp.inspect
        client.sendmsg(resp.join("\t"))
        client.close
      end
    end

    private

    def can_map_variable?(var_name)
      klass = klass_for(var_name)
      ["YES"]
    rescue NameError
      ["NO"]
    end

    def variable_responds_to?(var_name, method_name)
      klass = klass_for(var_name)
      klass.method_defined?(method_name) ? ["YES"] : ["NO"]
    rescue NameError
      ["NO"]
    end

    def variable_method_supports_arity?(var_name, method_name, num_received)
      klass = klass_for(var_name)
      arity = klass.instance_method(method_name).arity
      Arity.supports?(arity: arity, received: num_received.to_i) ? ["YES"] : ["NO"]
    rescue NameError
      ["NO"]
    end

    # NOTE: @jbodah 2019-02-21: we are assuming a Rails server here
    def klass_for(var_name)
      # 0. use hardcoded entry if it exists
      return CUSTOM_MAP[var_name].constantize if CUSTOM_MAP.key?(var_name)

      # 1. try to constantize
      begin
        return var_name.camelcase.constantize
      rescue NameError
      end

      models = Dir['app/models/*.rb'].map(&File.method(:basename)).map { |name| name.sub(/\.rb$/, '') }

      # 2. try to perform substring match
      candidates = models.select { |model| model.include? var_name }
      return candidates[0].constantize if candidates.size == 1

      # 3. try to use acronym
      models_by_acronym = models.group_by { |model| model.split('_').map(&:first).join }
      if models_by_acronym[var_name] && models_by_acronym[var_name].size == 1
        return models_by_acronym[var_name].constantize
      end

      raise NameError
    end

    def handle_req(req)
      name, *args = req
      send(name, *args)
    end
  end
end
