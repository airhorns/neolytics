module Neo4Apis
  class Neolytics < Base
    module TracePointHelpers

      class << self

        FILE_LINES = {}

        def each_received_arguments(tp)
          # Can't just use #method method because some objects implement a #method method
          method = if tp.self.class.instance_method(:method).source_location.nil?
            tp.self.method(tp.method_id)
          else
            tp.self.class.instance_method(tp.method_id)
          end
          parameter_names = method.parameters.map {|_, name| name }
          arguments = parameter_names.compact.each_with_object({}) do |name, arguments|
            catch :not_found do
              arguments[name] = get_trace_point_var(tp, name)
            end
          end
          arguments.each do |name, object|
            yield name, object
          end
        end

        private

        def get_file_line(path, lineno)
          return '' if ['(eval)', '(irb)'].include?(path)
          FILE_LINES[path] ||= File.read(path).lines

          FILE_LINES[path][lineno - 1]
        end

        def get_trace_point_var(tp, var_name)
          begin
            tp.binding.local_variable_get(var_name)
          rescue NameError
            throw :not_found
          end
        end
      end
    end
  end
end
