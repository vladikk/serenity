cask "serenity" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/vladikk/serenity/releases/download/v#{version}/Serenity-#{version}.dmg"
  name "Serenity"
  desc "Menu bar ambient sound mixer"
  homepage "https://github.com/vladikk/serenity"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "Serenity.app"

  uninstall quit: "com.vladikk.Serenity"

  zap trash: "~/Library/Preferences/com.vladikk.Serenity.plist"
end
