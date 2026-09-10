# Homebrew cask (tap this repository or copy into your own tap).
# Update version and sha256 from the release's .dmg.sha256 file.
cask "leadsheet-studio" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE"

  url "https://github.com/srm-personal/Impro-Visor/releases/download/v#{version}/Leadsheet-Studio-#{version}.dmg"
  name "Leadsheet Studio"
  desc "Leadsheet editor and jazz play-along engine (port of Impro-Visor)"
  homepage "https://github.com/srm-personal/Impro-Visor/tree/swift-port"

  depends_on macos: ">= :sonoma"

  app "Leadsheet Studio.app"
end
