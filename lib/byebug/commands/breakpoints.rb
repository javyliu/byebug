module Byebug

  # Implements byebug "break" command.
  class AddBreakpoint < Command
    self.allow_in_control = true

    def regexp
      / ^\s*
        b(?:reak)?
        (?: \s+ #{Position_regexp})? \s*
        (?: \s+ (.*))? \s*
        $
      /x
    end

    def execute
      return print AddBreakpoint.help(nil) if
        AddBreakpoint.names.include?(@match[0])

      if @match[1]
        line, _, _, expr = @match.captures
      else
        _, file, line, expr = @match.captures
      end
      if expr
        if expr !~ /^\s*if\s+(.+)/
          if file or line
            errmsg "Expecting \"if\" in breakpoint condition; got: #{expr}.\n"
          else
            errmsg "Invalid breakpoint location: #{expr}.\n"
          end
          return
        else
          expr = $1
        end
      end

      brkpt_filename = file
      if file.nil?
        unless @state.context
          errmsg "We are not in a state that has an associated file.\n"
          return
        end
        brkpt_filename = @state.file
        if line.nil?
          # Set breakpoint at current line
          line = @state.line.to_s
        end
      elsif line !~ /^\d+$/
        # See if "line" is a method/function name
        klass = debug_silent_eval(file)
        if klass && klass.kind_of?(Module)
          class_name = klass.name if klass
        else
          errmsg "Unknown class #{file}.\n"
          throw :debug_error
        end
      end

      if line =~ /^\d+$/
        line = line.to_i
        if LineCache.cache(brkpt_filename, Command.settings[:reload_source_on_change])
          last_line = LineCache.size(brkpt_filename)
          if line > last_line
            errmsg \
              "There are only %d lines in file %s\n",
              last_line, brkpt_filename
            return
          end
          unless LineCache.trace_line_numbers(brkpt_filename).member?(line)
            errmsg \
              "Line %d is not a stopping point in file %s\n",
               line, brkpt_filename
            return
          end
        else
          errmsg("No source file named %s\n", brkpt_filename)
          return unless confirm("Set breakpoint anyway? (y/n) ")
        end

        unless @state.context
          errmsg "We are not in a state we can add breakpoints.\n"
          return
        end
        b = Byebug.add_breakpoint brkpt_filename, line, expr
        print "Created breakpoint #{b.id} at " \
              "#{CommandProcessor.canonic_file(brkpt_filename)}:#{line.to_s}\n"
        unless syntax_valid?(expr)
          errmsg "Expression \"#{expr}\" syntactically incorrect; breakpoint" \
                 " disabled.\n"
          b.enabled = false
        end
      else
        method = line.intern
        b = Byebug.add_breakpoint class_name, method, expr
        print "Created breakpoint #{b.id} at #{class_name}::#{method.to_s}\n"
      end
    end

    class << self
      def names
        %w(break)
      end

      def description
        %{
          b[reak] file:line [if expr]
          b[reak] class(.|#)method [if expr]

          Set breakpoint to some position, (optionally) if expr == true
        }
      end
    end
  end

  # Implements byebug "delete" command.
  class DeleteBreakpointCommand < Command
    self.allow_in_control = true

    def regexp
      /^\s *del(?:ete)? (?:\s+(.*))?$/ix
    end

    def execute
      return errmsg "We are not in a state we can delete breakpoints.\n" unless @state.context
      brkpts = @match[1]
      unless brkpts
        if confirm("Delete all breakpoints? (y or n) ")
          Byebug.breakpoints.clear
        end
      else
        brkpts.split(/[ \t]+/).each do |pos|
          pos = get_int(pos, "Delete", 1)
          return unless pos
          unless Byebug.remove_breakpoint(pos)
            errmsg "No breakpoint number %d\n", pos
          end
        end
      end
    end

    class << self
      def names
        %w(delete)
      end

      def description
        %{
          del[ete][ nnn...]

          Without argumen, deletes all breakpoints. With integer numbers,
          deletes specific breakpoints.
        }
      end
    end
  end

end
