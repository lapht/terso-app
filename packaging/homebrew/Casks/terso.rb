cask "terso" do
  version "0.2.1"
  sha256 "0a6743b5cd5faa2f45b383f65a76f9d69751350b8e2ccc7c3867b518cbb7f000"

  # The release ZIP is a universal (arm64 + x86_64) ad-hoc signed build.
  url "https://github.com/lapht/terso-app/releases/download/v#{version}/Terso-v#{version}-macOS.zip"
  name "Terso"
  desc "Open-source disk cleaner with trash-first, audited deletion"
  homepage "https://github.com/lapht/terso-app"

  depends_on macos: :ventura

  app "Terso.app"

  zap trash: "~/Library/Logs/Terso"
end
