# frozen_string_literal: true

# sample[:cwd]: { pid => working directory } for every process lsof can see.
#
# lsof costs ~0.4 s for the whole machine, so it runs at most every CWD_EVERY seconds and the
# sampler reuses the last map in between (`every:`). A process newer than the map has no cwd until
# the next run. Session labels ("claude 4242 · repo") and the Directory column come from here.
module Agentmon
  module Probes
    module Cwd
      CWD_EVERY = 10
      LSOF = %w[lsof -d cwd -Fpn].freeze

      module_function

      def read(text = IO.popen(LSOF, err: File::NULL, &:read)) = parse(text)

      # lsof -F output: "p<pid>" then "n<path>" lines.
      def parse(text)
        pid = nil
        text.each_line.with_object({}) do |line, cwds|
          case line[0]
          when "p" then pid = line[1..].to_i
          when "n" then cwds[pid] = line[1..].chomp if pid
          end
        end
      end
    end
  end

  probe(:cwd, every: Probes::Cwd::CWD_EVERY) { Probes::Cwd.read }
end
