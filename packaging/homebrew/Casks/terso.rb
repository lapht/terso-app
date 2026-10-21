cask "terso" do
  version "0.2.0"
  sha256 "e8e07bc58fa88e2d5dfc8ed0cc797361141ccea65ad15dfa156024e761fa3d67"

  # The release ZIP is a universal (arm64 + x86_64) ad-hoc signed build.
  url "https://github.com/lapht/terso-app/releases/download/v#{version}/Terso-v#{version}-macOS.zip"
  name "Terso"
  desc "Open-source disk cleaner with trash-first, audited deletion"
  homepage "https://github.com/lapht/terso-app"

  depends_on macos: :ventura

  app "Terso.app"

  zap trash: "~/Library/Logs/Terso"
end
