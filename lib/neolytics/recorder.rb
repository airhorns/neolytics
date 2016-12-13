require 'pathname'
require 'neo4apis'
require 'neo4apis/neolytics'

module Neolytics
  class Recorder
    def initialize(neo4j_session)
      @neo4j_session = neo4j_session
      @neo4apis_session = Neo4Apis::Neolytics.new(neo4j_session)
      create_indexes
    end

    def create_indexes
      @neo4j_session.query('CREATE INDEX ON :TracePoint(path)')
      @neo4j_session.query('CREATE INDEX ON :TracePoint(event)')
      @neo4j_session.query('CREATE INDEX ON :TracePoint(lineno)')
      @neo4j_session.query('CREATE INDEX ON :TracePoint(defined_class)')
      @neo4j_session.query('CREATE INDEX ON :TracePoint(method_id)')
      @neo4j_session.query('CREATE INDEX ON :TracePoint(execution_index)')
    end

    def record(&block)
      @neo4apis_session.batch do
        record_execution_trace do
          block.call
        end
      end
    end

    def record_execution_trace
      execution_index = 0
      indent = 0
      last_tracepoint_node = nil
      last_start_time = nil
      ancestor_stack = []
      run_time_stack = []
      total_run_time_stack = []

      last_tracepoint_end_time = nil
      last_run_time = nil

      trace = TracePoint.new(:call, :c_call, :return, :c_return) do |tp|
        last_run_time = 1_000_000.0 * (Time.now - last_tracepoint_end_time) if last_tracepoint_end_time

        next if tp.path.match(%r{/neolytics/})

        start = Time.now

        last_method_time = nil
        if [:call, :c_call].include?(tp.event)
          run_time_stack.push(0)
          total_run_time_stack.push(0)
        elsif [:return, :c_return].include?(tp.event)
          last_method_time = run_time_stack.pop
          last_method_total_time = total_run_time_stack.pop
        else
          #puts "total_run_time_stack: #{total_run_time_stack.inspect}"
          #puts "increment by #{last_run_time}"
          if run_time_stack[-1] && last_run_time
            run_time_stack[-1] += last_run_time
            total_run_time_stack.map! { |i| i + last_run_time }
          end
        end

        associated_call = nil
        if [:return, :c_return].include?(tp.event) && indent.nonzero?
          indent -= 1
          associated_call = ancestor_stack.pop
        elsif [:call, :c_call].include?(tp.event)
          indent += 1
        end

        last_tracepoint_node = @neo4apis_session.import :TracePoint, tp,
                            last_method_time,
                            last_method_total_time,
                            (execution_index += 1),
                            last_tracepoint_node,
                            ancestor_stack.last,
                            associated_call

        if [:call, :c_call].include?(tp.event)
          ancestor_stack.push(last_tracepoint_node)
        end

        stop = Time.now
        diff = stop - start
        if diff > 0.5
          puts "time: #{diff}"
          puts "tp: #{tp.inspect}"
        end
        last_tracepoint_end_time = Time.now
      end

      trace.enable
      yield
    ensure
      trace.disable
    end

    private

    CYAN = "\e[36m"
    CLEAR = "\e[0m"
    GREEN = "\e[32m"

    def tracepoint_string(tp, indent)
      parts = []
      parts << "#{'|  ' * indent}"
      parts << "#{CYAN if tp.event == :call}%-8s#{CLEAR}"
      parts << "%s:%-4d %-18s\n"
      parts.join(' ') % [tp.event, tp.path, tp.lineno, tp.defined_class.to_s + '#' + GREEN + tp.method_id.to_s + CLEAR]
    end
  end
end
