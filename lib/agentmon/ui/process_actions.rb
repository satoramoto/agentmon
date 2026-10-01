# frozen_string_literal: true

# Terminate or kill processes from the Processes panel.
#
#   K  terminate: sends TERM (the process may clean up and exit)
#   X  kill: sends KILL (immediate, can't be caught)
#
# Each asks first ("terminate 1 row? y/n"; y sends, any other key cancels). On a group line
# (g: Session, Directory, Name, tree) it signals every process in the group: K on
# "claude 200 · repo" terminates the whole session. pid 0, pid 1 (launchd) and agentmon itself are
# refused ("kill failed: refusing to signal pid 1 (launchd)"); a process that is another user's
# or already gone shows "terminate failed: pid 200 (claude): Operation not permitted" on the
# status bar instead of stopping the dashboard.
module Agentmon
  module UI
    module ProcessActions
      # pid 0 is the kernel, pid 1 launchd: signalling either is never what you meant.
      PROTECTED = [0, 1].freeze

      class << self
        # Delivers a signal: `(signal_name, pid)`. Tests swap it to record instead of signalling.
        attr_accessor :sender

        # Sends `signal` ("TERM", "KILL") to the row's process, or raises Agentmon::Error with the
        # reason (shown as "<action> failed: <reason>").
        def signal(signal, row)
          pid = row.pid
          raise Error, "refusing to signal agentmon itself (pid #{pid})" if pid == Process.pid
          raise Error, "refusing to signal pid #{pid.inspect} (#{row.name})" if pid.nil? || PROTECTED.include?(pid)

          sender.call(signal, pid)
        rescue Errno::EPERM, Errno::ESRCH => e
          raise Error, "pid #{pid} (#{row.name}): #{e.message.sub(/ - .*\z/, "")}"
        end
      end

      self.sender = ->(signal, pid) { Process.kill(signal, pid) }
    end
  end

  extend_resource :process do |_engine|
    action :terminate, key: "K", label: "terminate", confirm: true do |row|
      UI::ProcessActions.signal("TERM", row)
    end
    action :kill, key: "X", label: "kill", confirm: true do |row|
      UI::ProcessActions.signal("KILL", row)
    end
  end
end
