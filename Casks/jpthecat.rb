cask "jpthecat" do
  version "1.161"
  sha256 "d79d81df2a84b6c1051a6377cf37fb5dceb21a68dd45eef06dd174c3e0552770"

  url "https://github.com/8bittts/JPtheCat/releases/download/v#{version}/JPtheCat-#{version}.dmg"
  name "JP the Cat"
  desc "Menu bar AI coding cost meter"
  homepage "https://github.com/8bittts/JPtheCat"

  livecheck do
    url "https://jpthecat.com/stable/appcast.xml"
    strategy :sparkle, &:short_version
  end

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "JPtheCat.app"

  zap trash: [
    "~/Library/Application Support/com.8bittts.jpthecat",
    "~/Library/Application Support/JPtheCat",
    "~/Library/Caches/com.8bittts.jpthecat",
    "~/Library/Caches/com.8bittts.jpthecat.ShipIt",
    "~/Library/Group Containers/GRNGR33Z8A.com.8bittts.jpthecat",
    "~/Library/HTTPStorages/com.8bittts.jpthecat",
    "~/Library/Preferences/com.8bittts.jpthecat.plist",
    "~/Library/Saved Application State/com.8bittts.jpthecat.savedState",
  ]
end
