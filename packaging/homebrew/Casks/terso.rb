cask "terso" do
  version "0.1.2"
  sha256 "a80d12edd6e795c019b929b9da6421755bc6264fa2d5ec65d1cc2e897ca3659d"

  # The release ZIP is a universal (arm64 + x86_64) ad-hoc signed build.
  url "https://github.com/lapht/terso-app/releases/download/v#{version}/Terso-v#{version}-macOS.zip",
      verified: "github.com/lapht/terso-app/"
  name "Terso"
  desc "Open-source disk cleaner with trash-first, audited deletion"
  homepage "https://github.com/lapht/terso-app"

  depends_on macos: ">= :ventura"

  app "Terso.app"

  zap trash: "~/Library/Logs/Terso"
end
