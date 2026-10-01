# frozen_string_literal: true

# reading[:sessions]: a SessionMap of the agent sessions alive in this sample and which session
# each pid belongs to.
#
# A process belongs to its outermost `claude`/`codex` CLI ancestor (itself included), so shells,
# tools, MCP servers and sub-agents count toward the session that started them. With no CLI
# ancestor, it belongs to the topmost agent desktop app ancestor (Claude, ChatGPT/Codex), so all
# of an app's helpers are one session. Claude Code sessions that the desktop app launches are CLI
# sessions of their own, not part of the app's. Anything else is in no session.
module Agentmon
  module Metrics
    module Sessions
      CLI = /\A(claude|codex)\z/
      APP = /claude|codex|chatgpt/i

      module_function

      def call(processes, cwds)
        processes ||= []
        cwds ||= {}
        by_pid = processes.to_h { |p| [p.pid, p] }
        chains = {}
        sessions = {}
        map = {}
        processes.each do |p|
          cli, app = chain(p, by_pid, chains)
          root = cli || app
          next unless root

          info = sessions[root.pid] ||= info(root, cli ? :cli : :app, cwds)
          map[p.pid] = info.id
        end
        SessionMap.new(sessions: sessions.values, by_pid: map)
      end

      # [outermost CLI ancestor-or-self, topmost app ancestor-or-self], memoized per pid. Walks up
      # iteratively and stops at a cycle (pid 0 is its own parent).
      def chain(process, by_pid, memo)
        path = []
        seen = {}
        node = process
        while node && !memo.key?(node.pid) && !seen[node.pid]
          seen[node.pid] = true
          path << node
          node = by_pid[node.ppid]
        end
        cli, app = node && memo[node.pid]
        path.reverse_each do |n|
          cli ||= n if n.name.match?(CLI)
          app ||= n if n.name.match?(APP)
          memo[n.pid] = [cli, app]
        end
        memo[process.pid]
      end

      def info(root, kind, cwds)
        cwd = cwds[root.pid]
        id = [root.name, root.pid, root.started_at&.to_i].compact.join("-")
        label = if kind == :cli && cwd && cwd != "/"
                  "#{root.name} #{root.pid} · #{File.basename(cwd)}"
                else
                  "#{root.name} #{root.pid}"
                end
        SessionInfo.new(id:, kind:, name: root.name, root_pid: root.pid, label:, cwd:, started_at: root.started_at)
      end
    end
  end

  metric(:sessions) { |reading| Metrics::Sessions.call(reading.sample[:processes], reading.sample[:cwd]) }
end
