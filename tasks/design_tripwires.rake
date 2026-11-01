# frozen_string_literal: true

# Hooks the doc-layer checks into rake (the layout is described in AGENTS.md, "Design docs").
# The bash script is the single implementation; this task only runs it.

desc "Design docs: cited slugs resolve, headings and caps hold, CLAUDE.md is a symlink"
task :design_tripwires do
  sh "design/verify_design_tripwires.sh"
end
