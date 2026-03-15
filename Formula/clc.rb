class Clc < Formula
  desc "Claude Code Cloak — manage worktrees and Claude files without leaving traces"
  homepage "https://github.com/no-simpler/clc"
  url "https://github.com/no-simpler/clc/releases/download/v1.0.0/clc.sh"
  sha256 "<sha256>"
  version "1.0.0"
  license "MIT"

  def install
    bin.install "clc.sh" => "clc"
  end

  test do
    system "#{bin}/clc", "--version"
  end
end
