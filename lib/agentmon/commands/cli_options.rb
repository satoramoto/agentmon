# frozen_string_literal: true

# Root-level options every `agentmon` command takes, from r2ui's CLI extensions.
#
#   agentmon --version                  agentmon 0.1.0 (also -V, and `agentmon top --version`)
#   agentmon completion zsh             a completion script; also bash and fish:
#     eval "$(agentmon completion zsh)"           in ~/.zshrc, after compinit
#     eval "$(agentmon completion bash)"          in ~/.bashrc
#     agentmon completion fish | source           in ~/.config/fish/config.fish
#   agentmon report --trace             an unexpected error prints its backtrace (and causes)
#   agentmon top --no-color             no colour on a terminal; --color colours a pipe (| less -R)
#
# Without --color/--no-color, colour follows the terminal and NO_COLOR/FORCE_COLOR as usual.
module Agentmon
  cli do
    version Agentmon::VERSION
    completion
    trace_option
    color_option
  end
end
