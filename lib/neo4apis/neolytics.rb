require 'neo4apis/neolytics/trace_point_helpers'

module Neo4Apis
  class Neolytics < Base
    common_label :Neolytics

    uuid :Object, :ruby_object_id
    uuid :TracePoint, :uuid
    uuid :File, :path

    batch_size 6000

    IMPORTED_OBJECT_NODES = {}

    importer :Object do |object|
      next IMPORTED_OBJECT_NODES[object.object_id] if IMPORTED_OBJECT_NODES.key?(object.object_id)

      object_node = add_node(:Object) do |node|
        node.ruby_object_id = object.object_id
        node.ruby_inspect = object.inspect[0,500]
        node._extra_labels = []
        node._extra_labels << 'Class' if object.class == Class
        node._extra_labels << 'Module' if object.class == Module
      end

      IMPORTED_OBJECT_NODES[object.object_id] = object_node

      class_node = import :Object, object.class
      add_relationship :IS_A, object_node, class_node if class_node

      if object.respond_to?(:superclass) && object.superclass
        superclass_node = import :Object, object.superclass
        add_relationship :HAS_SUPERCLASS, object_node, superclass_node if superclass_node
      end

      if object.respond_to?(:included_modules)
        object.included_modules.each do |mod|
          module_node = import :Object, mod
          add_relationship :INCLUDES_MODULE, object_node, module_node if module_node
        end
      end

      object.instance_variables.each do |variable|
        value = object.instance_variable_get(variable)
        other_object_node = import :Object, value
        add_relationship :INSTANCE_VARIABLE, object_node, other_object_node, variable: variable
      end

      object_node
    end

    importer :TracePoint do |tp, execution_time, total_execution_time, execution_index, last_tracepoint_node, parent, associated_call|
      next nil if tp.method_id.to_s.strip.empty? && tp.defined_class.to_s.strip.empty?

      # if tp.lineno == 19 && tp.event == :line
      #   require 'pry'
      #   binding.pry
      # end
      trace_point_node = add_node :TracePoint, tp, %i(event lineno method_id) do |node|
        node.uuid = SecureRandom.uuid
        node.defined_class = tp.defined_class.to_s
        node.execution_time = execution_time if execution_time
        node.total_execution_time = total_execution_time if total_execution_time
        node.execution_index = execution_index

        node.path = if ['(eval)', '(irb)'].include?(tp.path)
          tp.path
        else
          Pathname.new(tp.path).realpath.to_s
        end
      end


      if [:return, :c_return].include?(tp.event)
        returned_object_node = import :Object, tp.return_value
        add_relationship :RETURNED, trace_point_node, returned_object_node
      end

      unless tp == tp.self
        begin
          ruby_object_node = import :Object, tp.self
          add_relationship :FROM_OBJECT, trace_point_node, ruby_object_node
        rescue Exception
          nil
        end
      end

      if tp.event == :call
        TracePointHelpers.each_received_arguments(tp) do |argument, object|
          object_node = import :Object, object
          add_relationship :RECEIVED_ARGUMENT, trace_point_node, object_node, argument_name: argument
        end
      end

      add_relationship :NEXT, last_tracepoint_node, trace_point_node if last_tracepoint_node
      add_relationship :HAS_PARENT, trace_point_node, parent if parent
      add_relationship :STARTED_AT, trace_point_node, associated_call if associated_call

      trace_point_node
    end

    importer :File do |full_path, content|
      add_node :File do |node|
        node.path = full_path
        node.content = content
      end
    end
  end
end
