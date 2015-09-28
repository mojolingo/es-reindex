class ESReindex
  class ArgsParser

    def self.parse(args)
      remove = false
      update = false
      frame = 1000
      src = nil
      dst = nil
      copy_mappings = true

      while args[0]
        case arg = args.shift
        when '-r' then remove = true
        when '-f' then frame  = args.shift.to_i
        when '-u' then update = true
        when '-nm' then copy_mappings = false
        else
          u = arg.chomp '/'
          !src ? (src = u) : !dst ? (dst = u) :
            raise("Unexpected parameter '#{arg}'. Use '-h' for help.")
        end
      end

      return src, dst, {
        remove: remove,
        frame:  frame,
        update: update,
        copy_mappings: copy_mappings,
      }
    end
  end
end
