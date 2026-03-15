class Clc < Formula
  desc "Claude Code Cloak — manage worktrees and Claude files without leaving traces"
  homepage "https://github.com/no-simpler/clc"
  url "https://github.com/no-simpler/clc/releases/download/v0.1.0/clc.sh"
  sha256 "<sha256>"  # updated per release by publish skill
  version "0.1.0"
  license "MIT"

  def install
    bin.install "clc.sh" => "clc"
  end

  test do
    system "#{bin}/clc", "--version"
  end
end
