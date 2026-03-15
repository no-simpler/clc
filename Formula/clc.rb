class Clc < Formula
  desc "Claude Code Cloak — manage worktrees and Claude files without leaving traces"
  homepage "https://github.com/no-simpler/clc"
  url "https://github.com/no-simpler/clc/releases/download/v1.0.0/clc.sh"
  sha256 "07e26819e3cc472bced1a212869660f4cbc9ba92ebbd69b7cb928976bd28b43a"
  version "1.0.0"
  license "MIT"

  def install
    bin.install "clc.sh" => "clc"
  end

  test do
    system "#{bin}/clc", "--version"
  end
end
